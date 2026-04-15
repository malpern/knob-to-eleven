#!/bin/bash
# Bootstrap a fresh checkout of knob-to-eleven on macOS.
# Clones lv_micropython, applies the Apple-clang warning patches we discovered
# during the spike, builds the Unix+LVGL+SDL variant, and drops the binary at
# bin/micropython so the eleven CLI can find it.
#
# Idempotent — re-running is safe and skips work already done.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LV_DIR="$REPO_ROOT/lib/lv_micropython"
OUT_BIN="$REPO_ROOT/bin/micropython"

# Clang flags needed on Apple clang 17+; the binding generators in
# lv_micropython trip a few -Werror checks that older clang only warned on.
CFLAGS_EXTRA="-Wno-error=gnu-folding-constant -Wno-error=deprecated-non-prototype \
-Wno-error=unused-command-line-argument -Wno-error=unused-function \
-Wno-error=unused-variable -Wno-error=unused-but-set-variable \
-Wno-error=sign-compare"

step() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Verify prerequisites

step "Checking prerequisites"
need=()
for tool in git make cmake gcc python3 pkg-config; do
    command -v "$tool" >/dev/null 2>&1 || need+=("$tool")
done
if (( ${#need[@]} > 0 )); then
    die "missing tools: ${need[*]} — install via Homebrew or Xcode Command Line Tools"
fi
ok "core tools present"

if ! pkg-config --exists sdl2; then
    die "SDL2 not found — install with: brew install sdl2"
fi
ok "SDL2 installed: $(pkg-config --modversion sdl2)"

if ! /usr/libexec/java_home -v 17+ >/dev/null 2>&1; then
    # Java is needed by some MicroPython submodule build steps. Most macOS
    # systems have it via Homebrew openjdk; warn rather than die.
    echo "  warn: no Java 17+ found via /usr/libexec/java_home — Homebrew openjdk@21 recommended"
fi

# ---------------------------------------------------------------------------
# 2. Clone lv_micropython if missing

if [[ -d "$LV_DIR/.git" ]]; then
    ok "lv_micropython already cloned at $LV_DIR"
else
    step "Cloning lv_micropython (recursive, shallow — ~250MB)"
    mkdir -p "$REPO_ROOT/lib"
    git clone --depth 1 --recursive https://github.com/lvgl/lv_micropython.git "$LV_DIR"
    ok "cloned"
fi

# ---------------------------------------------------------------------------
# 3. Build mpy-cross

if [[ -x "$LV_DIR/mpy-cross/build/mpy-cross" ]]; then
    ok "mpy-cross already built"
else
    step "Building mpy-cross"
    make -C "$LV_DIR/mpy-cross" CFLAGS_EXTRA="$CFLAGS_EXTRA"
    ok "mpy-cross built"
fi

# ---------------------------------------------------------------------------
# 3.5. Configure extra fonts for the simulator
#
# Stock lv_micropython enables only a handful of Montserrat sizes and no
# bold variant. Our widgets (the clock especially) want Montserrat 12
# for small labels and Montserrat-Bold 24 for time values. Both are
# stock LVGL fonts; we just have to enable / generate them.
#
# This step is idempotent: it inspects the relevant files and only
# patches them when they don't already have what we need. If anything
# is patched, the unix port is rebuilt below to pick up the new fonts.

LV_BIND_DIR="$LV_DIR/user_modules/lv_binding_micropython"
LV_CONF_H="$LV_BIND_DIR/lv_conf.h"
LV_FONT_DIR="$LV_BIND_DIR/lvgl/src/font"
LV_FONT_H="$LV_FONT_DIR/lv_font.h"
BOLD_TTF="$LV_BIND_DIR/lvgl/tests/src/test_files/fonts/Montserrat-Bold.ttf"
BOLD_C="$LV_FONT_DIR/lv_font_montserrat_bold_24.c"

FONTS_CHANGED=0

step "Configuring extra simulator fonts"

# (a) Enable LV_FONT_MONTSERRAT_12 in lv_conf.h.
if grep -q '^#define LV_FONT_MONTSERRAT_12 1' "$LV_CONF_H"; then
    ok "Montserrat 12 already enabled"
else
    sed -i.bak 's|^#define LV_FONT_MONTSERRAT_12 .*|#define LV_FONT_MONTSERRAT_12 1|' "$LV_CONF_H"
    rm -f "$LV_CONF_H.bak"
    FONTS_CHANGED=1
    ok "enabled LV_FONT_MONTSERRAT_12"
fi

# (b) Add the LV_FONT_MONTSERRAT_BOLD_24 define if missing. We append
#     it after the MONTSERRAT_48 line so it groups with the other size
#     defines.
if grep -q 'LV_FONT_MONTSERRAT_BOLD_24' "$LV_CONF_H"; then
    ok "Montserrat-Bold 24 define already present"
else
    awk '
        { print }
        /^#define LV_FONT_MONTSERRAT_48 / && !done {
            print ""
            print "/* Custom Montserrat-Bold 24 — generated via lv_font_conv. */"
            print "#define LV_FONT_MONTSERRAT_BOLD_24 1"
            done = 1
        }
    ' "$LV_CONF_H" > "$LV_CONF_H.tmp" && mv "$LV_CONF_H.tmp" "$LV_CONF_H"
    FONTS_CHANGED=1
    ok "added LV_FONT_MONTSERRAT_BOLD_24 define"
fi

# (c) Add the LV_FONT_DECLARE so MicroPython's binding generator picks
#     up the new font symbol.
if grep -q 'LV_FONT_DECLARE(lv_font_montserrat_bold_24)' "$LV_FONT_H"; then
    ok "Montserrat-Bold 24 declared in lv_font.h"
else
    awk '
        { print }
        /^LV_FONT_DECLARE\(lv_font_montserrat_28_compressed\)/ && !done {
            getline next_line
            print next_line       # the closing #endif
            print ""
            print "#if LV_FONT_MONTSERRAT_BOLD_24"
            print "LV_FONT_DECLARE(lv_font_montserrat_bold_24)"
            print "#endif"
            done = 1
        }
    ' "$LV_FONT_H" > "$LV_FONT_H.tmp" && mv "$LV_FONT_H.tmp" "$LV_FONT_H"
    FONTS_CHANGED=1
    ok "added LV_FONT_DECLARE for Montserrat-Bold 24"
fi

# (d) Generate the bold .c via lv_font_conv if missing. Skip gracefully
#     when npx isn't installed — the app falls back to regular
#     Montserrat 24 via wlsdk's _pick_font.
if [[ -f "$BOLD_C" ]]; then
    ok "lv_font_montserrat_bold_24.c already generated"
elif command -v npx >/dev/null 2>&1; then
    if [[ ! -f "$BOLD_TTF" ]]; then
        echo "  warn: $BOLD_TTF missing — skipping bold font generation"
    else
        echo "  generating lv_font_montserrat_bold_24.c (one-time, ~30s) …"
        npx --yes lv_font_conv@1.5.3 \
            --bpp 4 --size 24 --font "$BOLD_TTF" \
            -r 0x20-0x7F --format lvgl --no-compress \
            --force-fast-kern-format \
            -o "$BOLD_C" >/dev/null 2>&1
        # The generator hard-codes `#include "lvgl.h"`, but the build
        # tree expects the relative form other Montserrat .c files use.
        sed -i.bak 's|^#include "lvgl.h"$|#include "../../lvgl.h"|' "$BOLD_C"
        rm -f "$BOLD_C.bak"
        FONTS_CHANGED=1
        ok "generated lv_font_montserrat_bold_24.c"
    fi
else
    echo "  warn: npx not found — install Node (e.g. \`brew install node\`) and"
    echo "        re-run bootstrap to enable the bold time font. The clock"
    echo "        widget will fall back to regular Montserrat 24 in the meantime."
fi

# ---------------------------------------------------------------------------
# 4. Build the Unix port with the lvgl variant

UNIX_BIN="$LV_DIR/ports/unix/build-lvgl/micropython"
if [[ -x "$UNIX_BIN" && "$FONTS_CHANGED" == "0" ]]; then
    ok "lv_micropython unix port already built"
else
    if [[ "$FONTS_CHANGED" == "1" && -x "$UNIX_BIN" ]]; then
        step "Font config changed — wiping build to pick up new fonts"
        rm -rf "$LV_DIR/ports/unix/build-lvgl"
    fi
    step "Building lv_micropython unix port (variant=lvgl) — ~5 min first time"
    make -C "$LV_DIR/ports/unix" VARIANT=lvgl CFLAGS_EXTRA="$CFLAGS_EXTRA"
    ok "unix port built"
fi

# ---------------------------------------------------------------------------
# 5. Symlink into bin/

mkdir -p "$REPO_ROOT/bin"
if [[ -L "$OUT_BIN" ]] && [[ "$(readlink "$OUT_BIN")" == "$UNIX_BIN" ]]; then
    ok "bin/micropython already symlinked"
else
    ln -sf "$UNIX_BIN" "$OUT_BIN"
    ok "symlinked $OUT_BIN -> $UNIX_BIN"
fi

# ---------------------------------------------------------------------------
# 6. Smoke test

step "Smoke test"
"$OUT_BIN" -c "import lvgl as lv; print('lvgl', lv.version_major(), 'OK')"

step "Building Swift CLI"
if command -v swift >/dev/null 2>&1; then
    (cd "$REPO_ROOT/mac" && swift build) > /dev/null
    ok "Swift CLI built at mac/.build/debug/eleven"
else
    echo "  warn: swift not found — install Xcode Command Line Tools to build the Swift CLI"
fi

cat <<EOF

🎉 Bootstrap complete.

Try:
  $REPO_ROOT/mac/.build/debug/eleven run $REPO_ROOT/examples/hello.py
  $REPO_ROOT/mac/.build/debug/eleven run $REPO_ROOT/examples/cpu/
  $REPO_ROOT/tests/run_all.sh
EOF
