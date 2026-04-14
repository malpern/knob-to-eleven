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

failures = []

for name in sorted(os.listdir(EXAMPLES_DIR)):
    if not name.endswith(".py"):
        continue
    src = os.path.join(EXAMPLES_DIR, name)
    out = os.path.join(OUT_DIR, name.replace(".py", ".png"))
    proc = subprocess.run(
        [ELEVEN, "render", src, "--out", out, "--frames", "2"],
        capture_output=True, text=True, timeout=20,
    )
    if proc.returncode != 0:
        failures.append((name, "render exit {}: {}".format(proc.returncode, proc.stderr.strip())))
        continue
    if not os.path.exists(out):
        failures.append((name, "no PNG written"))
        continue
    size = os.path.getsize(out)
    if size < 200:  # PNG header alone is ~50 bytes; real content is bigger
        failures.append((name, "PNG too small ({} bytes)".format(size)))
        continue
    print("  {}: OK ({} bytes)".format(name, size))

if failures:
    print("FAIL")
    for name, msg in failures:
        print("  {}: {}".format(name, msg))
    sys.exit(1)
print("render: all examples rendered cleanly")
