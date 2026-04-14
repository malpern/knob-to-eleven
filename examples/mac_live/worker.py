# mac_live — polls macOS CPU every 500ms, pushes to device.
import time

log("mac_live worker started")


def get_cpu_percent():
    # `top -l 1` is faster than -l 2 (one sample instead of two).
    # First sample is "since boot" which is less responsive, but for a
    # sparkline that's fine — we just want motion.
    out = exec_process("top -l 1 -n 0 | grep '^CPU usage' | head -1")
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


while True:
    pct = get_cpu_percent()
    send_rpc("cpu.update", {"value": pct})
    time.sleep(0.5)
