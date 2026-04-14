# Test for examples/cpu/app.py — verifies RPC handling without spinning
# up a real worker subprocess. Uses inject_rpc to synthesize the
# "cpu.update" message that worker.py would normally send.
#
# The end-to-end bridge (real worker subprocess + TCP loopback) is
# covered by tests/test_rpc_bridge.py instead.

import eleven_test as t

t.load_app(t.example("cpu/app.py"))


def find_pct():
    """Return the integer percent shown by the big numeric label, or None."""
    for w, txt in t.find_labels():
        if txt.endswith("%"):
            try:
                return int(txt[:-1])
            except ValueError:
                pass
    return None


def find_status():
    for w, txt in t.find_labels():
        if txt in ("waiting...", "CPU", "stale"):
            return txt
    return None


# --- Initial state ---
assert find_pct() is None or find_pct() == 0
assert find_status() == "waiting...", \
    "expected 'waiting...' before any RPC, got {!r}".format(find_status())

# --- One RPC arrives ---
ok = t.inject_rpc("cpu.update", {"value": 42.5})
assert ok, "no handler registered for cpu.update"
t.step()
assert find_pct() == 42, "expected 42% after first RPC, got {!r}".format(find_pct())
assert find_status() == "CPU", \
    "expected status 'CPU' after first RPC, got {!r}".format(find_status())

# --- Subsequent updates change the displayed value ---
t.inject_rpc("cpu.update", {"value": 87.0})
t.step()
assert find_pct() == 87, "expected 87% after update, got {!r}".format(find_pct())

t.inject_rpc("cpu.update", {"value": 5.0})
t.step()
assert find_pct() == 5

# --- Out-of-range values are clamped (worker can send weird stuff) ---
t.inject_rpc("cpu.update", {"value": 200.0})
t.step()
assert find_pct() == 100, "expected clamp-to-100, got {!r}".format(find_pct())

t.inject_rpc("cpu.update", {"value": -50.0})
t.step()
assert find_pct() == 0, "expected clamp-to-0, got {!r}".format(find_pct())

# --- Malformed payload is ignored, doesn't crash ---
t.inject_rpc("cpu.update", None)
t.inject_rpc("cpu.update", {"unrelated": "garbage"})
t.inject_rpc("cpu.update", "not a dict")
t.step()
# Last good value (0) should still be on display
assert find_pct() == 0

print("cpu app: RPC handler behaves correctly")
