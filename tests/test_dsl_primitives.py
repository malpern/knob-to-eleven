# Direct unit tests for eleven_dsl primitives. Each primitive should
# create the right LVGL widget type with theme defaults applied.
#
# Loads a small inline app via load_app() so the test harness already
# has lv_root + wlsdk wired up.

import eleven_test as t
import lvgl as lv

# Tiny app that creates one of each primitive so we can inspect them.
SCRATCH_APP = """
from eleven_dsl import theme, screen, dial, bar, label, segment, plate, indicator

dial_w = bar_w = label_w = seg_w = plate_w = ind_on = ind_off = None

def start():
    global dial_w, bar_w, label_w, seg_w, plate_w, ind_on, ind_off
    scr = screen()
    dial_w  = dial(scr, value=42, value_range=(0, 100), align="top")
    bar_w   = bar(scr, value=33, value_range=(0, 100), align="center", offset_y=-40)
    label_w = label(scr, text="hello", align="center")
    seg_w   = segment(scr, text="12:34", align="center", offset_y=40)
    plate_w = plate(scr, width=80, height=24, align="bottom", offset_y=-40)
    ind_on  = indicator(scr, on=True,  align="bottom_left", offset_x=10, offset_y=-10)
    ind_off = indicator(scr, on=False, align="bottom_right", offset_x=-10, offset_y=-10)
"""

# Persist the app to a temp file, load it
import os
_TMP = "/tmp/eleven_dsl_scratch.py"
with open(_TMP, "w") as f:
    f.write(SCRATCH_APP)
ns = t.load_app(_TMP)

# --- The screen got 7 widgets ---
ws = t.all_widgets()
assert len(ws) == 7, "expected 7 widgets, got {} ({})".format(
    len(ws), [type(w).__name__ for w in ws])

# --- dial → lv.arc with value 42, range 0-100 ---
dial_w = ns["dial_w"]
assert isinstance(dial_w, lv.arc), "dial must produce lv.arc"
assert dial_w.get_value() == 42, "dial value"
assert dial_w.get_min_value() == 0 and dial_w.get_max_value() == 100, "dial range"

# --- bar → lv.bar with value 33 ---
bar_w = ns["bar_w"]
assert isinstance(bar_w, lv.bar), "bar must produce lv.bar"
assert bar_w.get_value() == 33, "bar value"
assert bar_w.get_min_value() == 0 and bar_w.get_max_value() == 100, "bar range"

# --- label → lv.label with text ---
assert isinstance(ns["label_w"], lv.label)
assert ns["label_w"].get_text() == "hello"

# --- segment is a label with the BIG font (today; will diverge later) ---
assert isinstance(ns["seg_w"], lv.label)
assert ns["seg_w"].get_text() == "12:34"

# --- plate → lv.obj with the right size ---
plate_w = ns["plate_w"]
assert isinstance(plate_w, lv.obj)
assert plate_w.get_width() == 80, "plate width"
assert plate_w.get_height() == 24, "plate height"

# --- indicator → lv.obj, on/off variants differ in bg color ---
ind_on, ind_off = ns["ind_on"], ns["ind_off"]
assert isinstance(ind_on, lv.obj)
assert isinstance(ind_off, lv.obj)
# Both should be 8x8 by default
assert ind_on.get_width() == 8 and ind_on.get_height() == 8
assert ind_off.get_width() == 8 and ind_off.get_height() == 8

# --- Theme color override actually applies ---
SCRATCH2 = """
from eleven_dsl import dial, theme
custom = None
def start():
    global custom
    custom = dial(lv_root, color=0x44CC88)
"""
with open(_TMP, "w") as f:
    f.write(SCRATCH2)
ns2 = t.load_app(_TMP)
os.remove(_TMP)
custom_arc = ns2["custom"]
# Indicator color should now be the green we passed, not the default orange.
got = custom_arc.get_style_arc_color(lv.PART.INDICATOR)
assert got.red == 0x44 and got.green == 0xCC and got.blue == 0x88, \
    "expected (0x44, 0xCC, 0x88), got ({:02x}, {:02x}, {:02x})".format(
        got.red, got.green, got.blue)

print("dsl primitives: bar/plate/indicator created correctly, theme overrides work")
