"""GPU control panel for the domain.com lab.

Runs on the devops container and drives the Tesla P100 through the only host
that can reach everything: the PVE node (nvidia-smi, power limit) and each
container that uses the GPU (llama.cpp, Immich ML, Jellyfin transcoding).

Auth is a login page that sets a signed session cookie, plus the bearer token
for automation; there is no HTTP basic challenge, so browsers never pop up the
native credentials dialog.
"""

import asyncio
import base64
import contextlib
import hashlib
import hmac
import json
import os
import secrets
import subprocess
import time
from collections import deque
from urllib.parse import urlparse

import httpx
from fastapi import Body, Depends, FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse

APP_DIR = os.path.dirname(os.path.abspath(__file__))

PVE_HOST = os.environ.get("PVE_HOST", "root@192.168.10.2")
IMMICH_HOST = os.environ.get("IMMICH_HOST", "root@192.168.10.22")
FRONTEND_HOST = os.environ.get("FRONTEND_HOST", "root@192.168.10.21")
LLAMA_URL = os.environ.get("LLAMA_URL", "http://192.168.10.26:8080")
PANEL_USER = os.environ.get("PANEL_USER", "admin")
PANEL_PASSWORD = os.environ.get("PANEL_PASSWORD", "")
PANEL_TOKEN = os.environ.get("PANEL_TOKEN", "")
SESSION_COOKIE = os.environ.get("SESSION_COOKIE", "panel_session")
SESSION_TTL = int(os.environ.get("SESSION_TTL", 7 * 24 * 3600))
LOGIN_DELAY = float(os.environ.get("LOGIN_DELAY", 0.4))
STATE_PATH = os.environ.get("STATE_PATH", "/state/auto.json")

# NVENC is the only Jellyfin mode that touches the P100, the card it shares with
# llama.cpp and Immich ML. VAAPI runs on the Intel iGPU, a different device that
# costs the P100 nothing, so it is what Jellyfin falls back to when the LLM owns
# the card: dropping it to CPU would lose hardware transcoding for no reason.
# JELLYFIN_FALLBACK=none restores the old CPU behaviour on purpose.
JELLYFIN_FALLBACK = os.environ.get("JELLYFIN_FALLBACK", "vaapi")
JELLYFIN_DEVICES = {"nvenc": "P100 (NVENC)", "vaapi": "iGPU (VAAPI)", "none": "CPU"}
if JELLYFIN_FALLBACK not in ("vaapi", "none"):
    JELLYFIN_FALLBACK = "vaapi"

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

DEFAULTS = {"enabled": True, "llama_idle_min": 60, "ml_idle_min": 0, "last_action": None, "last_action_at": None, "revoked": {}, "jellyfin_before_llm": None}

# Sessions are signed with a key derived from the credentials, so rotating
# either one logs every browser out and no extra secret has to be provisioned.
SESSION_KEY = hashlib.sha256(f"session|{PANEL_PASSWORD}|{PANEL_TOKEN}".encode()).digest()

state = dict(DEFAULTS)
busy_samples = deque(maxlen=240)
last_busy = time.time()
llm_blocked = False

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
# auth: login page -> signed session cookie; bearer token for automation
# --------------------------------------------------------------------------- #
def _b64e(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _b64d(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def is_https(request: Request) -> bool:
    return request.headers.get("x-forwarded-proto", request.url.scheme) == "https"


def make_session(user: str) -> str:
    payload = {"u": user, "exp": int(time.time()) + SESSION_TTL, "n": secrets.token_urlsafe(12)}
    body = _b64e(json.dumps(payload, separators=(",", ":")).encode())
    sig = _b64e(hmac.new(SESSION_KEY, body.encode(), hashlib.sha256).digest())
    return f"{body}.{sig}"


def session_payload(request: Request) -> dict:
    """Verified session payload, or {} when the cookie is absent/invalid/revoked."""
    raw = request.cookies.get(SESSION_COOKIE, "")
    body, _, sig = raw.partition(".")
    if not body or not sig:
        return {}
    expected = _b64e(hmac.new(SESSION_KEY, body.encode(), hashlib.sha256).digest())
    if not secrets.compare_digest(sig, expected):
        return {}
    try:
        payload = json.loads(_b64d(body))
    except Exception:
        return {}
    if int(payload.get("exp", 0)) < time.time():
        return {}
    if payload.get("n") in state.get("revoked", {}):
        return {}
    return payload


def read_session(request: Request) -> str:
    return str(session_payload(request).get("u") or "")


def has_bearer(request: Request) -> bool:
    header = request.headers.get("authorization", "")
    return bool(PANEL_TOKEN) and (
        secrets.compare_digest(header, f"Bearer {PANEL_TOKEN}")
        or secrets.compare_digest(request.headers.get("x-api-token", ""), PANEL_TOKEN)
    )


def require_auth(request: Request) -> str:
    if has_bearer(request):
        return "token"
    user = read_session(request)
    if user:
        # Cookie-authenticated writes must come from this same origin.
        if request.method not in ("GET", "HEAD", "OPTIONS"):
            origin = request.headers.get("origin")
            if origin and urlparse(origin).netloc != request.headers.get("host", ""):
                raise HTTPException(403, "cross-origin request rejected")
        return user
    raise HTTPException(401, "unauthorized")


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


def jellyfin_ensure_accel(accel):
    if jellyfin_accel() == accel:
        return {"accel": accel, "already": True}
    return jellyfin_set_accel(accel)


def jellyfin_release_p100():
    """Move Jellyfin off the P100 while keeping hardware transcoding: the iGPU.

    The chosen accel is remembered so the way back puts Jellyfin on the device it
    had before, instead of assuming NVENC.
    """
    current = jellyfin_accel()
    if current in ("nvenc", "vaapi"):
        state["jellyfin_before_llm"] = current
    return jellyfin_ensure_accel(JELLYFIN_FALLBACK)


def jellyfin_reclaim_p100():
    """Undo jellyfin_release_p100() once llama.cpp gives the card back."""
    accel = state.get("jellyfin_before_llm") or "nvenc"
    state["jellyfin_before_llm"] = None
    return jellyfin_ensure_accel(accel)


def auto_snapshot():
    return {
        "enabled": state["enabled"],
        "llama_idle_min": state["llama_idle_min"],
        "ml_idle_min": state["ml_idle_min"],
        "last_action": state.get("last_action"),
        "last_action_at": state.get("last_action_at"),
        "idle_seconds": int(time.time() - last_busy),
        "llm_blocked": llm_blocked,
    }


def record_action(text):
    state["last_action"] = text
    state["last_action_at"] = time.strftime("%Y-%m-%d %H:%M:%S")
    save_state()


# --------------------------------------------------------------------------- #
# auto switch
# --------------------------------------------------------------------------- #
def auto_tick():
    global last_busy, llm_blocked
    util = int(gpu_status()["util"])
    busy_samples.append(util)
    if util > 0:
        last_busy = time.time()
    if not state["enabled"]:
        return
    idle = time.time() - last_busy

    try:
        models = llama_loaded()
    except Exception:
        models = []

    if models:
        if state["llama_idle_min"] and idle > state["llama_idle_min"] * 60:
            unloaded = llama_unload_all()
            if unloaded:
                back = {"accel": state.get("jellyfin_before_llm") or "nvenc"}
                with contextlib.suppress(HTTPException):
                    immich_ml("start")
                    back = jellyfin_reclaim_p100()
                llm_blocked = False
                record_action("GPU idle %d min: unloaded %s, Immich ML on, Jellyfin back to %s"
                              % (idle // 60, [u["model"] for u in unloaded], JELLYFIN_DEVICES.get(back.get("accel"), back.get("accel"))))
        elif not llm_blocked:
            with contextlib.suppress(HTTPException):
                immich_ml("stop")        # Immich ML is CUDA: it needs the P100
                jellyfin_release_p100()  # Jellyfin keeps transcoding on the iGPU
            llm_blocked = True
            record_action("LLM in use: Immich ML stopped, Jellyfin on %s (P100 free for llama.cpp)"
                          % JELLYFIN_DEVICES[JELLYFIN_FALLBACK])
    else:
        llm_blocked = False

    if state["ml_idle_min"] and idle > state["ml_idle_min"] * 60:
        if immich_ml_state() == "running" and immich_ml_queue_active() == 0:
            with contextlib.suppress(HTTPException):
                immich_ml("stop")
            record_action("Immich ML idle %d min: stopped to free VRAM" % (idle // 60))


async def auto_loop():
    while True:
        with contextlib.suppress(Exception):
            await asyncio.to_thread(auto_tick)
        await asyncio.sleep(20)


@app.on_event("startup")
async def _startup():
    load_state()
    asyncio.create_task(auto_loop())


# --------------------------------------------------------------------------- #
# pages
# --------------------------------------------------------------------------- #
NO_STORE = {"Cache-Control": "no-store"}


@app.get("/login")
def login_page():
    return FileResponse(os.path.join(APP_DIR, "static", "login.html"), headers=NO_STORE)


@app.get("/")
def index(request: Request):
    if not (read_session(request) or has_bearer(request)):
        return RedirectResponse("/login", status_code=303)
    return FileResponse(os.path.join(APP_DIR, "static", "index.html"), headers=NO_STORE)


@app.post("/api/login")
def login(request: Request, body: dict = Body(...)):
    user = str(body.get("user") or "").strip()
    password = str(body.get("password") or "")
    ok = bool(PANEL_PASSWORD) and secrets.compare_digest(user, PANEL_USER) and secrets.compare_digest(password, PANEL_PASSWORD)
    if not ok:
        time.sleep(LOGIN_DELAY)
        raise HTTPException(401, "usuario o contraseña incorrectos")
    response = JSONResponse({"ok": True, "user": user})
    response.set_cookie(
        SESSION_COOKIE,
        make_session(user),
        max_age=SESSION_TTL,
        httponly=True,
        samesite="lax",
        secure=is_https(request),
        path="/",
    )
    return response


@app.post("/api/logout")
def logout(request: Request):
    payload = session_payload(request)
    if payload.get("n"):
        # Sessions are stateless, so "Salir" has to remember the nonce until it
        # would have expired anyway.
        revoked = {n: exp for n, exp in state.get("revoked", {}).items() if int(exp) > time.time()}
        revoked[str(payload["n"])] = int(payload.get("exp") or time.time())
        state["revoked"] = revoked
        save_state()
    response = JSONResponse({"ok": True})
    response.delete_cookie(SESSION_COOKIE, path="/")
    return response


@app.get("/api/session")
def session_info(request: Request):
    if has_bearer(request):
        return {"authenticated": True, "user": "token", "mode": "token"}
    user = read_session(request)
    return {"authenticated": bool(user), "user": user or None, "mode": "session" if user else None}


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
    global llm_blocked
    result = {}
    if mode == "llm":
        result["immich_ml"] = immich_ml("stop")        # CUDA: it needs the P100
        result["jellyfin"] = jellyfin_release_p100()   # iGPU keeps transcoding
        llm_blocked = True
        record_action("mode LLM: Immich ML stopped, Jellyfin on %s (P100 free for llama.cpp)"
                      % JELLYFIN_DEVICES[JELLYFIN_FALLBACK])
    elif mode == "media":
        result["llama"] = llama_unload_all()
        result["immich_ml"] = immich_ml("start")
        result["jellyfin"] = jellyfin_ensure_accel("nvenc")
        state["jellyfin_before_llm"] = None
        llm_blocked = False
        record_action("mode Media: llama.cpp unloaded, Immich ML + Jellyfin (NVENC on the P100) on")
    elif mode == "balanced":
        result["immich_ml"] = immich_ml("start")
        result["jellyfin"] = jellyfin_ensure_accel("nvenc")
        state["jellyfin_before_llm"] = None
        llm_blocked = False
        record_action("mode Shared: Immich ML + Jellyfin (NVENC on the P100, LLM not unloaded) on")
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
