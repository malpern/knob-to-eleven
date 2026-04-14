# eleven_test — helpers available to test scripts.
#
# Usage from a test script:
#
#     import eleven_test as t
#     t.load_app("examples/counter.py")
#     t.step()
#     assert t.find_label_text() == "0"
#     t.inject_encoder(+1)
#     t.step()
#     assert t.find_label_text() == "1"
#
# Test scripts run under test_host.py which calls _install() before
# exec'ing them.

import lvgl as _lv_unused  # placeholder until _install sets the real references

# Populated by test_host.py at startup
_state = {
    "lv_root": None,
    "wlsdk": None,
    "lv": None,
    "app_ns": None,
}
_failed = 0


def _install(lv_root, wlsdk, lv_mod):
    _state["lv_root"] = lv_root
    _state["wlsdk"] = wlsdk
    _state["lv"] = lv_mod


# --- App lifecycle ---

def load_app(path):
    """Load an app.py, call start(). Replaces any previously-loaded app."""
    lv = _state["lv"]
    lv_root = _state["lv_root"]
    wlsdk = _state["wlsdk"]

    # Unload previous app first
    if _state["app_ns"]:
        prev = _state["app_ns"]
        if callable(prev.get("end")):
            try: prev["end"]()
            except Exception as e: print("warn: end() raised:", e)
    try:
        lv_root.clean()
    except Exception:
        pass
    try:
        wlsdk._reset_widget_state()
    except Exception:
        pass

    with open(path) as f:
        src = f.read()
    ns = {"__name__": "__main__", "__file__": path, "lv_root": lv_root}
    exec(compile(src, path, "exec"), ns)
    _state["app_ns"] = ns

    if callable(ns.get("start")):
        ns["start"]()

    # Initial frame so widgets are laid out
    step(1)
    return ns


def step(frames=1, frame_ms=16):
    """Advance the LVGL clock by `frames` frames, running update() each frame."""
    import time as _time
    lv = _state["lv"]
    wlsdk = _state["wlsdk"]
    ns = _state["app_ns"]

    for _ in range(frames):
        now_ms = _time.ticks_ms()
        wlsdk._Time._advance(now_ms)
        lv.tick_inc(frame_ms)
        lv.task_handler()
        if ns and callable(ns.get("update")):
            ns["update"]()


# --- Event injection (synthesizes the same on_event(type, idx, val) calls
# the device firmware makes — bypasses SDL entirely). ---

def inject_encoder(diff, index=0):
    """Synthesize one or more encoder events. diff > 0 = RIGHT, < 0 = LEFT."""
    wlsdk = _state["wlsdk"]
    ns = _state["app_ns"]
    if not ns or not callable(ns.get("on_event")):
        return
    if diff == 0:
        return
    step_val = wlsdk.EVENT.ENCODER_RIGHT if diff > 0 else wlsdk.EVENT.ENCODER_LEFT
    for _ in range(abs(diff)):
        ns["on_event"](wlsdk.EVENT.ENCODER, index, step_val)


def inject_button(index=0, state="press"):
    """Synthesize a button event.
    state: "down", "up", or "press" (down + up pair)."""
    wlsdk = _state["wlsdk"]
    ns = _state["app_ns"]
    if not ns or not callable(ns.get("on_event")):
        return
    if state == "press":
        ns["on_event"](wlsdk.EVENT.BUTTON, index, wlsdk.EVENT.BUTTON_DOWN)
        ns["on_event"](wlsdk.EVENT.BUTTON, index, wlsdk.EVENT.BUTTON_UP)
    elif state == "down":
        ns["on_event"](wlsdk.EVENT.BUTTON, index, wlsdk.EVENT.BUTTON_DOWN)
    elif state == "up":
        ns["on_event"](wlsdk.EVENT.BUTTON, index, wlsdk.EVENT.BUTTON_UP)
    else:
        raise ValueError("inject_button state must be 'down', 'up', or 'press'")


# --- Widget inspection ---

def _walk(obj, out):
    try:
        count = obj.get_child_count()
    except Exception:
        return
    for i in range(count):
        child = obj.get_child(i)
        if child is not None:
            out.append(child)
            _walk(child, out)


def all_widgets():
    """Flat list of all widgets under lv_root, depth-first."""
    out = []
    _walk(_state["lv_root"], out)
    return out


def find_labels():
    """Return all lv.label instances and their text."""
    lv = _state["lv"]
    result = []
    for w in all_widgets():
        # Labels expose get_text(); use duck typing.
        try:
            t = w.get_text()
            result.append((w, t))
        except Exception:
            pass
    return result


def find_label_text(index=0):
    """Text of the Nth label (depth-first order). Raises IndexError if none."""
    labels = find_labels()
    if index >= len(labels):
        raise IndexError("no label at index {} (found {})".format(index, len(labels)))
    return labels[index][1]


def find_label_with_text(substring):
    """First label whose text contains the substring, or None."""
    for w, t in find_labels():
        if substring in t:
            return w
    return None


def dump_tree():
    """Print the widget tree for debugging."""
    ws = all_widgets()
    print("widgets ({}):".format(len(ws)))
    for w in ws:
        text = ""
        try: text = " text=" + repr(w.get_text())
        except Exception: pass
        print("  {}{}".format(type(w).__name__, text))
