# Same Pomodoro app as examples/pomodoro.py, rewritten using
# the eleven.dsl primitives. Same behavior, much less boilerplate.
#
# Compare: this file is ~80 lines; the raw-LVGL version is ~120.
# More importantly: no lv.color_hex calls, no set_style_*_width
# repetitions, no manual font lookup. The widget set is opinionated;
# colors / sizes / motion are theme-driven by default.

import wlsdk
from eleven_dsl import theme, screen, dial, segment, label

S_IDLE = 0
S_RUNNING = 1
S_PAUSED = 2
S_BREAK = 3

work_minutes = 25
break_minutes = 5
state = S_IDLE
remaining_s = work_minutes * 60.0

arc = None
time_disp = None
status = None


def _format_time(seconds):
    s = max(0, int(seconds))
    return "{:02d}:{:02d}".format(s // 60, s % 60)


def _render():
    if state == S_IDLE:
        status.set_text("READY")
        time_disp.set_text("{:02d}:00".format(work_minutes))
        arc.set_value(100)
    elif state == S_RUNNING:
        status.set_text("WORK")
        time_disp.set_text(_format_time(remaining_s))
        arc.set_value(int(100 * remaining_s / (work_minutes * 60)))
    elif state == S_PAUSED:
        status.set_text("PAUSED")
        time_disp.set_text(_format_time(remaining_s))
    elif state == S_BREAK:
        status.set_text("BREAK")
        time_disp.set_text(_format_time(remaining_s))
        arc.set_value(int(100 * remaining_s / (break_minutes * 60)))


def start():
    global arc, time_disp, status
    scr = screen()
    arc = dial(scr, value=100, offset_y=-50)
    time_disp = segment(scr, text="25:00", offset_y=25)
    status = label(scr, text="READY", color=theme.muted, font="small",
                   align="bottom", offset_y=-16)
    wlsdk.ui.set_grab_input(True)
    _render()


def update():
    global state, remaining_s
    if state in (S_RUNNING, S_BREAK):
        remaining_s -= wlsdk.time.get_delta()
        if remaining_s <= 0:
            if state == S_RUNNING:
                state = S_BREAK
                remaining_s = break_minutes * 60.0
            else:
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
            if state == S_IDLE:
                state = S_RUNNING
                remaining_s = work_minutes * 60.0
            elif state == S_RUNNING:
                state = S_PAUSED
            elif state == S_PAUSED:
                state = S_RUNNING
            elif state == S_BREAK:
                state = S_IDLE
                remaining_s = work_minutes * 60.0
            _render()
        elif event_index == 1:
            state = S_IDLE
            remaining_s = work_minutes * 60.0
            _render()
