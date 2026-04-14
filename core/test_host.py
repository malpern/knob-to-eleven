# eleven test host — runs a test script that drives app.py programmatically.
#
# Unlike host.py (which runs the app in a frame loop until the user closes
# the window), this mode loads a user-supplied test script that calls
# helpers from the `eleven_test` module to inject events, step frames, and
# inspect widget state.
#
# Env vars:
#   ELEVEN_TEST_SCRIPT   absolute path to test script
#   ELEVEN_GEOMETRY      "WxH" (default "100x310")
#   ELEVEN_TEST_SHOW     if non-empty, show the SDL window during the run
#   ELEVEN_CORE_DIR      where wlsdk.py + eleven_test.py live
#   ELEVEN_PLATFORM      passed to wlsdk.sys.get_platform_name()

import os
import sys
import time
import lvgl as lv


def die(msg):
    print("eleven-test: " + msg)
    raise SystemExit(2)


def parse_geom(s):
    try:
        w, h = s.split("x")
        return int(w), int(h)
    except Exception:
        die("invalid geometry " + repr(s))


TEST_SCRIPT = os.getenv("ELEVEN_TEST_SCRIPT") or die("ELEVEN_TEST_SCRIPT not set")
WIDTH, HEIGHT = parse_geom(os.getenv("ELEVEN_GEOMETRY") or "100x310")
SHOW = bool(os.getenv("ELEVEN_TEST_SHOW"))
PLATFORM = os.getenv("ELEVEN_PLATFORM") or "knob-v1"

_core_dir = os.getenv("ELEVEN_CORE_DIR") or "."
if _core_dir not in sys.path:
    sys.path.insert(0, _core_dir)


lv.init()

if SHOW:
    disp = lv.sdl_window_create(WIDTH, HEIGHT)
    lv.sdl_window_set_title(disp, "eleven test")
else:
    # Headless buffer-backed display (RGB565 native = 2 bytes/pixel)
    _disp_buf = bytearray(WIDTH * HEIGHT * 2)
    disp = lv.display_create(WIDTH, HEIGHT)
    disp.set_buffers(_disp_buf, None, len(_disp_buf), lv.DISPLAY_RENDER_MODE.DIRECT)

    def _flush_cb(d, area, px_map):
        d.flush_ready()
    disp.set_flush_cb(_flush_cb)


lv_root = lv.screen_active()

import wlsdk
wlsdk._init(lv_root, platform=PLATFORM)

import eleven_test
eleven_test._install(lv_root, wlsdk, lv, root=os.getenv("ELEVEN_REPO_ROOT") or "")


# --- Run the test script ---
try:
    with open(TEST_SCRIPT) as f:
        src = f.read()
    ns = {
        "__name__": "__main__",
        "__file__": TEST_SCRIPT,
    }
    exec(compile(src, TEST_SCRIPT, "exec"), ns)
    # If test script completes without raising, it passes
    if eleven_test._failed:
        print("FAIL: " + str(eleven_test._failed) + " check(s) failed")
        raise SystemExit(1)
    print("PASS")
except AssertionError as e:
    print("FAIL: " + str(e))
    try:
        sys.print_exception(e)
    except Exception:
        pass
    raise SystemExit(1)
except Exception as e:
    print("ERROR: test raised " + type(e).__name__ + ": " + str(e))
    try:
        sys.print_exception(e)
    except Exception:
        pass
    raise SystemExit(2)
