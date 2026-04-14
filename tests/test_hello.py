# Test for examples/hello.py — verifies the time-driven animation progresses.
import eleven_test as t

t.load_app(t.example("hello.py"))

# Initial label shows "0%"
initial = t.find_label_text()
assert initial == "0%", "initial label should be '0%', got {!r}".format(initial)

# The platform label should be present as a second label
labels = t.find_labels()
texts = [text for _, text in labels]
assert "nomad-v1" in texts, \
    "platform label 'nomad-v1' not found; labels: {}".format(texts)

# After stepping many frames, the arc percentage should advance
# hello.py increments at 25%/sec; at ~60 fps, 60 frames = 1 sec
# (get_delta uses ticks_ms wall-clock, so advance is real-time)
import time as _time
start_text = t.find_label_text()
for _ in range(30):
    t.step(1)
    _time.sleep_ms(40)  # total ~1.2s of wall time
later = t.find_label_text()
assert later != start_text, \
    "label unchanged after 1.2s of frames; start={!r} later={!r}".format(start_text, later)

# The text should be a percentage
assert later.endswith("%"), "label should end in %, got {!r}".format(later)

print("hello: animation progressed from {} to {}".format(start_text, later))
