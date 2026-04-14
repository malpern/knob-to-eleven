# knob-to-eleven

Build apps that go to eleven.

A host-side runtime and developer tool for writing custom apps for
[Work Louder](https://worklouder.cc) devices — the k·no·b·1 and Nomad E —
using their MicroPython + LVGL SDK. Write your `app.py`, see it rendered in
a pixel-accurate preview window instantly, no device required.

The CLI is named `eleven`. The repo is `knob-to-eleven`.

**Status:** early but usable. Renders apps, hot-reloads, RPC bridges to
host data, autonomous test harness. No SwiftUI app yet — just a CLI.

---

## Quick start

Requires macOS, Xcode Command Line Tools, Swift, Homebrew with `sdl2`,
`pkg-config`, `cmake`, `python3`, and `openjdk` (any of 17/21/25).

```bash
git clone <this-repo>
cd knob-to-eleven
bin/bootstrap.sh                   # ~5 min first time, ~2s thereafter
mac/.build/debug/eleven run examples/hello.py
mac/.build/debug/eleven run examples/cpu/    # live macOS CPU on the dial
tests/run_all.sh                   # 6 tests, all should pass
```

The bootstrap script clones lv_micropython into `lib/`, builds it with
the LVGL+SDL variant, builds the Swift CLI. Both outputs are gitignored;
you rebuild on each fresh clone.

---

## Why

Work Louder ships an SDK for Nomad E (`sdk-alpha-0.1`) that lets you write
Python apps running in MicroPython on the device, drawing via LVGL,
responding to encoder and button input, and talking to host processes over
RPC. The knob port is coming, not yet shipped.

`eleven` lets you build apps against the SDK *today* — without a device,
on macOS, with a <100ms hot-reload loop and a pixel-accurate preview.
The same `app.py` you write here runs unchanged on device when you're
ready to deploy.

## Architecture

Two layers:

1. **`eleven-core`** — a platform-neutral runtime. Embeds MicroPython +
   LVGL, runs `app.py`, exposes a C API for "render a frame, deliver this
   input event, read the framebuffer." Ships as a CLI and as a library.
   Anyone can build a different shell on top — Electron, VSCode extension,
   headless CI runner.

2. **`eleven-mac`** — a native macOS shell. SwiftUI, Metal, Liquid Glass,
   keyboard-driven. Preview window, widget inspector, chat-based LLM app
   generation, one-click deploy to a connected device.

The core is MIT licensed and exists independently of the Mac shell. Fork
it, build a Windows/Linux UI on it, contribute upstream — all welcome.

## License

MIT. See `LICENSE`.

## Relationship to Work Louder

This is a community project. It is not affiliated with, endorsed by, or
officially associated with Work Louder. "Work Louder," "k·no·b·1," and
"Nomad E" are trademarks of their respective owners.
