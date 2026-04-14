# Test for examples/mac_live/app.py — sparkline + animated big number.
# Uses inject_rpc to feed synthetic CPU values without spinning a worker.
import eleven_test as t
import time as _time

t.load_app(t.example("mac_live/app.py"))


def big_value():
    # The big number label is the only one that's *just* digits
    for w, txt in t.find_labels():
        if txt and txt.isdigit():
            return int(txt)
    return None


# Initial: number renders as "0"
assert big_value() == 0, "expected 0 at start, got {!r}".format(big_value())

# Push a single sample. The big number eases toward target over frames,
# not instantly — so we step a few frames to let it converge.
t.inject_rpc("cpu.update", {"value": 50.0})
for _ in range(20):
    t.step(1)
    _time.sleep_ms(20)
v = big_value()
assert v is not None, "no numeric label found"
assert 30 <= v <= 50, "expected number to ease toward 50, got {}".format(v)

# Push a much higher sample, give it time to converge
t.inject_rpc("cpu.update", {"value": 90.0})
for _ in range(40):
    t.step(1)
    _time.sleep_ms(20)
v = big_value()
assert 70 <= v <= 90, "expected number to ease toward 90, got {}".format(v)

# Wildly high sample is clamped — but for sparkline only,
# the displayed number eases toward the clamped value.
t.inject_rpc("cpu.update", {"value": 9999.0})
for _ in range(60):
    t.step(1)
    _time.sleep_ms(20)
v = big_value()
assert v <= 100, "expected clamp to <=100, got {}".format(v)

print("mac_live: sparkline animation eases toward incoming RPC values")
