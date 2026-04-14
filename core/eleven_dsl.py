# eleven.dsl — opinionated widget primitives that compile to LVGL.
#
# Per docs/design-language.md, this is the "narrow surface" the LLM
# (and humans) build against. Each primitive applies theme defaults so
# apps look consistent without hand-styling every widget. Drop down to
# raw LVGL when you need to.
#
# Status: v0.1, single-file, will split into a package as it grows.
#
# Primitives (the surface):
#   theme              — named colors (bg, fg, muted, dim, accent, ...)
#   screen()           — the active LVGL screen, themed
#   dial()             — circular gauge with arc indicator
#   bar()              — horizontal level meter
#   label()            — text with theme/font defaults
#   segment()          — big numeric display (for time, counters)
#   plate()            — slightly-darker container for grouping
#   indicator()        — small filled status dot
#   marquee()          — TODO — scrolling label
#   sparkline()        — TODO — tiny line chart

import lvgl as lv


# --- Theme ----------------------------------------------------------

class theme:
    bg = 0x000000
    fg = 0xFFFFFF
    muted = 0x888888
    dim = 0x333333
    accent = 0xFF8800   # Fryc's signature orange
    warn = 0xFFCC00
    ok = 0x44CC88
    err = 0xFF4444


# --- Helpers --------------------------------------------------------

_ALIGN = {
    "center": lv.ALIGN.CENTER,
    "top": lv.ALIGN.TOP_MID,
    "bottom": lv.ALIGN.BOTTOM_MID,
    "left": lv.ALIGN.LEFT_MID,
    "right": lv.ALIGN.RIGHT_MID,
    "top_left": lv.ALIGN.TOP_LEFT,
    "top_right": lv.ALIGN.TOP_RIGHT,
    "bottom_left": lv.ALIGN.BOTTOM_LEFT,
    "bottom_right": lv.ALIGN.BOTTOM_RIGHT,
}


def _resolve_align(align):
    if isinstance(align, str):
        return _ALIGN.get(align, lv.ALIGN.CENTER)
    return align


def _resolve_color(c, default):
    if c is None:
        c = default
    return lv.color_hex(c)


def _resolve_font(font):
    """Map "big"/"medium"/"small" to wlsdk.ui.FONT.*."""
    import wlsdk
    if font is None:
        return wlsdk.ui.FONT.MEDIUM
    if isinstance(font, str):
        f = font.lower()
        if f == "big":    return wlsdk.ui.FONT.BIG
        if f == "small":  return wlsdk.ui.FONT.SMALL
        return wlsdk.ui.FONT.MEDIUM
    return font  # assume it's already a font object


# --- Widget primitives ----------------------------------------------

def screen(bg=None):
    """Return the active LVGL screen, with theme background applied."""
    s = lv.screen_active()
    s.set_style_bg_color(_resolve_color(bg, theme.bg), 0)
    return s


def dial(parent, value=0, value_range=(0, 100),
         color=None, track=None, width=8,
         size=84, align="center", offset_x=0, offset_y=0):
    """Circular gauge: arc indicator on a dimmer arc track.

    Returns the underlying lv.arc — call set_value(N) on it to update.
    Sized for the knob's 100×310 screen by default; pass `size=` to
    override for wider devices.
    """
    a = lv.arc(parent)
    a.set_size(size, size)
    a.set_range(value_range[0], value_range[1])
    a.set_value(value)
    a.set_rotation(270)
    a.set_bg_angles(0, 360)
    a.remove_style(None, lv.PART.KNOB)
    a.remove_flag(lv.obj.FLAG.CLICKABLE)  # purely visual; don't grab input
    indicator_c = _resolve_color(color, theme.accent)
    track_c = _resolve_color(track, theme.dim)
    a.set_style_arc_color(indicator_c, lv.PART.INDICATOR)
    a.set_style_arc_color(track_c, lv.PART.MAIN)
    a.set_style_arc_width(width, lv.PART.INDICATOR)
    a.set_style_arc_width(width, lv.PART.MAIN)
    a.align(_resolve_align(align), offset_x, offset_y)
    return a


def bar(parent, value=0, value_range=(0, 100),
        color=None, track=None,
        width=84, height=8, align="center", offset_x=0, offset_y=0):
    """Horizontal level meter. Returns lv.bar."""
    b = lv.bar(parent)
    b.set_size(width, height)
    b.set_range(value_range[0], value_range[1])
    b.set_value(value, False)  # anim_enable=False
    b.set_style_bg_color(_resolve_color(track, theme.dim), 0)
    b.set_style_bg_color(_resolve_color(color, theme.accent), lv.PART.INDICATOR)
    b.set_style_radius(2, 0)
    b.set_style_radius(2, lv.PART.INDICATOR)
    b.align(_resolve_align(align), offset_x, offset_y)
    return b


def label(parent, text="", color=None, font="medium",
          align="center", offset_x=0, offset_y=0):
    """Text label with theme color + font defaults. Returns lv.label."""
    l = lv.label(parent)
    l.set_text(text)
    l.set_style_text_color(_resolve_color(color, theme.fg), 0)
    l.set_style_text_font(_resolve_font(font), 0)
    l.align(_resolve_align(align), offset_x, offset_y)
    return l


def segment(parent, text="00:00", color=None,
            align="center", offset_x=0, offset_y=0):
    """Big numeric display — for time, counters, primary value.

    Identical to label(font="big") today; will diverge once we have a
    bitmap/segment-style font extracted from the firmware.
    """
    return label(parent, text=text,
                 color=color if color is not None else theme.fg,
                 font="big", align=align,
                 offset_x=offset_x, offset_y=offset_y)


def plate(parent, width=None, height=None, color=None,
          align="center", offset_x=0, offset_y=0, padding=8):
    """Subtle container for grouping related info. Returns lv.obj."""
    p = lv.obj(parent)
    if width is not None and height is not None:
        p.set_size(width, height)
    p.set_style_bg_color(_resolve_color(color, theme.dim), 0)
    p.set_style_border_width(0, 0)
    p.set_style_radius(4, 0)
    p.set_style_pad_all(padding, 0)
    p.align(_resolve_align(align), offset_x, offset_y)
    return p


def indicator(parent, on=False, color=None,
              size=8, align="center", offset_x=0, offset_y=0):
    """Small filled circle for binary/status state. Returns lv.obj."""
    dot = lv.obj(parent)
    dot.set_size(size, size)
    dot.set_style_radius(size // 2, 0)
    dot.set_style_border_width(0, 0)
    dot.set_style_bg_color(
        _resolve_color(color, theme.accent if on else theme.dim), 0)
    dot.align(_resolve_align(align), offset_x, offset_y)
    return dot
