# Contributing

Welcome. This is an early community project — issues, ideas, and pull
requests are all useful. Read the [vision doc](docs/vision.md) and
[design language draft](docs/design-language.md) before proposing any
changes to the DSL or default theme — those decisions are deliberate.

## Setup

macOS-only for now (the simulator embeds SDL + LVGL via lv_micropython).
You need Xcode Command Line Tools, Swift 5.9+, and Homebrew with these
packages: `sdl2`, `cmake`, `pkg-config`, `python3`, `openjdk@21` (any
JDK 17+ works).

```bash
git clone https://github.com/malpern/knob-to-eleven
cd knob-to-eleven
bin/bootstrap.sh                  # ~5 min cold; ~2s after that
mac/.build/debug/eleven run examples/hello.py
tests/run_all.sh
```

## Code layout

```
core/                  Python runtime (MicroPython side + worker subprocess)
  host.py              The interactive frame loop (used by `eleven run`)
  test_host.py         Headless test runner (used by `eleven test`)
  render_host.py       One-shot framebuffer capture (used by `eleven render`)
  worker_runner.py     Subprocess wrapper for worker.py — runs in CPython
  wlsdk.py             Stub of Work Louder's MicroPython SDK module
  eleven_dsl.py        Opinionated widget primitives over LVGL
  eleven_test.py       Test helpers (load_app, inject_*, find_labels, etc.)

mac/                   Native macOS pieces
  Package.swift        Swift Package
  Sources/eleven/      The Swift CLI (run / test / render subcommands)

examples/              Apps you can run with `eleven run`
  hello.py             Single-file: lifecycle hooks, lv_root, fonts
  pomodoro.py          Single-file: state machine, timer, encoder + buttons
  pomodoro_dsl.py      Same as above, rewritten on eleven_dsl primitives
  cpu/                 Project dir: app.py + worker.py (live macOS CPU)
  mac_live/            Project dir: scrolling sparkline + animated number

tests/                 Test suite (run via tests/run_all.sh)
  test_*.py            Per-app behavior tests; default to MicroPython driver
                       Files with a python3 shebang on line 1 run as CPython
                       (used for tests that shell out to the eleven CLI)

docs/                  Vision, design language, API surface, planning notes
bin/                   bootstrap.sh + symlink to the built micropython binary
lib/                   (gitignored) lv_micropython clone — created by bootstrap
```

## Adding an example

Single-file (no host data):

```bash
# create examples/myapp.py with start(), update(), on_event()
# create tests/test_myapp.py using eleven_test helpers
mac/.build/debug/eleven run examples/myapp.py
tests/run_all.sh
```

With host data (RPC):

```bash
# create examples/myapp/app.py and examples/myapp/worker.py
# app.py: wlsdk.rpc.register("my.method", handler)
# worker.py: send_rpc("my.method", {...}) on whatever cadence
# create tests/test_myapp_app.py — use t.inject_rpc(...) for fast unit tests
mac/.build/debug/eleven run examples/myapp/
tests/run_all.sh
```

See `examples/cpu/` for the canonical RPC pattern.

## Style

- Match the existing style of nearby files. No imposed formatter.
- Comments explain *why*, not *what*. Don't narrate code.
- Tests must be deterministic — prefer `inject_*` helpers over real
  subprocesses and wall-clock waits where possible.
- New DSL primitives need a behavior test that exercises them through
  at least one example.

## What's in scope vs out

**In scope:**
- macOS-host simulator for the Work Louder SDK
- Apps that match the [design language](docs/design-language.md)
- Tooling that helps people build SDK apps without a device

**Out of scope (for now):**
- Linux/Windows ports — possible later via the platform-neutral
  Python core, but not a current priority
- Replacing Work Louder's official Input app
- The LLM-first app generation experience described in
  [docs/vision.md](docs/vision.md) — that's the eventual end state but
  not the current focus

## Reporting bugs

Use the GitHub issue tracker. For runtime bugs, please include:
- macOS version
- Output of `swift --version`
- Output of `bin/bootstrap.sh` if it failed
- Full output of `tests/run_all.sh`
- A minimal reproduction (an `app.py` that triggers the bug)

## Relationship to Work Louder

This is unaffiliated. We hope to be useful to Work Louder and the knob
community; we are not Work Louder. Don't file issues here that should
be filed with Work Louder (firmware bugs, hardware questions). Do file
issues here about the simulator, the DSL, examples, or the CLI.
