# mac_live — scrolling CPU sparkline + animated big % number.
#
# Demonstrates:
#   - Live host data via RPC (worker.py polls top(1), pushes every 500ms)
#   - Scrolling sparkline over the last ~30 samples (LVGL chart)
#   - Smooth per-frame number animation between samples (get_delta-based)

import lvgl as lv
import wlsdk
from eleven_dsl import theme, screen

N_SAMPLES = 60  # sparkline history depth

big_num = None
label_unit = None
title = None
chart = None
series = None

# Animation state
displayed = 0.0   # what's on screen right now
target = 0.0      # latest sample — displayed eases toward this
history = []      # ring buffer of samples


def start():
    global big_num, label_unit, title, chart, series

    scr = screen()

    # Header
    title = lv.label(scr)
    title.set_text("CPU")
    title.set_style_text_color(lv.color_hex(theme.muted), 0)
    title.set_style_text_font(wlsdk.ui.FONT.SMALL, 0)
    title.align(lv.ALIGN.TOP_MID, 0, 12)

    # Sparkline (lv.chart) — sized for the knob's 100-wide screen
    chart = lv.chart(scr)
    chart.set_size(84, 60)
    chart.align(lv.ALIGN.CENTER, 0, -50)
    chart.set_type(lv.chart.TYPE.LINE)
    chart.set_axis_range(lv.chart.AXIS.PRIMARY_Y, 0, 100)
    chart.set_point_count(N_SAMPLES)
    chart.set_style_bg_opa(0, 0)
    chart.set_style_border_width(0, 0)
    chart.set_style_pad_all(0, 0)
    chart.set_style_line_width(2, lv.PART.ITEMS)
    chart.set_style_line_color(lv.color_hex(theme.accent), lv.PART.ITEMS)

    series = chart.add_series(
        lv.color_hex(theme.accent), lv.chart.AXIS.PRIMARY_Y
    )
    # Seed with zeroes so the line starts at the bottom
    for _ in range(N_SAMPLES):
        chart.set_next_value(series, 0)

    # Big number
    big_num = lv.label(scr)
    big_num.set_style_text_font(wlsdk.ui.FONT.BIG, 0)
    big_num.set_style_text_color(lv.color_hex(theme.fg), 0)
    big_num.align(lv.ALIGN.CENTER, 0, 30)
    big_num.set_text("0")

    # Unit label ("%") right of the big number
    label_unit = lv.label(scr)
    label_unit.set_style_text_font(wlsdk.ui.FONT.MEDIUM, 0)
    label_unit.set_style_text_color(lv.color_hex(theme.muted), 0)
    label_unit.align_to(big_num, lv.ALIGN.OUT_RIGHT_BOTTOM, 2, -2)
    label_unit.set_text("%")


def on_cpu_update(ctx, params):
    global target, history
    if isinstance(params, dict) and "value" in params:
        v = float(params["value"])
        target = max(0.0, min(100.0, v))
        history.append(target)
        if len(history) > N_SAMPLES:
            history = history[-N_SAMPLES:]
        # Push new point into the chart's ring buffer; it auto-scrolls
        chart.set_next_value(series, int(target))


def update():
    global displayed
    # Smoothly ease the displayed number toward target. Rate of 4x
    # per second approach (ease_out-ish: faster when far from target).
    dt = wlsdk.time.get_delta()
    diff = target - displayed
    if abs(diff) < 0.1:
        displayed = target
    else:
        displayed += diff * min(1.0, dt * 6.0)
    big_num.set_text(str(int(displayed)))


wlsdk.rpc.register("cpu.update", on_cpu_update)
