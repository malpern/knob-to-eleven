# CPU monitor — device-side app.py.
# Renders a dial showing the current CPU percent. The value comes from
# the host via worker.py, which polls top/ps and pushes via send_rpc.

import wlsdk
from eleven_dsl import theme, screen, dial, segment, label

arc = None
pct_label = None
status = None
current_pct = 0
last_update_at = None  # wall-clock seconds from wlsdk.time at last update


def _render():
    arc.set_value(int(current_pct))
    pct_label.set_text("{}%".format(int(current_pct)))


def start():
    global arc, pct_label, status
    scr = screen()
    arc = dial(scr, value=0, size=150, width=10, offset_y=-30)
    pct_label = segment(scr, text="--", offset_y=-30)
    status = label(scr, text="waiting...", color=theme.muted, font="small",
                   align="center", offset_y=80)


def on_cpu_update(ctx, params):
    """Called when worker.py sends wlsdk.cpu.update."""
    global current_pct, last_update_at
    if isinstance(params, dict) and "value" in params:
        try:
            v = float(params["value"])
        except (TypeError, ValueError):
            return
        current_pct = max(0.0, min(100.0, v))
        last_update_at = wlsdk.time.get_elapsed()
        _render()
        status.set_text("CPU")


def update():
    # Show "stale" if we haven't heard from worker in 5+ seconds
    if last_update_at is not None:
        if wlsdk.time.get_elapsed() - last_update_at > 5.0:
            status.set_text("stale")


# Register the RPC handler so worker.py's send_rpc("cpu.update", ...) reaches us.
wlsdk.rpc.register("cpu.update", on_cpu_update)
