#!/usr/bin/env python3
# Visual smoke test — verify each example renders to a PNG with non-zero
# content. Doesn't compare against golden PNGs (yet); just catches the case
# where rendering breaks entirely.
#
# This test runs OUTSIDE the MicroPython test_host (it shells out to
# `eleven render`). The `#!/usr/bin/env python3` shebang on line 1 tells
# run_all.sh to invoke it via python3 instead of `eleven test`.

import os
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ELEVEN = os.environ.get("ELEVEN_BIN", os.path.join(REPO_ROOT, "core", "eleven"))
EXAMPLES_DIR = os.path.join(REPO_ROOT, "examples")
OUT_DIR = "/tmp/eleven_render_test"
os.makedirs(OUT_DIR, exist_ok=True)


def render(src_path, out_path, events=""):
    args = [ELEVEN, "render", src_path, "--out", out_path, "--frames", "2"]
    if events:
        args += ["--events", events]
    proc = subprocess.run(args, capture_output=True, text=True, timeout=20)
    return proc


# Collect all example apps:
#   examples/foo.py        — single-file
#   examples/foo/app.py    — project-dir
targets = []  # (label, source_path_for_render, events_for_render)
for name in sorted(os.listdir(EXAMPLES_DIR)):
    p = os.path.join(EXAMPLES_DIR, name)
    if name.endswith(".py"):
        targets.append((name, p, ""))
    elif os.path.isdir(p) and os.path.exists(os.path.join(p, "app.py")):
        # For project-dir examples that use RPC, inject a synthetic value
        # so the render shows real content. Default = no events.
        events = ""
        if name in ("cpu", "mac_live"):
            events = "rpc:cpu.update:42"
        targets.append((name + "/", os.path.join(p, "app.py"), events))


failures = []
for label, src, events in targets:
    out = os.path.join(OUT_DIR, label.rstrip("/").replace("/", "_") + ".png")
    proc = render(src, out, events)
    if proc.returncode != 0:
        failures.append((label, "render exit {}: {}".format(proc.returncode, proc.stderr.strip())))
        continue
    if not os.path.exists(out):
        failures.append((label, "no PNG written"))
        continue
    size = os.path.getsize(out)
    if size < 200:
        failures.append((label, "PNG too small ({} bytes)".format(size)))
        continue
    print("  {}: OK ({} bytes)".format(label, size))

if failures:
    print("FAIL")
    for label, msg in failures:
        print("  {}: {}".format(label, msg))
    sys.exit(1)
print("render: all examples rendered cleanly ({} total)".format(len(targets)))
