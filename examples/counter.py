# Counter — demonstrates on_event(). Turn the encoder to adjust.
# Press Enter/Space to reset.
#
# Simulator keybindings (see core/host.py):
#   Left / Right arrow    -> encoder -/+
#   Mouse wheel up/down   -> encoder +/-
#   Enter / Space         -> button 0
#   1..9                  -> button 1..9

import lvgl as lv
import wlsdk

value = 0
label = None
hint = None


def _render():
    label.set_text(str(value))


def start():
    global label, hint
    scr = lv_root
    scr.set_style_bg_color(lv.color_hex(0x000000), 0)

    label = lv.label(scr)
    label.set_style_text_font(wlsdk.ui.FONT.BIG, 0)
    label.set_style_text_color(lv.color_hex(0xff8800), 0)
    label.align(lv.ALIGN.CENTER, 0, -10)
    _render()

    hint = lv.label(scr)
    hint.set_style_text_font(wlsdk.ui.FONT.SMALL, 0)
    hint.set_style_text_color(lv.color_hex(0x888888), 0)
    hint.align(lv.ALIGN.BOTTOM_MID, 0, -14)
    hint.set_text("turn: change\npress: reset")
    hint.set_style_text_align(lv.TEXT_ALIGN.CENTER, 0)

    wlsdk.ui.set_grab_input(True)


def on_event(event_type, event_index, event_value):
    global value
    if event_type == wlsdk.EVENT.ENCODER:
        value += event_value
        _render()
    elif event_type == wlsdk.EVENT.BUTTON and event_value == wlsdk.EVENT.BUTTON_DOWN:
        value = 0
        _render()
