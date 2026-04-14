# Design Language v0.1 (working draft)

The aesthetic and rules that `knob-to-eleven`'s DSL primitives, default
themes, and LLM-generated apps should follow.

**Status:** v0.1, working draft. Synthesized from Ben Fryc's portfolio
and his public statements about the knob (see
`research-ben-fryc.md`). Not endorsed by Fryc or Work Louder. Will be
revised once we have:
- Device font extraction
- Photos of actual on-screen widgets from a real device
- Direct input from Fryc / Work Louder if obtainable

When in doubt, prefer to look like a **physical instrument faceplate**
or a **vintage hi-fi component**, not like an iOS widget or a
Material card.

---

## 1. Voice & feel

| Yes | No |
|---|---|
| Modern-retro tactile-tech | Flat material design |
| Pixel-honest | Hi-DPI vector smoothness |
| One accent on a restrained ground | Rainbow palettes |
| Big numerals + small caps labels | Body-text-paragraph layouts |
| Spring/overshoot motion | Linear interpolation |
| Instrument faceplates | Cards |
| Composable third-party widgets | Locked-down system widgets |

The screen should feel like an object you'd find on a producer's desk
or in a small recording studio rack — not like a small iPhone.

---

## 2. Color palette

Defaults that should ship with the DSL. Hex values are the LVGL
arguments to `lv.color_hex(...)`.

```
bg          0x000000   true black; the device's OLED-style background
fg          0xFFFFFF   primary text and important value rendering
muted       0x888888   secondary labels and inactive state
dim         0x333333   inactive arc track, plate background
accent      0xFF8800   Fryc's signature orange, used for primary value
                       indication, focused state, "alive" feel
warn        0xFFCC00   amber warning (non-critical)
ok          0x44CC88   muted green for success states (sparingly)
err         0xFF4444   red for errors only
```

**Rule:** every app uses `bg`, `fg`, `muted`, `accent`. Other colors
are exceptional. Discourage the LLM from picking arbitrary RGB values
when one of the named colors fits.

**Theming:** future versions of the DSL should let users override the
palette but expose only the named slots. The `accent` is the most
likely user override (someone wants their pomodoro to be teal; that's
fine) — change *one* color, the rest of the palette adapts.

---

## 3. Typography

The device exposes three fonts via `wlsdk.ui.FONT.{BIG, MEDIUM, SMALL}`.
The simulator currently substitutes Montserrat at sizes 24/16/12 — a
**known mismatch**, since:

- Montserrat is a humanist sans designed for print, not pixel-honest
- Anti-aliasing at small sizes blurs the "instrument" feel
- The actual device fonts are likely something blockier / more
  bitmap-leaning

**Action:** extract the device fonts from firmware rodata (planned).
Until then, the simulator's Montserrat substitution is acceptable but
should be replaced with a more pixel-honest fallback (candidates: IBM
Plex Mono, Berkeley Mono, JetBrains Mono Bitmap, Geneva, or a small
bitmap font like 5x7 / 6x10).

**Hierarchy rule:**

- `BIG` — *primary value*. Always the focus of the screen. Reserve
  for the one number the user cares about (current minute, BPM,
  percent, song title). Should occupy ~25-40% of vertical space.
- `MEDIUM` — secondary value or single-line label
- `SMALL` — captions, status text, "PAUSED" / "WORK" / "READY" /
  platform name. Often UPPER CASE for label-y feel.

**Don't use BIG for two things at once.** One value per screen
deserves the spotlight.

---

## 4. Widget aesthetic

LVGL primitives compose into widgets that should look like one of
these patterns, in order of preference:

1. **Dial** — circular gauge with an arc indicator on a darker arc
   track, optional centered numeric value. The pomodoro example is the
   canonical instance.
2. **Bar** — horizontal level meter with discrete or continuous fill.
   Like a VU meter.
3. **Plate** — slightly-darker rectangular background with a label
   and value, for grouping related info.
4. **Segment display** — chunky monospace numerals in `accent`,
   evoking 7-segment LCDs. Use for time and counters.
5. **Marquee** — scrolling label for content longer than the screen
   width. Common for song titles, error messages.
6. **Sparkline** — tiny line chart of recent values. Use for
   trending data (CPU over the last 60s, etc.).
7. **Indicator dot** — small filled circle, accent or muted, for
   binary/status state.

**Avoid:** chrome-heavy buttons, drop shadows that simulate depth,
gradients across the whole screen, photographic backgrounds (other
than wallpapers, which are a separate Work Louder feature).

**Bevels and shadows:** subtle. Inner shadow on plates is OK; outer
shadow on the screen as a whole is not (the screen *is* the device,
nothing's floating above it).

---

## 5. Motion

Defaults the DSL should provide; the LLM should not specify motion
parameters explicitly unless overriding.

| Action | Easing | Duration |
|---|---|---|
| Value change (number ticks up) | `ease_out_cubic` | 200ms |
| Arc/dial fill animation | `ease_out_back` (slight overshoot) | 350ms |
| Status transition (READY→WORK) | `ease_out_quart` | 250ms |
| Screen entrance (app load) | `ease_out_back` | 400ms |
| Screen exit (teardown) | `ease_in_cubic` | 200ms |
| Marquee scroll | linear | 30 px/sec |

**Rule:** motion should always have **weight** — overshoot or
deceleration, not linear. Linear motion is for marquees only.

**Frame budget:** 60 fps target. If a per-frame computation doesn't
finish in 16ms, simplify the visual (don't drop fps).

---

## 6. Layout

The knob screen is **100 × 310** (portrait). Nomad E is **170 × 320**.
Both are tall, narrow.

- **Default orientation:** vertical stack from top
- **Primary value:** vertically centered, dominates middle 50% of
  height
- **Status label:** above or below the primary value, never floating
- **Secondary info:** bottom 15% of screen, in `SMALL`, `muted`
- **Margins:** 8px on all sides minimum, 12px preferred

The DSL's default layout should fill these patterns automatically
when widgets are composed. The user (or LLM) shouldn't have to think
about pixel positions for typical apps.

---

## 7. Composability

Per Fryc's "UX playground" framing:

- Third-party widgets live alongside Work Louder's first-party widgets
  with the same visual treatment
- The DSL should expose theme tokens to user widgets so a user-built
  widget automatically picks up the right colors and motion
- Apps should be composable from existing widgets without writing new
  ones

The LLM's job is overwhelmingly to *compose*, not to draw new widget
primitives. New primitives are for human contributors.

---

## 8. Anti-patterns to detect and reject

When the LLM generates an app, the DSL or the linter should warn on:

- Two `BIG` text instances on one screen
- Hard-coded RGB values outside the palette (allow user override but
  warn on others)
- Linear easing on value changes
- Anti-aliased text under 14px (when device fonts land)
- Drop shadows on the root screen
- Apps that use 4+ accent colors

---

## 9. Open questions

- What are the actual device font names, sizes, and bitmap rasters?
  (Extractable from firmware rodata.)
- What's the *exact* orange Fryc uses on the knob marketing? `0xFF8800`
  is approximate from this draft.
- What motion easing does the device firmware actually use for arcs
  and value changes?
- Does Fryc / Work Louder have an opinion on "dark mode" alternates?
  (We're assuming the device is always dark.)
- Should the DSL ship multiple themes (e.g., "Studio" = the default,
  "Workshop" = warm-toned, "Lab" = cooler-toned)? Or one canonical
  look?

---

*v0.1 — 2026-04-14. Will rev once device font extraction and real
hardware photos are in.*
