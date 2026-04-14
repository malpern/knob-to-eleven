#!/usr/bin/env python3
# End-to-end test of the worker.py <-> device RPC bridge.
#
# Spawns `eleven run examples/cpu/` for ~5s, captures stdout, and
# verifies that:
#   - the worker connected (host printed "worker connected")
#   - the worker's log() messages reached the host (printed "worker: ...")
#   - the device received at least one cpu.update RPC (the worker is
#     running on a 1-second polling loop)

import os
import re
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ELEVEN = os.path.join(REPO_ROOT, "core", "eleven")
CPU_DIR = os.path.join(REPO_ROOT, "examples", "cpu")

# Patch app.py briefly to add a print on cpu.update so we can verify
# from stdout. We restore the original after.
APP_PATH = os.path.join(CPU_DIR, "app.py")
with open(APP_PATH) as f:
    original = f.read()

instrumented = original.replace(
    'def on_cpu_update(ctx, params):\n    """Called when worker.py sends wlsdk.cpu.update."""',
    'def on_cpu_update(ctx, params):\n    """Called when worker.py sends wlsdk.cpu.update."""\n    print("RPC_TEST_GOT_UPDATE:" + repr(params))',
)
if instrumented == original:
    print("FAIL: could not patch on_cpu_update for instrumentation")
    sys.exit(1)

with open(APP_PATH, "w") as f:
    f.write(instrumented)

try:
    proc = subprocess.Popen(
        [ELEVEN, "run", CPU_DIR],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        start_new_session=True,  # so we can SIGTERM the whole group
    )
    try:
        output, _ = proc.communicate(timeout=6)
    except subprocess.TimeoutExpired:
        # Send SIGTERM to the process group so the bash CLI's trap
        # fires and cleans up its worker subprocess too.
        import os as _os, signal as _signal
        try:
            _os.killpg(_os.getpgid(proc.pid), _signal.SIGTERM)
        except Exception:
            proc.terminate()
        try:
            output, _ = proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            output, _ = proc.communicate()
finally:
    with open(APP_PATH, "w") as f:
        f.write(original)

# Even if subprocess timed out, we should have captured stdout.
checks = {
    "worker connected": "worker connected on port" in output,
    "worker log reached host": "worker: cpu worker started" in output,
    "device received cpu.update": "RPC_TEST_GOT_UPDATE:" in output,
}

failed = [name for name, ok in checks.items() if not ok]

if failed:
    print("FAIL")
    for name, ok in checks.items():
        print("  {} {}".format("✓" if ok else "✗", name))
    print("--- captured output ---")
    print(output[-2000:])
    sys.exit(1)

print("rpc_bridge: round-trip works")
for name in checks:
    print("  ✓ {}".format(name))
