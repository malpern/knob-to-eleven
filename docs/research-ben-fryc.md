# Research: Ben Fryc, designer of the k·no·b·1

Captured 2026-04-14. Background research used to inform this project's
visual direction (see `design-language.md`). Not affiliated with or
endorsed by Ben Fryc or Work Louder.

---

## Identity

**Ben Fryc** — 3D artist and motion designer based in Michigan.

- Portfolio: https://www.benfryc.com
- Knob microsite: https://knob.design
- Instagram: https://www.instagram.com/benfryc_art/
- Announcement of the project (his voice): https://www.tiktok.com/@benfryc/video/7329990304205999402

**Important:** not Ben Fry (co-creator of Processing, Fathom Information
Design). Two different people — the names are confusable. Ben **Fryc**
is the designer of the k·no·b·1.

## Role on the knob

- Started the knob as a Figma concept in **July 2023**
- Partnered with Work Louder under their "WrkShop" program (Work Louder
  co-founders Mike Di Genova and Mattia run WrkShop as a path for
  outside designers to bring keyboard-adjacent products to manufacture)
- Lead visual / industrial designer; Work Louder handled productization,
  firmware, and software

## Background

- Currently full-time at **Framer** doing 3D and motion design for video
- Past clients: Wealthsimple, Polywork, Mango Languages, Teal Media,
  freelance for Google, Figma, Loom
- Work skews toward Cinema 4D / Octane-style 3D renders, motion
  graphics, kinetic typography
- Signature aesthetic: **modern-retro tactile-tech** — soft shadows,
  matte plastics, crisp single-accent colors. The orange (`#FF8800`-ish)
  visible across the knob marketing is consistent with his other work.

## Public statements about the knob's UI

He hasn't published a formal design language doc, design diary, or
long-form interview about the knob's screen UI. The recurring quotable
position from press coverage and the knob.design page:

- The 100×310 full-color LCD is a **"UX playground"**
- "We plan to support custom wallpapers, a timer, and computer control
  features when we ship. Down the road, we want people to be able to
  create their own features."
- The bottom encoder is for navigation; the top encoder is
  user-programmable
- The display resolution is described as "suitable for pixel art"

Press references:
- Tools and Toys feature on the knob (search for "tools and toys knob"
  — they framed it as "both classic and modern technology")
- Acquire Magazine
- Inspiration Grid

## Why this matters for our project

We're building `knob-to-eleven`, a host-side simulator + dev tool +
eventual LLM-first app generator for Work Louder devices. The visual
language of generated apps should:

1. **Honor Fryc's aesthetic intent** (modern-retro tactile-tech with one
   accent color), since end users will perceive our generated apps as
   "knob apps" regardless of who built them
2. **Amplify the "UX playground" framing**, not subvert it — we're
   making it easier to do what he explicitly said he wanted
3. **Stay distinguishable from generic LVGL output**, which by default
   looks like flat material-design widgets (wrong feel for the device)

See `design-language.md` for the working design principles we're
adopting based on this research.

## Open research gaps

- No formal published design language doc from Fryc or Work Louder
- The exact fonts Work Louder ships with the firmware are unknown.
  These live as byte arrays in the firmware rodata and are extractable
  via Ghidra (deferred — see `wlsdk-api-surface.md`).
- Specific motion/easing parameters used in firmware widgets — unknown
  without device access or firmware decompilation
- Whether Fryc has design opinions about *non-Pomodoro/Clock* widget
  categories (sliders, lists, charts) — speculative
- Whether reaching out to Fryc or Work Louder directly would yield a
  formal design language doc — not attempted

## How we'll close the gaps over time

- Extract device fonts from firmware (next planned task)
- When we have a real device: photograph the actual on-screen widgets,
  measure their colors, decompose their motion
- If the project gains traction publicly, ask Work Louder / Fryc for
  input
