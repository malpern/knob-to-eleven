# Test for examples/pomodoro.py — state machine + timer + input.

import eleven_test as t
import time as _time

t.load_app(t.example("pomodoro.py"))


def status_text():
    """Find the status label (READY/WORK/PAUSED/BREAK)."""
    for state_word in ("READY", "WORK", "PAUSED", "BREAK"):
        if t.find_label_with_text(state_word):
            return state_word
    return None


def time_text():
    """Find the MM:SS time label."""
    for w, txt in t.find_labels():
        if len(txt) == 5 and txt[2] == ":" and txt[:2].isdigit() and txt[3:].isdigit():
            return txt
    return None


# --- Initial state ---
assert status_text() == "READY", "expected READY at start, got {!r}".format(status_text())
assert time_text() == "25:00", "expected 25:00 at start, got {!r}".format(time_text())

# --- Encoder adjusts duration when idle ---
t.inject_encoder(+5)
t.step()
assert time_text() == "30:00", "encoder +5 should set 30:00, got {!r}".format(time_text())

t.inject_encoder(-15)
t.step()
assert time_text() == "15:00", "encoder -15 should set 15:00, got {!r}".format(time_text())

# Clamp to 1..60: try to go below 1
t.inject_encoder(-100)
t.step()
assert time_text() == "01:00", "encoder should clamp at 1, got {!r}".format(time_text())

# Reset to 25 for clarity
t.inject_encoder(+24)
t.step()
assert time_text() == "25:00"

# --- Button 0 starts the timer ---
t.inject_button(0, "press")
t.step()
assert status_text() == "WORK", "after start, expected WORK, got {!r}".format(status_text())

# --- Time decreases over wall-clock seconds ---
# Step real frames until at least one second has elapsed
for _ in range(80):
    t.step(1)
    _time.sleep_ms(15)
later = time_text()
assert later != "25:00", "timer should have decreased from 25:00, got {!r}".format(later)
assert later.startswith("24:"), "after ~1.2s, expected 24:xx, got {!r}".format(later)

# --- Button 0 pauses ---
t.inject_button(0, "press")
t.step()
assert status_text() == "PAUSED", "expected PAUSED after pause, got {!r}".format(status_text())

paused_at = time_text()
# Wait, time should not advance while paused
for _ in range(30):
    t.step(1)
    _time.sleep_ms(15)
assert time_text() == paused_at, \
    "time should be frozen when paused, but went {!r} -> {!r}".format(paused_at, time_text())

# --- Button 0 resumes ---
t.inject_button(0, "press")
t.step()
assert status_text() == "WORK", "expected WORK after resume, got {!r}".format(status_text())

# --- Button 1 resets ---
t.inject_button(1, "press")
t.step()
assert status_text() == "READY", "expected READY after reset, got {!r}".format(status_text())
assert time_text() == "25:00", "expected 25:00 after reset, got {!r}".format(time_text())

print("pomodoro: state machine and timer behave correctly")
