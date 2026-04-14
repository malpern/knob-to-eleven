# eleven host driver — runs inside MicroPython.
# Sets up the SDL window, imports the user's app.py, calls its lifecycle
# hooks, and hot-reloads when the file changes.
#
# Env vars (set by the `eleven` CLI):
#   ELEVEN_APP_PATH   absolute path to user's app.py
#   ELEVEN_GEOMETRY   "WxH" (default "170x320")
#   ELEVEN_TITLE      window title (default: basename of app)
#   ELEVEN_PLATFORM   wlsdk.sys.get_platform_name() value (default "nomad-v1")

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
lv.sdl_keyboard_create()

lv_root = lv.screen_active()


# --- Wire wlsdk ---
import wlsdk
wlsdk._init(lv_root, platform=PLATFORM)


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
    if callable(ns.get("start")):
        if not safe_call(ns["start"]):
            ns = None  # halt update per SDK semantics
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
                # debounce elapsed — reload
                print("eleven: reloading (mtime changed)")
                teardown(ns)
                current_mtime = mt
                change_seen_ms = 0
                try:
                    ns = load_app()
                    if callable(ns.get("start")):
                        if not safe_call(ns["start"]):
                            ns = None
                except Exception as e:
                    print("eleven: load failed: " + str(e))
                    try:
                        sys.print_exception(e)
                    except Exception:
                        pass
                    ns = None
        else:
            change_seen_ms = 0

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
