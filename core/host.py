# eleven host driver — runs inside MicroPython.
# Sets up the SDL window, imports the user's app.py, calls its lifecycle
# hooks, and hot-reloads when the file changes.
#
# Env vars (set by the `eleven` CLI):
#   ELEVEN_APP_PATH       absolute path to user's app.py
#   ELEVEN_GEOMETRY       "WxH" (default "170x320")
#   ELEVEN_TITLE          window title (default: basename of app)
#   ELEVEN_PLATFORM       wlsdk.sys.get_platform_name() value
#   ELEVEN_WORKER_PORT    optional TCP port (127.0.0.1) for worker.py bridge

import os
import sys
import time
import lvgl as lv


def die(msg):
    print("eleven: " + msg)
    raise SystemExit(1)


def parse_geom(s):
    try:
        w, h = s.split("x")
        return int(w), int(h)
    except Exception:
        die("invalid geometry " + repr(s) + " (expected WxH like 170x320)")


APP_PATH = os.getenv("ELEVEN_APP_PATH") or die("ELEVEN_APP_PATH not set")
WIDTH, HEIGHT = parse_geom(os.getenv("ELEVEN_GEOMETRY") or "170x320")
TITLE = os.getenv("ELEVEN_TITLE") or "eleven"
PLATFORM = os.getenv("ELEVEN_PLATFORM") or "nomad-v1"


# --- Make `wlsdk` importable (lives next to this file) ---
_this_dir = os.getenv("ELEVEN_CORE_DIR") or "."
if _this_dir not in sys.path:
    sys.path.insert(0, _this_dir)


# --- Set up LVGL with SDL window ---
lv.init()
disp = lv.sdl_window_create(WIDTH, HEIGHT)
lv.sdl_window_set_title(disp, TITLE)
lv.sdl_mouse_create()
kb_indev = lv.sdl_keyboard_create()
wheel_indev = lv.sdl_mousewheel_create()

lv_root = lv.screen_active()

# --- Wire wlsdk ---
import wlsdk
wlsdk._init(lv_root, platform=PLATFORM)


# --- RPC bridge to worker.py over TCP loopback ---
WORKER_PORT = int(os.getenv("ELEVEN_WORKER_PORT") or "0")
_worker_sock = None
_worker_buf = b""
_worker_notify_subs = set()  # methods the worker has subscribed to

if WORKER_PORT:
    import socket as _socket
    import json as _json

    def _connect_worker(port, attempts=60, delay_ms=100):
        # Worker has to do a Python cold start + bind the port; be
        # generous (60 * 100ms = 6s) before giving up.
        # MicroPython's socket.connect needs a getaddrinfo-derived
        # binary address (not a (host, port) tuple).
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
        print("eleven: worker connected on port " + str(WORKER_PORT))
    else:
        print("eleven: WARN worker did not become reachable on port " + str(WORKER_PORT))

    def _worker_send(obj):
        if _worker_sock is None:
            return
        try:
            line = (_json.dumps(obj) + "\n").encode("utf-8")
            _worker_sock.send(line)
        except Exception as e:
            print("eleven: worker send failed: " + str(e))

    def _wlsdk_notify_to_worker(method, payload):
        # method already prefixed with wlsdk. by wlsdk.rpc.send_notify
        _worker_send({"type": "notify", "method": method, "params": payload})

    wlsdk._state["rpc_notify_cb"] = _wlsdk_notify_to_worker

    def _pump_worker():
        """Drain any inbound bytes from the worker, dispatch full lines.
        Socket is non-blocking; recv raises OSError(EAGAIN) when empty."""
        global _worker_buf
        if _worker_sock is None:
            return
        # Drain whatever's available right now without blocking.
        try:
            chunk = _worker_sock.recv(4096)
        except Exception:
            # No data ready (EAGAIN) or other transient error
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
                print("eleven: bad JSON from worker")
                continue
            t = msg.get("type")
            if t == "log":
                print("worker: " + str(msg.get("msg", "")))
            elif t == "register_notify":
                _worker_notify_subs.add(msg.get("method", ""))
            elif t == "send_rpc":
                # Dispatch to a wlsdk.rpc.register'd handler on device side
                method = msg.get("method", "")
                params = msg.get("params")
                handler = wlsdk._RPCState._handlers.get(
                    method[len("wlsdk."):] if method.startswith("wlsdk.") else method
                )
                if handler is None:
                    # Try with full method name as a fallback
                    handler = wlsdk._RPCState._handlers.get(method)
                if handler is not None:
                    try:
                        # ctx is opaque per the SDK API; we pass None for now
                        handler(None, params)
                    except Exception as e:
                        print("eleven: rpc handler {} raised: {}".format(method, e))
else:
    def _pump_worker():
        pass


# --- Input: forward keyboard + wheel events as SDK on_event(type, idx, val) ---
# Keyboard mapping:
#   Enter / Space       -> BUTTON index 0
#   "1"..."9"           -> BUTTON index 1..9  (for multi-button devices)
#   Left  / Mouse wheel down -> ENCODER index 0, ENCODER_LEFT  (-1)
#   Right / Mouse wheel up   -> ENCODER index 0, ENCODER_RIGHT (+1)
#
# LVGL delivers key events through the indev's group. We install a group,
# focus lv_root, and forward EVENT.KEY / EVENT.CLICKED on lv_root.

_indev_group = lv.group_create()
kb_indev.set_group(_indev_group)
wheel_indev.set_group(_indev_group)


def _deliver_on_event(etype, idx, val):
    """Call user's on_event if defined; swallow exceptions so one bad
    handler doesn't take down the window."""
    app_ns = _current_app.get("ns")
    if not app_ns:
        return
    fn = app_ns.get("on_event")
    if not callable(fn):
        return
    try:
        fn(etype, idx, val)
    except Exception as e:
        print("eleven: on_event raised: " + str(e))
        try:
            sys.print_exception(e)
        except Exception:
            pass


_BTN_KEYS = {
    lv.KEY.ENTER: 0,
    ord(" "): 0,
    ord("1"): 1, ord("2"): 2, ord("3"): 3, ord("4"): 4, ord("5"): 5,
    ord("6"): 6, ord("7"): 7, ord("8"): 8, ord("9"): 9,
}


def _key_event_cb(e):
    code = e.get_code()
    indev = lv.indev_active()
    if indev is None:
        return

    # LVGL's keypad indev emits KEY events with the numeric key code.
    # The encoder (mousewheel) also uses this indev family but reports
    # KEY.NEXT / KEY.PREV for +/-.
    if code == lv.EVENT.KEY:
        key = indev.get_key()
        if key == lv.KEY.RIGHT or key == lv.KEY.NEXT:
            _deliver_on_event(wlsdk.EVENT.ENCODER, 0, wlsdk.EVENT.ENCODER_RIGHT)
        elif key == lv.KEY.LEFT or key == lv.KEY.PREV:
            _deliver_on_event(wlsdk.EVENT.ENCODER, 0, wlsdk.EVENT.ENCODER_LEFT)
        elif key in _BTN_KEYS:
            _deliver_on_event(wlsdk.EVENT.BUTTON, _BTN_KEYS[key], wlsdk.EVENT.BUTTON_DOWN)
    elif code == lv.EVENT.RELEASED:
        key = indev.get_key()
        if key in _BTN_KEYS:
            _deliver_on_event(wlsdk.EVENT.BUTTON, _BTN_KEYS[key], wlsdk.EVENT.BUTTON_UP)


# Shared handle so _key_event_cb can reach the live app namespace even
# across hot reloads.
_current_app = {"ns": None}

# Input sink lives on the top layer, which survives screen cleans during
# hot reload.
_top = lv.layer_top()
_input_sink = lv.obj(_top)
_input_sink.set_size(1, 1)
_input_sink.set_style_bg_opa(0, 0)
_input_sink.set_style_border_width(0, 0)
_input_sink.add_event_cb(_key_event_cb, lv.EVENT.ALL, None)
# First add_obj auto-focuses the object
_indev_group.add_obj(_input_sink)


# --- File-mtime tracking for hot reload ---
def file_mtime(path):
    try:
        return os.stat(path)[8]  # index 8 = mtime in MicroPython os.stat
    except Exception:
        return 0


# --- Load and execute app.py ---
def load_app():
    """Compile and execute app.py. Returns its namespace."""
    with open(APP_PATH) as f:
        source = f.read()
    ns = {
        "__name__": "__main__",
        "__file__": APP_PATH,
        "lv_root": lv_root,
    }
    exec(compile(source, APP_PATH, "exec"), ns)
    return ns


def teardown(ns):
    """Best-effort cleanup when reloading or exiting."""
    if ns and callable(ns.get("end")):
        try:
            ns["end"]()
        except Exception as e:
            print("eleven: end() raised: " + str(e))
    # Wipe screen children so the next app starts with a clean slate
    try:
        lv_root.clean()
    except Exception:
        pass
    # Reset wlsdk module-scope state (RPC handlers, ui flags)
    try:
        wlsdk._reset_widget_state()
    except Exception:
        pass


def safe_call(fn, *args):
    try:
        fn(*args)
        return True
    except Exception as e:
        # Print traceback-ish; MicroPython has sys.print_exception
        print("eleven: unhandled exception in {}: {}".format(fn.__name__, e))
        try:
            sys.print_exception(e)
        except Exception:
            pass
        return False


# --- Main loop ---
FPS = 60
FRAME_MS = 1000 // FPS
RELOAD_DEBOUNCE_MS = 2000  # match device firmware behavior


def run():
    print("eleven: loading " + APP_PATH)
    ns = load_app()
    _current_app["ns"] = ns
    if callable(ns.get("start")):
        if not safe_call(ns["start"]):
            ns = None
            _current_app["ns"] = None
    current_mtime = file_mtime(APP_PATH)
    change_seen_ms = 0

    print("eleven: running at {}x{}, {} fps".format(WIDTH, HEIGHT, FPS))
    last = time.ticks_ms()
    while True:
        now = time.ticks_ms()
        dt = time.ticks_diff(now, last)
        if dt < FRAME_MS:
            time.sleep_ms(FRAME_MS - dt)
            continue

        # Poll mtime for hot reload
        mt = file_mtime(APP_PATH)
        if mt != current_mtime:
            if change_seen_ms == 0:
                change_seen_ms = now
            elif time.ticks_diff(now, change_seen_ms) >= RELOAD_DEBOUNCE_MS:
                print("eleven: reloading (mtime changed)")
                teardown(ns)
                _current_app["ns"] = None
                current_mtime = mt
                change_seen_ms = 0
                try:
                    ns = load_app()
                    _current_app["ns"] = ns
                    if callable(ns.get("start")):
                        if not safe_call(ns["start"]):
                            ns = None
                            _current_app["ns"] = None
                except Exception as e:
                    print("eleven: load failed: " + str(e))
                    try:
                        sys.print_exception(e)
                    except Exception:
                        pass
                    ns = None
                    _current_app["ns"] = None
        else:
            change_seen_ms = 0

        # Pump worker.py messages (no-op if no worker)
        _pump_worker()

        wlsdk._Time._advance(now)
        lv.tick_inc(dt)
        lv.task_handler()
        if ns and callable(ns.get("update")):
            if not safe_call(ns["update"]):
                # per device semantics, halt the frame loop (keep window open
                # so the user sees the error overlay / can fix the file)
                ns = None
        last = now


try:
    run()
except KeyboardInterrupt:
    print("\neleven: interrupted")
