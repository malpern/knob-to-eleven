# Headless host — same lifecycle as host.py, but renders into a raw file
# instead of an SDL window. Used by the SwiftUI app for embedded live
# preview: Swift mmaps the file and displays the framebuffer.
#
# macOS /tmp is memory-backed, so the file acts as de-facto shared memory.
# We use a seqlock-style frame counter so the reader can detect tears.
#
# Env vars (in addition to the ones host.py accepts):
#   ELEVEN_FB_PATH    required — path to the framebuffer file we open+write
#   ELEVEN_FB_FMT     "rgb565" (only supported format today)

import os
import sys
import time
import struct
import lvgl as lv


def die(msg):
    print("eleven-headless: " + msg)
    raise SystemExit(1)


def parse_geom(s):
    try:
        w, h = s.split("x")
        return int(w), int(h)
    except Exception:
        die("invalid geometry " + repr(s))


APP_PATH = os.getenv("ELEVEN_APP_PATH") or die("ELEVEN_APP_PATH not set")
WIDTH, HEIGHT = parse_geom(os.getenv("ELEVEN_GEOMETRY") or "100x310")
FB_PATH = os.getenv("ELEVEN_FB_PATH") or die("ELEVEN_FB_PATH not set")
PLATFORM = os.getenv("ELEVEN_PLATFORM") or "knob-v1"

_this_dir = os.getenv("ELEVEN_CORE_DIR") or "."
if _this_dir not in sys.path:
    sys.path.insert(0, _this_dir)


# --- LVGL setup: buffer-backed display, no SDL window ---
lv.init()
BYTES_PER_PIXEL = 2  # RGB565 native on this build
disp_buf = bytearray(WIDTH * HEIGHT * BYTES_PER_PIXEL)
disp = lv.display_create(WIDTH, HEIGHT)
disp.set_buffers(disp_buf, None, len(disp_buf),
                 lv.DISPLAY_RENDER_MODE.DIRECT)

_dirty_tick = [0]  # writing LVGL itself doesn't tell us when a frame finished


def _flush_cb(d, area, px_map):
    _dirty_tick[0] += 1
    d.flush_ready()


disp.set_flush_cb(_flush_cb)
lv_root = lv.screen_active()


# --- wlsdk wiring ---
import wlsdk
wlsdk._init(lv_root, platform=PLATFORM)


# --- Framebuffer file ---
# Layout (all little-endian):
#   bytes 0..3   frame_counter (u32; updated LAST after pixels are written)
#   bytes 4..7   width (u32)
#   bytes 8..11  height (u32)
#   bytes 12.. pixels (W*H*2 bytes, RGB565)
HEADER_SIZE = 12
FB_SIZE = HEADER_SIZE + WIDTH * HEIGHT * BYTES_PER_PIXEL
fb_file = open(FB_PATH, "wb")
fb_file.write(b"\x00" * FB_SIZE)   # pre-size the file
fb_file.flush()


_header_scratch = bytearray(HEADER_SIZE)
_frame_counter = [0]


def _publish_frame():
    """Write the current LVGL framebuffer to the shared file.
    Pixels first, then the counter, then flush — so a reader seeing a
    new counter can trust the pixels are fully written."""
    _frame_counter[0] = (_frame_counter[0] + 1) & 0xFFFFFFFF
    # Pixels
    fb_file.seek(HEADER_SIZE)
    fb_file.write(disp_buf)
    # Header (counter, width, height) — counter last isn't necessary when
    # we write it all together in a single write, but pack_into keeps it
    # atomic-looking to a reader that just compares the counter field.
    struct.pack_into("<III", _header_scratch, 0,
                     _frame_counter[0], WIDTH, HEIGHT)
    fb_file.seek(0)
    fb_file.write(_header_scratch)
    fb_file.flush()


# --- RPC bridge (same as host.py) ---
WORKER_PORT = int(os.getenv("ELEVEN_WORKER_PORT") or "0")
_worker_sock = None
_worker_buf = b""

if WORKER_PORT:
    import socket as _socket
    import json as _json

    def _connect_worker(port, attempts=60, delay_ms=100):
        addr = _socket.getaddrinfo("127.0.0.1", port)[0][-1]
        for _ in range(attempts):
            s = _socket.socket(_socket.AF_INET, _socket.SOCK_STREAM)
            try:
                s.connect(addr)
                s.setblocking(False)
                return s
            except Exception:
                try: s.close()
                except Exception: pass
                time.sleep_ms(delay_ms)
        return None

    _worker_sock = _connect_worker(WORKER_PORT)
    if _worker_sock:
        print("eleven-headless: worker connected on port " + str(WORKER_PORT))

    def _wlsdk_notify_to_worker(method, payload):
        if _worker_sock is None:
            return
        try:
            line = (_json.dumps({"type": "notify", "method": method,
                                 "params": payload}) + "\n").encode("utf-8")
            _worker_sock.send(line)
        except Exception as e:
            print("eleven-headless: worker send failed: " + str(e))

    wlsdk._state["rpc_notify_cb"] = _wlsdk_notify_to_worker

    def _pump_worker():
        global _worker_buf
        if _worker_sock is None:
            return
        try:
            chunk = _worker_sock.recv(4096)
        except Exception:
            return
        if not chunk:
            return
        _worker_buf += chunk
        while b"\n" in _worker_buf:
            line, _worker_buf = _worker_buf.split(b"\n", 1)
            line = line.strip()
            if not line:
                continue
            try:
                msg = _json.loads(line.decode("utf-8"))
            except Exception:
                continue
            t = msg.get("type")
            if t == "log":
                print("worker: " + str(msg.get("msg", "")))
            elif t == "send_rpc":
                method = msg.get("method", "")
                params = msg.get("params")
                key = method[len("wlsdk."):] if method.startswith("wlsdk.") else method
                handler = wlsdk._RPCState._handlers.get(key) \
                          or wlsdk._RPCState._handlers.get(method)
                if handler is not None:
                    try:
                        handler(None, params)
                    except Exception as e:
                        print("eleven-headless: rpc handler {} raised: {}".format(method, e))
else:
    def _pump_worker():
        pass


# --- App lifecycle (same pattern as host.py) ---
def file_mtime(path):
    try:
        return os.stat(path)[8]
    except Exception:
        return 0


def load_app():
    with open(APP_PATH) as f:
        source = f.read()
    ns = {"__name__": "__main__", "__file__": APP_PATH, "lv_root": lv_root}
    exec(compile(source, APP_PATH, "exec"), ns)
    return ns


def teardown(ns):
    if ns and callable(ns.get("end")):
        try: ns["end"]()
        except Exception as e: print("eleven-headless: end() raised: " + str(e))
    try: lv_root.clean()
    except Exception: pass
    try: wlsdk._reset_widget_state()
    except Exception: pass


def safe_call(fn, *args):
    try:
        fn(*args)
        return True
    except Exception as e:
        print("eleven-headless: unhandled exception in {}: {}".format(fn.__name__, e))
        try: sys.print_exception(e)
        except Exception: pass
        return False


FPS = 60
FRAME_MS = 1000 // FPS
RELOAD_DEBOUNCE_MS = 2000


def run():
    print("eleven-headless: loading " + APP_PATH)
    ns = load_app()
    if callable(ns.get("start")):
        if not safe_call(ns["start"]): ns = None
    current_mtime = file_mtime(APP_PATH)
    change_seen_ms = 0

    print("eleven-headless: running {}x{} -> {}".format(WIDTH, HEIGHT, FB_PATH))
    last = time.ticks_ms()
    while True:
        now = time.ticks_ms()
        dt = time.ticks_diff(now, last)
        if dt < FRAME_MS:
            time.sleep_ms(FRAME_MS - dt)
            continue

        # Hot-reload poll
        mt = file_mtime(APP_PATH)
        if mt != current_mtime:
            if change_seen_ms == 0:
                change_seen_ms = now
            elif time.ticks_diff(now, change_seen_ms) >= RELOAD_DEBOUNCE_MS:
                print("eleven-headless: reloading (mtime changed)")
                teardown(ns)
                current_mtime = mt
                change_seen_ms = 0
                try:
                    ns = load_app()
                    if callable(ns.get("start")):
                        if not safe_call(ns["start"]): ns = None
                except Exception as e:
                    print("eleven-headless: load failed: " + str(e))
                    ns = None
        else:
            change_seen_ms = 0

        _pump_worker()
        wlsdk._Time._advance(now)
        lv.tick_inc(dt)
        lv.task_handler()
        if ns and callable(ns.get("update")):
            if not safe_call(ns["update"]):
                ns = None

        _publish_frame()
        last = now


try:
    run()
except KeyboardInterrupt:
    pass
finally:
    try: fb_file.close()
    except Exception: pass
