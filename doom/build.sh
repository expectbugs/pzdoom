#!/bin/bash
# Build the PZDOOM binary (doomgeneric + the PZ pipe backend).
#
# What this does, reproducibly, from a fresh checkout of this repo:
#   1. clones ozkl/doomgeneric into doom/doomgeneric/ (gitignored) and pins it
#      to the upstream commit we build against ($DG_COMMIT),
#   2. applies doom/patches/*.patch (idempotent: already-applied patches are
#      detected and skipped),
#   3. copies our backend + makefile from doom/src/ into the clone,
#   4. builds, then refuses a binary that contains BMI2 instructions (they crash
#      on pre-2013 Intel / pre-2015 AMD CPUs — see CHANGELOG 0.2.1).
#
# Prerequisites:
#   Linux   : gcc, make, git, SDL2 + SDL2_mixer development files (sdl2-config)
#   Windows : x86_64-w64-mingw32-gcc (MinGW-w64) whose runtime libs are built
#             for baseline x86-64; the SDL2 / SDL2_mixer MinGW dev packages are
#             downloaded into doom/mingw-sdl2/ automatically if missing.
#
# Usage:
#   ./build.sh                 # Linux build (default)
#   ./build.sh --windows       # Windows cross-build (pzdoom.exe)
#   ./build.sh --all           # both
#   ./build.sh ... --install   # also copy the built binaries into the mod as
#                              # media/doom/pzdoom.dat / pzdoom_win.dat
#   ./build.sh --reset         # discard local edits in the clone and re-apply
#                              # the patches (use when a patch fails to apply)
#   ./build.sh --clean         # remove object files and binaries
#
# Environment overrides (mainly for testing):
#   DG_REPO         git URL/path to clone doomgeneric from
#   MINGW_SDL2_DIR  directory holding SDL2-2.30.12/ and SDL2_mixer-2.8.1/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DG_DIR="$SCRIPT_DIR/doomgeneric"          # upstream clone (gitignored)
DG_SRC="$DG_DIR/doomgeneric"              # upstream source subdir
SRC_DIR="$SCRIPT_DIR/src"                 # our backend + makefile (canonical)
PATCH_DIR="$SCRIPT_DIR/patches"           # our changes to upstream files
MOD_DOOM="$SCRIPT_DIR/../mod/PZDOOM/42/media/doom"

DG_REPO="${DG_REPO:-https://github.com/ozkl/doomgeneric.git}"
# Upstream revision the patches were written and tested against.
DG_COMMIT="3b1d53020373b502035d7d48dede645a7c429feb"

MINGW_SDL2_DIR="${MINGW_SDL2_DIR:-$SCRIPT_DIR/mingw-sdl2}"
SDL2_VER="2.30.12"
SDL2_MIXER_VER="2.8.1"
SDL2_URL="https://github.com/libsdl-org/SDL/releases/download/release-${SDL2_VER}/SDL2-devel-${SDL2_VER}-mingw.tar.gz"
SDL2_MIXER_URL="https://github.com/libsdl-org/SDL_mixer/releases/download/release-${SDL2_MIXER_VER}/SDL2_mixer-devel-${SDL2_MIXER_VER}-mingw.tar.gz"
CROSS_PREFIX="x86_64-w64-mingw32-"

BUILD_LINUX=0
BUILD_WINDOWS=0
DO_INSTALL=0
DO_RESET=0
DO_CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --linux)   BUILD_LINUX=1 ;;
        --windows) BUILD_WINDOWS=1 ;;
        --all)     BUILD_LINUX=1; BUILD_WINDOWS=1 ;;
        --install) DO_INSTALL=1 ;;
        --reset)   DO_RESET=1 ;;
        --clean)   DO_CLEAN=1 ;;
        -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)"; exit 2 ;;
    esac
done
# No target given: build Linux (also after --reset); --clean alone just cleans.
if [ "$BUILD_LINUX" = 0 ] && [ "$BUILD_WINDOWS" = 0 ] && [ "$DO_CLEAN" = 0 ]; then
    BUILD_LINUX=1
fi

die() { echo "ERROR: $*" >&2; exit 1; }

# BMI2 scan (shlx/shrx/sarx/rorx/bzhi/pdep/pext/mulx). Count must be 0.
bmi2_count() {
    local objdump="$1" file="$2"
    "$objdump" -d --no-show-raw-insn "$file" | grep -cE '\s(shlx|shrx|sarx|rorx|bzhi|pdep|pext|mulx)\s' || true
}

# ---------------------------------------------------------------------------
# 1. Upstream clone, pinned
# ---------------------------------------------------------------------------
if [ ! -d "$DG_DIR/.git" ]; then
    echo "Cloning doomgeneric from $DG_REPO ..."
    git clone --quiet "$DG_REPO" "$DG_DIR"
    git -C "$DG_DIR" checkout --quiet "$DG_COMMIT" \
        || die "upstream commit $DG_COMMIT not found in $DG_REPO"
fi

HEAD_COMMIT="$(git -C "$DG_DIR" rev-parse HEAD)"
if [ "$HEAD_COMMIT" != "$DG_COMMIT" ]; then
    echo "WARNING: doomgeneric clone is at $HEAD_COMMIT, patches were tested against $DG_COMMIT."
    echo "         (git -C \"$DG_DIR\" checkout $DG_COMMIT to match)"
fi

if [ "$DO_RESET" = 1 ]; then
    echo "Resetting clone working tree to upstream (keeps the .git dir)..."
    git -C "$DG_DIR" checkout --quiet -- .
    git -C "$DG_DIR" clean --quiet -fdx
fi

if [ "$DO_CLEAN" = 1 ]; then
    if [ -f "$DG_SRC/Makefile.pz" ]; then
        make -C "$DG_SRC" -f Makefile.pz clean >/dev/null
    fi
    echo "Cleaned."
    [ "$BUILD_LINUX" = 1 ] || [ "$BUILD_WINDOWS" = 1 ] || exit 0
fi

# ---------------------------------------------------------------------------
# 2. Patches (idempotent)
# ---------------------------------------------------------------------------
shopt -s nullglob
PATCHES=("$PATCH_DIR"/*.patch)
shopt -u nullglob
[ "${#PATCHES[@]}" -gt 0 ] || die "no patches found in $PATCH_DIR"
for p in "${PATCHES[@]}"; do
    name="$(basename "$p")"
    if git -C "$DG_DIR" apply --check --reverse "$p" 2>/dev/null; then
        echo "patch already applied: $name"
    elif git -C "$DG_DIR" apply --check "$p" 2>/dev/null; then
        git -C "$DG_DIR" apply "$p"
        echo "patch applied: $name"
    else
        die "patch $name neither applied nor applicable — the clone has other local changes. Run: $0 --reset"
    fi
done

# ---------------------------------------------------------------------------
# 3. Our backend + makefile (src/ is canonical; the clone copies are gitignored)
# ---------------------------------------------------------------------------
for f in doomgeneric_pz.c Makefile.pz; do
    [ -f "$SRC_DIR/$f" ] || die "missing $SRC_DIR/$f"
    if ! cmp -s "$SRC_DIR/$f" "$DG_SRC/$f"; then
        cp "$SRC_DIR/$f" "$DG_SRC/$f"
    fi
done

# ---------------------------------------------------------------------------
# 4. Build
# ---------------------------------------------------------------------------
JOBS="$(nproc 2>/dev/null || echo 4)"

if [ "$BUILD_LINUX" = 1 ]; then
    command -v sdl2-config >/dev/null || die "sdl2-config not found (install SDL2 + SDL2_mixer dev packages)"
    echo "Building pzdoom (Linux)..."
    make -C "$DG_SRC" -f Makefile.pz -j"$JOBS"
    n="$(bmi2_count objdump "$DG_SRC/pzdoom")"
    [ "$n" = 0 ] || die "pzdoom contains $n BMI2 instruction(s) — not shippable"
    echo "Built: $DG_SRC/pzdoom (BMI2 instructions: $n)"
fi

if [ "$BUILD_WINDOWS" = 1 ]; then
    command -v "${CROSS_PREFIX}gcc" >/dev/null || die "${CROSS_PREFIX}gcc not found (install a MinGW-w64 cross toolchain)"
    mkdir -p "$MINGW_SDL2_DIR"
    if [ ! -d "$MINGW_SDL2_DIR/SDL2-$SDL2_VER/x86_64-w64-mingw32" ]; then
        echo "Downloading SDL2 $SDL2_VER MinGW dev package..."
        curl -fL --retry 3 -o "$MINGW_SDL2_DIR/sdl2.tar.gz" "$SDL2_URL"
        tar xzf "$MINGW_SDL2_DIR/sdl2.tar.gz" -C "$MINGW_SDL2_DIR"
    fi
    if [ ! -d "$MINGW_SDL2_DIR/SDL2_mixer-$SDL2_MIXER_VER/x86_64-w64-mingw32" ]; then
        echo "Downloading SDL2_mixer $SDL2_MIXER_VER MinGW dev package..."
        curl -fL --retry 3 -o "$MINGW_SDL2_DIR/sdl2_mixer.tar.gz" "$SDL2_MIXER_URL"
        tar xzf "$MINGW_SDL2_DIR/sdl2_mixer.tar.gz" -C "$MINGW_SDL2_DIR"
    fi
    echo "Building pzdoom.exe (Windows, baseline x86-64)..."
    make -C "$DG_SRC" -f Makefile.pz CROSS="$CROSS_PREFIX" MINGW_SDL2="$MINGW_SDL2_DIR" -j"$JOBS"
    n="$(bmi2_count "${CROSS_PREFIX}objdump" "$DG_SRC/pzdoom.exe")"
    [ "$n" = 0 ] || die "pzdoom.exe contains $n BMI2 instruction(s) — rebuild the MinGW runtime for baseline x86-64 (see CHANGELOG 0.2.1)"
    echo "Built: $DG_SRC/pzdoom.exe (BMI2 instructions: $n)"
fi

# ---------------------------------------------------------------------------
# 5. Install into the mod (Workshop rejects .exe/.dll/ELF names, so .dat)
# ---------------------------------------------------------------------------
if [ "$DO_INSTALL" = 1 ]; then
    mkdir -p "$MOD_DOOM"
    if [ "$BUILD_LINUX" = 1 ]; then
        cp "$DG_SRC/pzdoom" "$MOD_DOOM/pzdoom.dat"
        chmod +x "$MOD_DOOM/pzdoom.dat"
        echo "Installed: $MOD_DOOM/pzdoom.dat"
    fi
    if [ "$BUILD_WINDOWS" = 1 ]; then
        cp "$DG_SRC/pzdoom.exe" "$MOD_DOOM/pzdoom_win.dat"
        echo "Installed: $MOD_DOOM/pzdoom_win.dat"
        # Runtime DLLs ship once; only seed them if absent.
        for pair in "SDL2-$SDL2_VER/x86_64-w64-mingw32/bin/SDL2.dll:SDL2.dat" \
                    "SDL2_mixer-$SDL2_MIXER_VER/x86_64-w64-mingw32/bin/SDL2_mixer.dll:SDL2_mixer.dat"; do
            src="$MINGW_SDL2_DIR/${pair%%:*}"; dst="$MOD_DOOM/${pair##*:}"
            if [ ! -f "$dst" ] && [ -f "$src" ]; then
                cp "$src" "$dst"; echo "Installed: $dst"
            fi
        done
    fi
    (cd "$MOD_DOOM" && sha256sum pzdoom.dat pzdoom_win.dat 2>/dev/null || true)
fi

echo "Done."
