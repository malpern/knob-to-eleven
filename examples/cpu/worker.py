# CPU monitor — host-side worker.py.
# Polls macOS for CPU percent every second, pushes to the device app
# via send_rpc.

import time

log("cpu worker started")


def get_cpu_percent():
    """Read total CPU usage as a percent (0-100) via top."""
    # `top -l 2` runs two samples; second sample's CPU line has the real numbers
    out = exec_process("top -l 2 -n 0 | grep '^CPU usage' | tail -1")
    # Output looks like: CPU usage: 12.34% user, 5.67% sys, 81.99% idle
    if not out:
        return 0.0
    try:
        parts = out.replace("CPU usage:", "").split(",")
        idle = 0.0
        for p in parts:
            p = p.strip()
            if "idle" in p:
                idle = float(p.split("%")[0])
                break
        return max(0.0, min(100.0, 100.0 - idle))
    except Exception:
        return 0.0


# Poll loop. We sleep between samples; the bridge socket reads in the
# background via blocking recv on a separate read loop in worker_runner.
while True:
    pct = get_cpu_percent()
    send_rpc("cpu.update", {"value": pct})
    time.sleep(1.0)
