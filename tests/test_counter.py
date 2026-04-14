# Test for examples/counter.py
# Verifies:
#   - initial label reads "0"
#   - encoder right increments, encoder left decrements
#   - button press resets to 0

import eleven_test as t

REPO_ROOT = "/Users/malpern/local-code/eleven"
t.load_app(REPO_ROOT + "/examples/counter.py")

# After start(), counter should render 0
assert t.find_label_text() == "0", \
    "expected '0' at start, got {!r}".format(t.find_label_text())

# Encoder right 3 times -> 3
t.inject_encoder(+3)
t.step()
assert t.find_label_text() == "3", \
    "after +3 encoder, expected '3', got {!r}".format(t.find_label_text())

# Encoder left 5 times -> -2
t.inject_encoder(-5)
t.step()
assert t.find_label_text() == "-2", \
    "after -5 encoder, expected '-2', got {!r}".format(t.find_label_text())

# Button press -> 0
t.inject_button(0, "press")
t.step()
assert t.find_label_text() == "0", \
    "after button press, expected '0', got {!r}".format(t.find_label_text())

print("counter: all assertions passed")
