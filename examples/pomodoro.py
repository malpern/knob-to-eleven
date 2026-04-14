# Pomodoro — classic 25/5 timer.
#
# States:
#   IDLE      — show duration; encoder adjusts (1..60 min); button starts
#   RUNNING   — count down; button pauses
#   PAUSED    — frozen; button resumes
#   BREAK     — counting down break; button skips to IDLE
#
# Inputs:
#   Encoder    — when IDLE: adjust work minutes
#   Button 0   — start / pause / resume / skip
#   Button 1   — reset to IDLE

import lvgl as lv
import wlsdk

# --- State ---
S_IDLE = 0
S_RUNNING = 1
S_PAUSED = 2
S_BREAK = 3

work_minutes = 25
break_minutes = 5
state = S_IDLE
remaining_s = work_minutes * 60.0  # float for sub-second precision

# --- Widgets (set in start) ---
arc = None
time_label = None
status_label = None


def _format_time(seconds):
    s = max(0, int(seconds))
    return "{:02d}:{:02d}".format(s // 60, s % 60)


def _render():
    if state == S_IDLE:
        status_label.set_text("READY")
        time_label.set_text("{:02d}:00".format(work_minutes))
        arc.set_value(100)
    elif state == S_RUNNING:
        status_label.set_text("WORK")
        time_label.set_text(_format_time(remaining_s))
        pct = int(100 * remaining_s / (work_minutes * 60))
        arc.set_value(pct)
    elif state == S_PAUSED:
        status_label.set_text("PAUSED")
        time_label.set_text(_format_time(remaining_s))
    elif state == S_BREAK:
        status_label.set_text("BREAK")
        time_label.set_text(_format_time(remaining_s))
        pct = int(100 * remaining_s / (break_minutes * 60))
        arc.set_value(pct)


def start():
    global arc, time_label, status_label

    scr = lv_root
    scr.set_style_bg_color(lv.color_hex(0x000000), 0)

    arc = lv.arc(scr)
    arc.set_size(150, 150)
    arc.align(lv.ALIGN.CENTER, 0, -30)
    arc.set_range(0, 100)
    arc.set_rotation(270)
    arc.set_bg_angles(0, 360)
    arc.set_value(100)
    arc.remove_style(None, lv.PART.KNOB)
    arc.set_style_arc_color(lv.color_hex(0xff8800), lv.PART.INDICATOR)
    arc.set_style_arc_color(lv.color_hex(0x222222), lv.PART.MAIN)
    arc.set_style_arc_width(10, lv.PART.INDICATOR)
    arc.set_style_arc_width(10, lv.PART.MAIN)

    time_label = lv.label(scr)
    time_label.set_style_text_font(wlsdk.ui.FONT.BIG, 0)
    time_label.set_style_text_color(lv.color_hex(0xffffff), 0)
    time_label.align(lv.ALIGN.CENTER, 0, -30)

    status_label = lv.label(scr)
    status_label.set_style_text_font(wlsdk.ui.FONT.SMALL, 0)
    status_label.set_style_text_color(lv.color_hex(0x888888), 0)
    status_label.align(lv.ALIGN.CENTER, 0, 80)

    wlsdk.ui.set_grab_input(True)
    _render()


def update():
    global state, remaining_s
    if state in (S_RUNNING, S_BREAK):
        remaining_s -= wlsdk.time.get_delta()
        if remaining_s <= 0:
            if state == S_RUNNING:
                # work session ended -> start break
                state = S_BREAK
                remaining_s = break_minutes * 60.0
            else:
                # break ended -> back to idle
                state = S_IDLE
                remaining_s = work_minutes * 60.0
        _render()


def on_event(event_type, event_index, event_value):
    global work_minutes, state, remaining_s

    if event_type == wlsdk.EVENT.ENCODER:
        if state == S_IDLE:
            work_minutes = max(1, min(60, work_minutes + event_value))
            remaining_s = work_minutes * 60.0
            _render()
    elif event_type == wlsdk.EVENT.BUTTON and event_value == wlsdk.EVENT.BUTTON_DOWN:
        if event_index == 0:
            # Start / pause / resume / skip
            if state == S_IDLE:
                state = S_RUNNING
                remaining_s = work_minutes * 60.0
            elif state == S_RUNNING:
                state = S_PAUSED
            elif state == S_PAUSED:
                state = S_RUNNING
            elif state == S_BREAK:
                # skip the break
                state = S_IDLE
                remaining_s = work_minutes * 60.0
            _render()
        elif event_index == 1:
            # Reset
            state = S_IDLE
            remaining_s = work_minutes * 60.0
            _render()
