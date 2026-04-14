#!/usr/bin/env python3
# Verify the Swift CLI fails cleanly on common bad inputs:
#   - run/test/render against a nonexistent file
#   - render without --out (required)
#   - run on a directory that has no app.py
#   - bad --geometry value

import os
import subprocess
import sys
import tempfile

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ELEVEN = os.environ.get("ELEVEN_BIN", os.path.join(REPO_ROOT, "core", "eleven"))


def expect_error(args, expect_substring, label):
    proc = subprocess.run(
        [ELEVEN] + args,
        capture_output=True, text=True, timeout=10,
    )
    out = proc.stdout + proc.stderr
    if proc.returncode == 0:
        return "{}: expected non-zero exit, got 0. output:\n{}".format(label, out[-500:])
    if expect_substring not in out:
        return "{}: expected {!r} in output, got:\n{}".format(label, expect_substring, out[-500:])
    return None


cases = [
    # run on nonexistent file
    (["run", "/this/path/does/not/exist.py"], "not found", "run-missing-file"),
    # test on nonexistent file
    (["test", "/no/such/test.py"], "not found", "test-missing-file"),
    # render needs --out
    (["render", os.path.join(REPO_ROOT, "examples/hello.py")], "out", "render-missing-out"),
    # bad geometry
    (["run", os.path.join(REPO_ROOT, "examples/hello.py"), "--geometry", "garbage"],
     "geometry", "bad-geometry"),
    # unknown subcommand
    (["xyz"], "Error", "unknown-subcommand"),
]

# Run on a dir without app.py
empty_dir = tempfile.mkdtemp(prefix="eleven_emptydir_")
cases.append((["run", empty_dir], "no app.py", "dir-without-app"))

failures = []
for args, sub, label in cases:
    err = expect_error(args, sub, label)
    if err:
        failures.append(err)
    else:
        print("  ✓ {}".format(label))

# cleanup
try: os.rmdir(empty_dir)
except Exception: pass

if failures:
    print("FAIL")
    for f in failures: print("  " + f)
    sys.exit(1)
print("cli errors: all bad inputs rejected with helpful messages")
