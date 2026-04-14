# eleven render host — load an app, advance N frames, write a PNG.
#
# Env vars:
#   ELEVEN_APP_PATH   absolute path to app.py
#   ELEVEN_GEOMETRY   "WxH" (default 170x320)
#   ELEVEN_FRAMES     number of frames to advance (default 1)
#   ELEVEN_FRAME_MS   ms per frame for tick_inc (default 16 for 60fps)
#   ELEVEN_OUT        output PNG path (required)
#   ELEVEN_PRE_EVENTS comma-separated synthetic events to feed before
#                     the final frame, e.g. "encoder:+3,button:0,encoder:-1"
#   ELEVEN_CORE_DIR   wlsdk.py location
#   ELEVEN_PLATFORM   wlsdk.sys.get_platform_name() value

import os
import sys
import struct
import lvgl as lv


def die(msg):
    print("eleven-render: " + msg)
    raise SystemExit(2)


APP = os.getenv("ELEVEN_APP_PATH") or die("ELEVEN_APP_PATH not set")
OUT = os.getenv("ELEVEN_OUT") or die("ELEVEN_OUT not set")
FRAMES = int(os.getenv("ELEVEN_FRAMES") or "1")
FRAME_MS = int(os.getenv("ELEVEN_FRAME_MS") or "16")
PRE = os.getenv("ELEVEN_PRE_EVENTS") or ""
PLATFORM = os.getenv("ELEVEN_PLATFORM") or "nomad-v1"

geom = os.getenv("ELEVEN_GEOMETRY") or "170x320"
W, H = (int(x) for x in geom.split("x"))

_core = os.getenv("ELEVEN_CORE_DIR") or "."
if _core not in sys.path:
    sys.path.insert(0, _core)


# --- Headless buffer-backed display (RGB565 native on this build) ---
lv.init()
BYTES_PER_PIXEL = 2  # RGB565
buf = bytearray(W * H * BYTES_PER_PIXEL)
disp = lv.display_create(W, H)
disp.set_buffers(buf, None, len(buf), lv.DISPLAY_RENDER_MODE.DIRECT)


def _flush(d, area, px_map):
    d.flush_ready()


disp.set_flush_cb(_flush)

lv_root = lv.screen_active()
import wlsdk
wlsdk._init(lv_root, platform=PLATFORM)


# --- Load the app ---
with open(APP) as f:
    src = f.read()
ns = {"__name__": "__main__", "__file__": APP, "lv_root": lv_root}
exec(compile(src, APP, "exec"), ns)
if callable(ns.get("start")):
    ns["start"]()


def step(n=1):
    import time as t
    for _ in range(n):
        wlsdk._Time._advance(t.ticks_ms())
        lv.tick_inc(FRAME_MS)
        lv.task_handler()
        if callable(ns.get("update")):
            ns["update"]()


# Initial layout pass
step(1)


# --- Inject pre-events ---
def parse_events(s):
    """Parse "encoder:+3,button:0,encoder:-1" into list of (kind, n)."""
    if not s:
        return []
    out = []
    for chunk in s.split(","):
        kind, _, val = chunk.strip().partition(":")
        out.append((kind, val))
    return out


for kind, val in parse_events(PRE):
    if kind == "encoder":
        n = int(val)
        ev = wlsdk.EVENT.ENCODER_RIGHT if n > 0 else wlsdk.EVENT.ENCODER_LEFT
        for _ in range(abs(n)):
            if callable(ns.get("on_event")):
                ns["on_event"](wlsdk.EVENT.ENCODER, 0, ev)
        step(1)
    elif kind == "button":
        idx = int(val)
        if callable(ns.get("on_event")):
            ns["on_event"](wlsdk.EVENT.BUTTON, idx, wlsdk.EVENT.BUTTON_DOWN)
            ns["on_event"](wlsdk.EVENT.BUTTON, idx, wlsdk.EVENT.BUTTON_UP)
        step(1)
    elif kind == "step":
        step(int(val))
    elif kind == "rpc":
        # Format: rpc:method.name:value
        # value is parsed as a number if possible, then wrapped as
        # {"value": N} — the convention the canonical apps use. For more
        # complex RPC payloads, add a richer event grammar later.
        method, _, raw = val.partition(":")
        if not method or not raw:
            die("rpc event must be 'rpc:method:value', got: " + repr(val))
        try:
            value = float(raw) if "." in raw else int(raw)
        except ValueError:
            value = raw
        handler = wlsdk._RPCState._handlers.get(method)
        if handler is None:
            die("no handler registered for RPC method " + repr(method))
        handler(None, {"value": value})
        step(1)
    else:
        die("unknown pre-event kind: " + repr(kind))


# --- Advance the requested frames ---
step(FRAMES)


# --- Write PPM (sips converts to PNG afterward) ---
# Buffer is RGB565 little-endian. Each pixel is two bytes:
#   byte[0] = GGGB BBBB (low byte)
#   byte[1] = RRRR RGGG (high byte)
# Combined uint16 = RRRR_RGGG_GGGB_BBBB
ppm = bytearray()
ppm.extend("P6\n{} {}\n255\n".format(W, H).encode())
for i in range(0, len(buf), 2):
    lo = buf[i]
    hi = buf[i + 1]
    px = (hi << 8) | lo
    r5 = (px >> 11) & 0x1F
    g6 = (px >> 5) & 0x3F
    b5 = px & 0x1F
    # Scale to 8-bit (use the standard "shift and OR top bits" trick for
    # accurate full-range mapping)
    r = (r5 << 3) | (r5 >> 2)
    g = (g6 << 2) | (g6 >> 4)
    b = (b5 << 3) | (b5 >> 2)
    ppm.append(r)
    ppm.append(g)
    ppm.append(b)

ppm_path = OUT + ".ppm"
with open(ppm_path, "wb") as f:
    f.write(ppm)

# Sanity: did anything render?
nonzero = sum(1 for x in buf if x != 0)
if nonzero == 0:
    die("framebuffer is entirely zero — did the app render?")

print("eleven-render: wrote {} ({} non-zero bytes)".format(ppm_path, nonzero))
