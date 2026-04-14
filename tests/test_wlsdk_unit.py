# Direct unit tests for the wlsdk module.
# Verifies the SDK contract everything else builds on:
#   wlsdk.ui.{get,set}_{grab_input, block_input, stay_on_screen, disable_overlay}
#   wlsdk.ui.FONT.{BIG, MEDIUM, SMALL} are LVGL font objects
#   wlsdk.EVENT constants have the documented integer values
#   wlsdk.time.{get_delta, get_elapsed, get_frames}
#   wlsdk.sys.get_platform_name
#   wlsdk.rpc.{register, send_notify, _dispatch}

import eleven_test as t
import wlsdk

# Load a no-op app so the harness is fully wired up
NOOP = "def start(): pass\n"
import os
_TMP = "/tmp/eleven_wlsdk_noop.py"
with open(_TMP, "w") as f:
    f.write(NOOP)
t.load_app(_TMP)
os.remove(_TMP)


# --- wlsdk.ui flags ---
for name in ("grab_input", "block_input", "stay_on_screen", "disable_overlay"):
    getter = getattr(wlsdk.ui, "get_" + name)
    setter = getattr(wlsdk.ui, "set_" + name)
    # Default
    assert getter() is False or getter() == False, "{} default should be False".format(name)
    setter(True)
    assert getter() is True, "{} after set(True)".format(name)
    setter(False)
    assert getter() is False, "{} after set(False)".format(name)
print("  ui flags: ok")


# --- wlsdk.ui.get_root() returns the lv_root we set up ---
assert wlsdk.ui.get_root() is not None
print("  ui.get_root: ok")


# --- wlsdk.ui.FONT slots are present and look like font objects ---
import lvgl as lv
for slot in ("BIG", "MEDIUM", "SMALL"):
    f = getattr(wlsdk.ui.FONT, slot)
    assert f is not None, "FONT.{} missing".format(slot)
print("  ui.FONT: BIG/MEDIUM/SMALL all populated")


# --- wlsdk.EVENT integer constants match documented values ---
assert wlsdk.EVENT.BUTTON == 0
assert wlsdk.EVENT.ENCODER == 1
assert wlsdk.EVENT.BUTTON_DOWN == 0
assert wlsdk.EVENT.BUTTON_UP == 1
assert wlsdk.EVENT.ENCODER_RIGHT == 1
assert wlsdk.EVENT.ENCODER_LEFT == -1
print("  EVENT constants: ok")


# --- wlsdk.time advances on step ---
e0 = wlsdk.time.get_elapsed()
f0 = wlsdk.time.get_frames()
import time as _time
_time.sleep_ms(20)
t.step(1)
e1 = wlsdk.time.get_elapsed()
f1 = wlsdk.time.get_frames()
assert e1 > e0, "elapsed should increase ({} -> {})".format(e0, e1)
assert f1 > f0, "frames should increase ({} -> {})".format(f0, f1)
assert wlsdk.time.get_delta() > 0, "delta should be > 0 after step"
print("  time: get_elapsed/get_frames/get_delta advance correctly")


# --- wlsdk.sys ---
plat = wlsdk.sys.get_platform_name()
assert isinstance(plat, str) and len(plat) > 0
print("  sys.get_platform_name: {!r}".format(plat))


# --- wlsdk.rpc.register + dispatch round-trip ---
calls = []
def my_handler(ctx, params):
    calls.append((ctx, params))

wlsdk.rpc.register("unit.test_method", my_handler)
# Dispatch via the internal _dispatch interface (what the host uses)
ok = wlsdk.rpc._dispatch("unit.test_method", "ctx", {"x": 1})
assert ok, "_dispatch should return True for registered handler"
assert calls == [("ctx", {"x": 1})], "handler should have been called"
# Unknown method returns False, no crash
assert wlsdk.rpc._dispatch("unit.unknown_method", None, None) is False
print("  rpc.register + _dispatch: round trip works")


# --- wlsdk.rpc.send_notify forwards to the host callback (or no-op) ---
notifies = []
def fake_cb(method, payload):
    notifies.append((method, payload))

# Save + restore so we don't poison other tests
prev = wlsdk._state.get("rpc_notify_cb")
wlsdk._state["rpc_notify_cb"] = fake_cb
wlsdk.rpc.send_notify("unit.notify", {"hello": "world"})
wlsdk._state["rpc_notify_cb"] = prev
# send_notify auto-prefixes with "wlsdk."
assert notifies == [("wlsdk.unit.notify", {"hello": "world"})], notifies
print("  rpc.send_notify: forwards via host callback with wlsdk. prefix")


print("wlsdk unit: all sub-APIs behave per spec")
