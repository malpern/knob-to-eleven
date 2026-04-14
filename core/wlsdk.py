# wlsdk — stub implementation of Work Louder's MicroPython SDK module.
#
# Matches the device-side surface documented in docs/wlsdk-api-surface.md.
# Host (eleven's host.py) is responsible for calling _init() before the
# user's app.py is loaded, and _advance_time() each frame.
#
# Sub-APIs: wlsdk.ui, wlsdk.ui.FONT, wlsdk.EVENT, wlsdk.time, wlsdk.sys,
# wlsdk.rpc

import lvgl as lv


# --- internal state set by host ---
_state = {
    "lv_root": None,
    "platform": "knob-v1",
    "rpc_notify_cb": None,  # host sets this to forward notifications to worker.py
}


def _init(lv_root_obj, platform="knob-v1", rpc_notify_cb=None):
    _state["lv_root"] = lv_root_obj
    _state["platform"] = platform
    _state["rpc_notify_cb"] = rpc_notify_cb
    _Time._start_ms = None  # reset


def _reset_widget_state():
    """Called on hot reload — reset flags so a fresh app starts clean."""
    ui._grab_input = False
    ui._block_input = False
    ui._stay_on_screen = False
    ui._disable_overlay = False
    _RPCState._handlers = {}


# --- wlsdk.ui ---
class _UI:
    _grab_input = False
    _block_input = False
    _stay_on_screen = False
    _disable_overlay = False

    @staticmethod
    def get_root():
        return _state["lv_root"]

    # grab_input
    @classmethod
    def get_grab_input(cls): return cls._grab_input
    @classmethod
    def set_grab_input(cls, v): cls._grab_input = bool(v)

    # block_input
    @classmethod
    def get_block_input(cls): return cls._block_input
    @classmethod
    def set_block_input(cls, v): cls._block_input = bool(v)

    # stay_on_screen
    @classmethod
    def get_stay_on_screen(cls): return cls._stay_on_screen
    @classmethod
    def set_stay_on_screen(cls, v): cls._stay_on_screen = bool(v)

    # disable_overlay
    @classmethod
    def get_disable_overlay(cls): return cls._disable_overlay
    @classmethod
    def set_disable_overlay(cls, v): cls._disable_overlay = bool(v)


# wlsdk.ui.FONT — three firmware-registered LVGL fonts. The simulator
# substitutes LVGL's bundled Montserrat fonts at similar sizes until we have
# the actual device fonts extracted.
def _pick_font(name_preferred):
    for n in name_preferred:
        if hasattr(lv, n):
            return getattr(lv, n)
    return lv.font_get_default()


class _Fonts:
    BIG = _pick_font(["font_montserrat_24", "font_montserrat_bold_24", "font_montserrat_22"])
    MEDIUM = _pick_font(["font_montserrat_16", "font_montserrat_14"])
    SMALL = _pick_font(["font_montserrat_12", "font_montserrat_10", "font_montserrat_14"])


ui = _UI()
ui.FONT = _Fonts()


# --- wlsdk.EVENT ---
class EVENT:
    BUTTON = 0
    ENCODER = 1
    BUTTON_DOWN = 0
    BUTTON_UP = 1
    ENCODER_RIGHT = 1
    ENCODER_LEFT = -1


# --- wlsdk.time ---
class _Time:
    _start_ms = None
    _last_ms = 0
    _delta = 0.0
    _frames = 0

    @classmethod
    def _advance(cls, now_ms):
        if cls._start_ms is None:
            cls._start_ms = now_ms
            cls._last_ms = now_ms
            cls._delta = 0.0
            cls._frames = 0
            return
        cls._delta = (now_ms - cls._last_ms) / 1000.0
        cls._last_ms = now_ms
        cls._frames += 1

    @classmethod
    def get_delta(cls): return cls._delta

    @classmethod
    def get_elapsed(cls):
        if cls._start_ms is None: return 0.0
        return (cls._last_ms - cls._start_ms) / 1000.0

    @classmethod
    def get_frames(cls): return cls._frames


time = _Time


# --- wlsdk.sys ---
class _Sys:
    @staticmethod
    def get_platform_name():
        return _state["platform"]


sys = _Sys()


# --- wlsdk.rpc ---
class _RPCState:
    _handlers = {}


class _RPC:
    @staticmethod
    def register(method, callback):
        _RPCState._handlers[method] = callback

    @staticmethod
    def send_response(ctx, body):
        # host bridge will route; for now print for visibility
        print("rpc response: ctx={} body={!r}".format(ctx, body))

    @staticmethod
    def send_error(ctx, code, message):
        print("rpc error: ctx={} code={} msg={!r}".format(ctx, code, message))

    @staticmethod
    def send_notify(method, payload):
        full = "wlsdk." + method
        cb = _state.get("rpc_notify_cb")
        if cb:
            cb(full, payload)
        else:
            print("rpc notify: {} payload={!r}".format(full, payload))

    @staticmethod
    def _dispatch(method, ctx, params):
        """Called by the host when an incoming RPC arrives (for
        eventual worker.py → device direction). Not used yet."""
        handler = _RPCState._handlers.get(method)
        if handler is None:
            return False
        try:
            handler(ctx, params)
        except Exception as e:
            print("rpc handler for {} raised: {}".format(method, e))
        return True


rpc = _RPC()
