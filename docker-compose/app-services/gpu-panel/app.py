"""GPU control panel for the domain.com lab.

Runs on the devops container and drives the Tesla P100 through the only host
that can reach everything: the PVE node (nvidia-smi, power limit) and each
container that uses the GPU (llama.cpp, Immich ML, Jellyfin transcoding).
"""

import base64
import json
import os
import secrets
import subprocess

import httpx
from fastapi import Body, Depends, FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials

APP_DIR = os.path.dirname(os.path.abspath(__file__))

PVE_HOST = os.environ.get("PVE_HOST", "root@192.168.10.2")
IMMICH_HOST = os.environ.get("IMMICH_HOST", "root@192.168.10.22")
FRONTEND_HOST = os.environ.get("FRONTEND_HOST", "root@192.168.10.21")
LLAMA_URL = os.environ.get("LLAMA_URL", "http://192.168.10.26:8080")
PANEL_USER = os.environ.get("PANEL_USER", "admin")
PANEL_PASSWORD = os.environ.get("PANEL_PASSWORD", "")

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

# Immich keeps its system config as JSON in system_metadata. Delivered base64
# because the SQL/psql quoting does not survive nested shells otherwise.
IMMICH_CFG_SCRIPT = r"""docker exec immich_postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select value from system_metadata where key = '"'"'system-config'"'"';"'"""

app = FastAPI(title="domain.com GPU control")
security = HTTPBasic()


def require_auth(cred: HTTPBasicCredentials = Depends(security)) -> str:
    if PANEL_PASSWORD:
        ok = secrets.compare_digest(cred.username, PANEL_USER) and secrets.compare_digest(
            cred.password, PANEL_PASSWORD
        )
        if not ok:
            raise HTTPException(401, "unauthorized", headers={"WWW-Authenticate": "Basic"})
    return cred.username


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


def llama_unload_all():
    out = []
    for m in llama_models():
        if m["status"] == "loaded":
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


@app.get("/api/status")
def status(_: str = Depends(require_auth)):
    state = {"gpu": gpu_status()}
    for key, fn in (
        ("llama", llama_models),
        ("immich_ml", immich_ml_state),
        ("immich_ffmpeg", immich_transcode),
        ("jellyfin_accel", jellyfin_accel),
    ):
        try:
            state[key] = fn()
        except Exception as exc:  # noqa: BLE001 - surface each probe failure
            state[key] = {"error": str(exc)}
    return state


@app.post("/api/mode/{mode}")
def set_mode(mode: str, _: str = Depends(require_auth)):
    result = {}
    if mode == "llm":
        result["immich_ml"] = immich_ml("stop")
    elif mode == "media":
        result["llama"] = llama_unload_all()
        result["immich_ml"] = immich_ml("start")
    elif mode == "balanced":
        result["immich_ml"] = immich_ml("start")
    else:
        raise HTTPException(400, "mode must be llm, media or balanced")
    return result


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
