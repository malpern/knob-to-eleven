# Clock — matches the knob's native lock-screen clock widget.
# Vertical orange→white gradient background; dark rounded-rect card at
# the top shows the current time (large) and date (small).

import os
import lvgl as lv
import wlsdk
import time as _time

_WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
           "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

# Live wall-clock by default. Set ELEVEN_CLOCK_FIXED="9:00|Thu, Apr 4"
# to pin the display (useful for reference-image comparisons).
_FIXED = os.getenv("ELEVEN_CLOCK_FIXED", "")

time_label = None
date_label = None
card = None

# Live tuning — the Mac app writes JSON here whenever any tuning control
# changes. Clock polls the file each frame and re-applies fields that
# changed. Schema: {"card_radius": int, "card_w": int, "card_h": int,
# "card_x": int, "card_y": int}. Any missing field keeps its default.
_TUNING_PATH = "/tmp/eleven_clock_tuning.json"
_last_tuning_mtime = [0]
_last_applied = [{}]


def _now_strings():
    """Returns (time_str, date_str). The colon in the time blinks each
    second (on for even seconds, off for odd) — classic Mac menu-bar
    clock behavior."""
    if _FIXED and "|" in _FIXED:
        t_str, d_str = _FIXED.split("|", 1)
        return (t_str, d_str)
    t = _time.localtime()
    h = t[3] % 12
    if h == 0:
        h = 12
    minute = t[4]
    colon = ":" if (t[5] % 2 == 0) else " "
    wday = _WEEKDAYS[t[6]]
    month = _MONTHS[t[1] - 1]
    day = t[2]
    return ("{}{}{:02d}".format(h, colon, minute),
            "{}, {} {}".format(wday, month, day))


def start():
    global time_label, date_label, card

    scr = lv_root

    # Vertical gradient — orange holds for the upper third, transitions
    # through the middle, ends as a warm cream at the bottom. The stops
    # below are 0..255 positions along the gradient axis.
    # Colors sampled from a photo of the physical device: top is a muted
    # peach-orange, transitioning through cream to near-grey at the base.
    scr.set_style_bg_color(lv.color_hex(0xea9060), 0)
    scr.set_style_bg_grad_color(lv.color_hex(0xe8e3d4), 0)
    scr.set_style_bg_grad_dir(lv.GRAD_DIR.VER, 0)
    scr.set_style_bg_main_stop(80, 0)
    scr.set_style_bg_grad_stop(245, 0)

    # Dark rounded-rect clock card at the top. Matches the native knob
    # widget: squircle-ish corner radius, generous inner padding, warm
    # amber date text on a near-black background.
    card = lv.obj(scr)
    card.set_size(91, 68)
    card.align(lv.ALIGN.TOP_MID, 0, 5)
    card.set_style_bg_color(lv.color_hex(0x0a0a0a), 0)
    card.set_style_bg_opa(255, 0)
    card.set_style_border_width(0, 0)
    card.set_style_radius(20, 0)
    card.set_style_pad_left(7, 0)
    card.set_style_pad_right(7, 0)
    card.set_style_pad_top(6, 0)
    card.set_style_pad_bottom(6, 0)
    card.remove_flag(lv.obj.FLAG.SCROLLABLE)

    time_str, date_str = _now_strings()

    # FONT.BIG resolves to Montserrat-Bold 24 when the simulator build
    # has it compiled in — no faux-bold stacking needed.
    time_label = lv.label(card)
    time_label.set_style_text_font(wlsdk.ui.FONT.BIG, 0)
    time_label.set_style_text_color(lv.color_hex(0xffffff), 0)
    time_label.align(lv.ALIGN.TOP_MID, 0, 9)
    time_label.set_text(time_str)

    # Warm golden-tan date — sampled from the brightest date pixels in a
    # photo of the physical display. Less saturated than a pure amber so
    # it reads as "slightly yellow", matching the native look.
    date_label = lv.label(card)
    date_label.set_style_text_font(wlsdk.ui.FONT.SMALL, 0)
    date_label.set_style_text_color(lv.color_hex(0xd7c35a), 0)
    date_label.align(lv.ALIGN.BOTTOM_MID, 0, -8)
    date_label.set_text(date_str)


_last_time_str = [""]
_last_date_str = [""]


def update():
    # Called each frame. Recompute strings and only touch LVGL when
    # they actually change — which is once a second for the colon
    # blink, and once a minute for everything else.
    time_str, date_str = _now_strings()
    if time_str != _last_time_str[0]:
        _last_time_str[0] = time_str
        time_label.set_text(time_str)
    if date_str != _last_date_str[0]:
        _last_date_str[0] = date_str
        date_label.set_text(date_str)
    _poll_tuning()


def _poll_tuning():
    # Live re-style of the card from the Mac app's tuning panel. File
    # is tiny (<100 bytes) so stat+read every frame is fine.
    try:
        mt = os.stat(_TUNING_PATH)[8]
    except OSError:
        return
    if mt == _last_tuning_mtime[0]:
        return
    _last_tuning_mtime[0] = mt
    try:
        import json as _json
        with open(_TUNING_PATH) as f:
            cfg = _json.loads(f.read())
    except (OSError, ValueError):
        return
    if card is None or not isinstance(cfg, dict):
        return
    prev = _last_applied[0]
    changed = False
    if cfg.get("card_radius") != prev.get("card_radius"):
        card.set_style_radius(int(cfg.get("card_radius", 20)), 0)
        changed = True
    w = cfg.get("card_w", prev.get("card_w", 91))
    h = cfg.get("card_h", prev.get("card_h", 68))
    if w != prev.get("card_w") or h != prev.get("card_h"):
        card.set_size(int(w), int(h))
        changed = True
    x = cfg.get("card_x", prev.get("card_x", 0))
    y = cfg.get("card_y", prev.get("card_y", 5))
    if x != prev.get("card_x") or y != prev.get("card_y"):
        card.align(lv.ALIGN.TOP_MID, int(x), int(y))
        changed = True
    if changed:
        print("clock: applied tuning {}".format(cfg))
        _last_applied[0] = cfg
        card.invalidate()
