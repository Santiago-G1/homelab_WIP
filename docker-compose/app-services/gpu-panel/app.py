"""GPU control panel for the domain.com lab.

Runs on the devops container and drives the Tesla P100 through the only host
that can reach everything: the PVE node (nvidia-smi, power limit) and each
container that uses the GPU (llama.cpp, Immich ML, Jellyfin transcoding).
"""

import asyncio
import base64
import contextlib
import json
import os
import secrets
import subprocess
import time
from collections import deque

import httpx
from fastapi import Body, Depends, FastAPI, HTTPException, Request
from fastapi.responses import FileResponse

APP_DIR = os.path.dirname(os.path.abspath(__file__))

PVE_HOST = os.environ.get("PVE_HOST", "root@192.168.10.2")
IMMICH_HOST = os.environ.get("IMMICH_HOST", "root@192.168.10.22")
FRONTEND_HOST = os.environ.get("FRONTEND_HOST", "root@192.168.10.21")
LLAMA_URL = os.environ.get("LLAMA_URL", "http://192.168.10.26:8080")
PANEL_USER = os.environ.get("PANEL_USER", "admin")
PANEL_PASSWORD = os.environ.get("PANEL_PASSWORD", "")
PANEL_TOKEN = os.environ.get("PANEL_TOKEN", "")
STATE_PATH = os.environ.get("STATE_PATH", "/state/auto.json")

IMMICH_ML = "immich_machine_learning"
JELLYFIN_XML = "/opt/docker/jellyfin/config/encoding.xml"
GPU_FIELDS = (
    "name,driver_version,memory.used,memory.total,utilization.gpu,temperature.gpu,"
    "power.draw,power.limit,power.default_limit,power.min_limit,power.max_limit,"
    "clocks.current.sm,clocks.current.memory"
)
GPU_KEYS = [
    "name", "driver", "mem_used", "mem_total", "util", "temp", "power_draw",
    "power_limit", "power_default", "power_min", "power_max", "clk_sm", "clk_mem",
]
ML_QUEUES = ("faceDetection", "smartSearch", "ocr")

# Immich keeps its system config as JSON in system_metadata. Delivered base64
# because the SQL/psql quoting does not survive nested shells otherwise.
IMMICH_CFG_SCRIPT = r"""docker exec immich_postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select value from system_metadata where key = '"'"'system-config'"'"';"'"""

DEFAULTS = {"enabled": True, "llama_idle_min": 15, "ml_idle_min": 0, "last_action": None, "last_action_at": None}

state = dict(DEFAULTS)
busy_samples = deque(maxlen=240)
last_busy = time.time()

app = FastAPI(title="domain.com GPU control")


# --------------------------------------------------------------------------- #
# state
# --------------------------------------------------------------------------- #
def load_state():
    try:
        with open(STATE_PATH) as fh:
            state.update({k: v for k, v in json.load(fh).items() if k in DEFAULTS})
    except Exception:
        pass


def save_state():
    with contextlib.suppress(Exception):
        os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
        with open(STATE_PATH, "w") as fh:
            json.dump(state, fh, indent=2)


# --------------------------------------------------------------------------- #
# auth: HTTP basic for the browser, bearer token for automation
# --------------------------------------------------------------------------- #
def require_auth(request: Request) -> str:
    header = request.headers.get("authorization", "")
    if PANEL_TOKEN and (
        secrets.compare_digest(header, f"Bearer {PANEL_TOKEN}")
        or secrets.compare_digest(request.headers.get("x-api-token", ""), PANEL_TOKEN)
    ):
        return "token"
    if PANEL_PASSWORD and header.startswith("Basic "):
        try:
            user, _, password = base64.b64decode(header[6:]).decode().partition(":")
        except Exception:
            user = password = ""
        if secrets.compare_digest(user, PANEL_USER) and secrets.compare_digest(password, PANEL_PASSWORD):
            return user
    raise HTTPException(401, "unauthorized", headers={"WWW-Authenticate": "Basic"})


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #
def run(cmd, timeout=30, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kwargs)


def ssh(host, command, timeout=30):
    return run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6", host, command], timeout)


def ssh_script(host, script, timeout=60):
    payload = base64.b64encode(script.encode()).decode()
    return run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=6", host, "base64 -d | sh"],
        timeout,
        input=payload,
    )


def gpu_status():
    p = ssh(PVE_HOST, f"nvidia-smi --query-gpu={GPU_FIELDS} --format=csv,noheader,nounits")
    if p.returncode != 0:
        raise HTTPException(502, f"nvidia-smi failed: {p.stderr.strip() or p.stdout.strip()}")
    row = [v.strip() for v in p.stdout.splitlines()[0].split(",")]
    gpu = dict(zip(GPU_KEYS, row))
    pr = ssh(PVE_HOST, "nvidia-smi --query-compute-apps=pid,process_name,used_memory --format=csv,noheader,nounits")
    procs = []
    for line in pr.stdout.splitlines():
        parts = [x.strip() for x in line.split(",")]
        if len(parts) == 3 and parts[0].isdigit():
            procs.append({"pid": parts[0], "name": parts[1], "mem_mib": int(parts[2])})
    gpu["processes"] = procs
    return gpu


def llama_models():
    r = httpx.get(f"{LLAMA_URL}/v1/models", timeout=8)
    r.raise_for_status()
    return [
        {"id": m.get("id"), "status": (m.get("status") or {}).get("value", "unknown")}
        for m in r.json().get("data", [])
    ]


def llama_loaded():
    return [m for m in llama_models() if m["status"] == "loaded"]


def llama_unload_all():
    out = []
    for m in llama_loaded():
        r = httpx.post(f"{LLAMA_URL}/models/unload", json={"model": m["id"]}, timeout=60)
        out.append({"model": m["id"], "http": r.status_code})
    return out


def immich_ml_state():
    p = ssh(IMMICH_HOST, f"docker inspect -f '{{{{.State.Status}}}}' {IMMICH_ML}")
    return p.stdout.strip() or "unknown"


def immich_ml(action):
    p = ssh(IMMICH_HOST, f"docker {action} {IMMICH_ML}")
    if p.returncode != 0:
        raise HTTPException(502, p.stderr.strip() or p.stdout.strip())
    return {"action": action, "ok": True}


def immich_ml_queue_active():
    script = "\n".join(
        f'echo "$(docker exec immich_redis redis-cli llen immich_bull:{q}:active) $(docker exec immich_redis redis-cli llen immich_bull:{q}:wait)"'
        for q in ML_QUEUES
    )
    p = ssh_script(IMMICH_HOST, script)
    total = 0
    for line in p.stdout.split():
        if line.isdigit():
            total += int(line)
    return total


def immich_transcode():
    p = ssh_script(IMMICH_HOST, IMMICH_CFG_SCRIPT)
    try:
        return json.loads(p.stdout).get("ffmpeg", {})
    except Exception:
        return {"error": (p.stdout or p.stderr).strip()[:200]}


def jellyfin_accel():
    p = ssh(FRONTEND_HOST, f"sed -n 's:.*<HardwareAccelerationType>\\([^<]*\\).*:\\1:p' {JELLYFIN_XML}")
    return p.stdout.strip() or "unknown"


def jellyfin_set_accel(accel):
    if accel not in ("nvenc", "vaapi", "none"):
        raise HTTPException(400, "accel must be nvenc, vaapi or none")
    script = (
        "set -e\n"
        f"F={JELLYFIN_XML}\n"
        "docker stop jellyfin >/dev/null\n"
        "sed -i 's#<HardwareAccelerationType>[^<]*</HardwareAccelerationType>"
        f"#<HardwareAccelerationType>{accel}</HardwareAccelerationType>#' \"$F\"\n"
        "docker start jellyfin >/dev/null\n"
    )
    p = ssh_script(FRONTEND_HOST, script)
    if p.returncode != 0:
        raise HTTPException(502, p.stderr.strip() or p.stdout.strip())
    return {"accel": accel}


def auto_snapshot():
    return {
        "enabled": state["enabled"],
        "llama_idle_min": state["llama_idle_min"],
        "ml_idle_min": state["ml_idle_min"],
        "last_action": state.get("last_action"),
        "last_action_at": state.get("last_action_at"),
        "idle_seconds": int(time.time() - last_busy),
    }


def record_action(text):
    state["last_action"] = text
    state["last_action_at"] = time.strftime("%Y-%m-%d %H:%M:%S")
    save_state()


# --------------------------------------------------------------------------- #
# auto switch
# --------------------------------------------------------------------------- #
def auto_tick():
    global last_busy
    util = int(gpu_status()["util"])
    busy_samples.append(util)
    if util > 0:
        last_busy = time.time()
    if not state["enabled"]:
        return
    idle = time.time() - last_busy

    if state["llama_idle_min"] and idle > state["llama_idle_min"] * 60:
        if llama_loaded():
            unloaded = llama_unload_all()
            if unloaded:
                with contextlib.suppress(HTTPException):
                    immich_ml("start")
                record_action("GPU idle %d min: unloaded %s, Immich ML on" % (idle // 60, [u["model"] for u in unloaded]))

    if state["ml_idle_min"] and idle > state["ml_idle_min"] * 60:
        if immich_ml_state() == "running" and immich_ml_queue_active() == 0:
            with contextlib.suppress(HTTPException):
                immich_ml("stop")
            record_action("Immich ML idle %d min: stopped to free VRAM" % (idle // 60))


async def auto_loop():
    while True:
        with contextlib.suppress(Exception):
            await asyncio.to_thread(auto_tick)
        await asyncio.sleep(30)


@app.on_event("startup")
async def _startup():
    load_state()
    asyncio.create_task(auto_loop())


# --------------------------------------------------------------------------- #
# api
# --------------------------------------------------------------------------- #
@app.get("/api/status")
def status(_: str = Depends(require_auth)):
    out = {"gpu": gpu_status(), "auto": auto_snapshot()}
    for key, fn in (
        ("llama", llama_models),
        ("immich_ml", immich_ml_state),
        ("immich_ffmpeg", immich_transcode),
        ("jellyfin_accel", jellyfin_accel),
    ):
        try:
            out[key] = fn()
        except Exception as exc:  # noqa: BLE001 - surface each probe failure
            out[key] = {"error": str(exc)}
    return out


@app.post("/api/mode/{mode}")
def set_mode(mode: str, _: str = Depends(require_auth)):
    result = {}
    if mode == "llm":
        result["immich_ml"] = immich_ml("stop")
        record_action("mode LLM: Immich ML stopped")
    elif mode == "media":
        result["llama"] = llama_unload_all()
        result["immich_ml"] = immich_ml("start")
        record_action("mode Media: llama.cpp unloaded, Immich ML on")
    elif mode == "balanced":
        result["immich_ml"] = immich_ml("start")
        record_action("mode Shared: Immich ML on")
    else:
        raise HTTPException(400, "mode must be llm, media or balanced")
    return result


@app.post("/api/auto")
def set_auto(body: dict = Body(...), _: str = Depends(require_auth)):
    if "enabled" in body:
        state["enabled"] = bool(body["enabled"])
    for key in ("llama_idle_min", "ml_idle_min"):
        if key in body:
            value = int(body[key])
            if value < 0 or value > 1440:
                raise HTTPException(400, f"{key} must be 0..1440 minutes")
            state[key] = value
    save_state()
    return auto_snapshot()


@app.post("/api/power")
def set_power(body: dict = Body(...), _: str = Depends(require_auth)):
    try:
        watts = int(body.get("watts"))
    except (TypeError, ValueError):
        raise HTTPException(400, "watts must be an integer")
    if not 125 <= watts <= 250:
        raise HTTPException(400, "watts must be between 125 and 250")
    p = ssh(PVE_HOST, f"nvidia-smi -pl {watts}")
    if p.returncode != 0:
        raise HTTPException(502, p.stderr.strip() or p.stdout.strip())
    record_action(f"power limit = {watts} W")
    return {"ok": True, "watts": watts}


@app.post("/api/llama/unload")
def llama_unload(_: str = Depends(require_auth)):
    return {"unloaded": llama_unload_all()}


@app.post("/api/immich/ml/{action}")
def immich_ml_action(action: str, _: str = Depends(require_auth)):
    if action not in ("start", "stop", "restart"):
        raise HTTPException(400, "action must be start, stop or restart")
    return immich_ml(action)


@app.post("/api/jellyfin/accel/{accel}")
def jellyfin_accel_action(accel: str, _: str = Depends(require_auth)):
    return jellyfin_set_accel(accel)


@app.get("/")
def index(_: str = Depends(require_auth)):
    return FileResponse(os.path.join(APP_DIR, "static", "index.html"))
