# Hello — a real Work Louder SDK-shaped app.py.
# Demonstrates: lifecycle hooks, lv_root, wlsdk.ui.FONT, wlsdk.time,
# wlsdk.sys, and per-frame animation via get_delta().

import lvgl as lv
import wlsdk

arc = None
label = None


def start():
    global arc, label
    scr = lv_root
    scr.set_style_bg_color(lv.color_hex(0x000000), 0)

    arc = lv.arc(scr)
    arc.set_size(84, 84)             # fits 100-wide knob screen
    arc.align(lv.ALIGN.CENTER, 0, -50)
    arc.set_range(0, 100)
    arc.set_value(0)
    arc.set_rotation(270)
    arc.set_bg_angles(0, 360)
    arc.remove_style(None, lv.PART.KNOB)  # hide the LVGL drag handle
    arc.remove_flag(lv.obj.FLAG.CLICKABLE)
    arc.set_style_arc_color(lv.color_hex(0xff8800), lv.PART.INDICATOR)
    arc.set_style_arc_color(lv.color_hex(0x333333), lv.PART.MAIN)
    arc.set_style_arc_width(8, lv.PART.INDICATOR)
    arc.set_style_arc_width(8, lv.PART.MAIN)

    label = lv.label(scr)
    label.set_style_text_font(wlsdk.ui.FONT.BIG, 0)
    label.set_style_text_color(lv.color_hex(0xffffff), 0)
    label.align(lv.ALIGN.CENTER, 0, 30)
    label.set_text("0%")



def update():
    # 25% / second
    elapsed = wlsdk.time.get_elapsed()
    pct = int((elapsed * 25) % 101)
    arc.set_value(pct)
    label.set_text("{}%".format(pct))


def end():
    print("hello.py: end()")
