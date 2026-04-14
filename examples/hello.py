# Hello — a real Work Louder SDK-shaped app.py.
# Demonstrates: lifecycle hooks, lv_root, wlsdk.ui.FONT, wlsdk.time,
# wlsdk.sys, and per-frame animation via get_delta().

import lvgl as lv
import wlsdk

arc = None
label = None
footer = None


def start():
    global arc, label, footer
    scr = lv_root
    scr.set_style_bg_color(lv.color_hex(0x000000), 0)

    arc = lv.arc(scr)
    arc.set_size(140, 140)
    arc.align(lv.ALIGN.CENTER, 0, -40)
    arc.set_range(0, 100)
    arc.set_value(0)
    arc.set_style_arc_color(lv.color_hex(0xff8800), lv.PART.INDICATOR)
    arc.set_style_arc_color(lv.color_hex(0x333333), lv.PART.MAIN)
    arc.set_style_arc_width(12, lv.PART.INDICATOR)
    arc.set_style_arc_width(12, lv.PART.MAIN)

    label = lv.label(scr)
    label.set_style_text_font(wlsdk.ui.FONT.BIG, 0)
    label.set_style_text_color(lv.color_hex(0xffffff), 0)
    label.align(lv.ALIGN.CENTER, 0, 75)
    label.set_text("0%")

    footer = lv.label(scr)
    footer.set_style_text_font(wlsdk.ui.FONT.SMALL, 0)
    footer.set_style_text_color(lv.color_hex(0x888888), 0)
    footer.align(lv.ALIGN.BOTTOM_MID, 0, -12)
    footer.set_text(wlsdk.sys.get_platform_name())


def update():
    # 25% / second
    elapsed = wlsdk.time.get_elapsed()
    pct = int((elapsed * 25) % 101)
    arc.set_value(pct)
    label.set_text("{}%".format(pct))


def end():
    print("hello.py: end()")
