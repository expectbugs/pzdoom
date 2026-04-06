#!/bin/bash
# Build the PZDOOM binary (doomgeneric with PZ pipe backend)
#
# Prerequisites:
#   - gcc, make
#   - SDL2 + SDL2_mixer development libraries
#   - doomgeneric source (cloned automatically if missing)
#
# Usage:
#   ./build.sh              # Build for Linux
#   ./build.sh --install    # Build and copy to mod directory

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DG_DIR="$SCRIPT_DIR/doomgeneric"
DG_SRC="$DG_DIR/doomgeneric"
MOD_DOOM="$SCRIPT_DIR/../mod/PZDOOM/42/media/doom"

# Clone doomgeneric if not present
if [ ! -d "$DG_DIR" ]; then
    echo "Cloning doomgeneric..."
    git clone https://github.com/ozkl/doomgeneric.git "$DG_DIR"
fi

# Copy our platform backend if not already there
if [ ! -f "$DG_SRC/doomgeneric_pz.c" ]; then
    echo "ERROR: doomgeneric_pz.c not found in $DG_SRC"
    echo "It should have been created during development."
    exit 1
fi

# Build
echo "Building pzdoom for Linux..."
cd "$DG_SRC"
make -f Makefile.pz clean
make -f Makefile.pz -j$(nproc)

echo ""
echo "Built: $DG_SRC/pzdoom"
file "$DG_SRC/pzdoom"

# Install to mod directory
if [ "$1" = "--install" ]; then
    mkdir -p "$MOD_DOOM"
    cp "$DG_SRC/pzdoom" "$MOD_DOOM/pzdoom"
    chmod +x "$MOD_DOOM/pzdoom"
    echo "Installed to $MOD_DOOM/pzdoom"
fi

echo "Done."
