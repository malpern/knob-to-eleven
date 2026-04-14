# Same behavior assertions as test_pomodoro.py, against the DSL-based
# version. Verifies the DSL preserves identical app behavior.

import eleven_test as t
import time as _time

t.load_app(t.example("pomodoro_dsl.py"))


def status_text():
    for state_word in ("READY", "WORK", "PAUSED", "BREAK"):
        if t.find_label_with_text(state_word):
            return state_word
    return None


def time_text():
    for w, txt in t.find_labels():
        if len(txt) == 5 and txt[2] == ":" and txt[:2].isdigit() and txt[3:].isdigit():
            return txt
    return None


# Initial state
assert status_text() == "READY"
assert time_text() == "25:00"

# Encoder adjusts duration
t.inject_encoder(+5)
t.step()
assert time_text() == "30:00"

t.inject_encoder(-15)
t.step()
assert time_text() == "15:00"

# Clamp at 1
t.inject_encoder(-100)
t.step()
assert time_text() == "01:00"

t.inject_encoder(+24)
t.step()
assert time_text() == "25:00"

# Start
t.inject_button(0, "press")
t.step()
assert status_text() == "WORK"

# Time progresses
for _ in range(80):
    t.step(1)
    _time.sleep_ms(15)
later = time_text()
assert later != "25:00"
assert later.startswith("24:")

# Pause freezes
t.inject_button(0, "press")
t.step()
assert status_text() == "PAUSED"
paused_at = time_text()
for _ in range(30):
    t.step(1)
    _time.sleep_ms(15)
assert time_text() == paused_at

# Resume
t.inject_button(0, "press")
t.step()
assert status_text() == "WORK"

# Reset
t.inject_button(1, "press")
t.step()
assert status_text() == "READY"
assert time_text() == "25:00"

print("pomodoro_dsl: behavior matches raw-LVGL version")
