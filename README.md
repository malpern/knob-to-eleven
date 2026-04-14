# eleven

Build apps that go to eleven.

A host-side runtime and developer tool for writing custom apps for
[Work Louder](https://worklouder.cc) devices — the k·no·b·1 and Nomad E —
using their MicroPython + LVGL SDK. Write your `app.py`, see it rendered in
a pixel-accurate preview window instantly, no device required.

**Status:** early. Not yet usable. See `docs/` for plans and progress.

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
