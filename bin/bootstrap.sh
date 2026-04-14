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
# 4. Build the Unix port with the lvgl variant

UNIX_BIN="$LV_DIR/ports/unix/build-lvgl/micropython"
if [[ -x "$UNIX_BIN" ]]; then
    ok "lv_micropython unix port already built"
else
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
