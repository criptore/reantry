#!/usr/bin/env bash
set -euo pipefail

# Install Apple's D3DMetal from a Game Porting Toolkit into an existing
# Libraries folder (the one downloaded by Reantry's setup wizard).
#
# Usage:
#   ./scripts/install_gptk.sh [--libraries <path>] [--gptk <path>]
#
#   --libraries <path>  Libraries folder (default: the one used by Reantry).
#   --gptk <path>       Mounted Game Porting Toolkit DMG or its "redist"
#                       folder. If omitted, a mounted toolkit is searched for.
#
# Apple's Game Porting Toolkit must be downloaded from Apple by the user
# (https://developer.apple.com/games/game-porting-toolkit/). This script never
# downloads it, since Apple requires a (free) developer account to do so.

LIBRARIES=""
GPTK_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --libraries) LIBRARIES="$2"; shift 2 ;;
        --gptk) GPTK_PATH="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,24p' "$0"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$LIBRARIES" ]; then
    # Reantry stores its libraries under the app's container.
    CANDIDATES=(
        "$HOME/Library/Application Support/com.isaacmarovitz.Whisky/Libraries"
        "$HOME/Library/Containers/com.isaacmarovitz.Whisky/Data/Library/Application Support/com.isaacmarovitz.Whisky/Libraries"
    )
    for c in "${CANDIDATES[@]}"; do
        if [ -d "$c/Wine" ]; then LIBRARIES="$c"; break; fi
    done
fi
if [ -z "$LIBRARIES" ] || [ ! -d "$LIBRARIES/Wine" ]; then
    echo "Error: Libraries folder not found. Pass it with --libraries <path>."
    exit 1
fi

if [ -z "$GPTK_PATH" ]; then
    for vol in /Volumes/*; do
        if [ -d "$vol/redist/lib/external/D3DMetal.framework" ] || [ -d "$vol/lib/external/D3DMetal.framework" ]; then
            GPTK_PATH="$vol"
            break
        fi
    done
fi

if [ -z "$GPTK_PATH" ]; then
    echo "No Game Porting Toolkit found mounted."
    echo "Download it from https://developer.apple.com/games/game-porting-toolkit/"
    echo "then mount the DMG and re-run this script."
    read -r -p "Open the download page now? [y/N] " answer
    if [ "${answer:-}" = "y" ] || [ "${answer:-}" = "Y" ]; then
        open "https://developer.apple.com/games/game-porting-toolkit/"
    fi
    exit 1
fi

if [ -d "$GPTK_PATH/redist/lib" ]; then
    REDIST="$GPTK_PATH/redist/lib"
elif [ -d "$GPTK_PATH/lib" ]; then
    REDIST="$GPTK_PATH/lib"
else
    echo "Error: no redist/lib folder in $GPTK_PATH"
    exit 1
fi
if [ ! -d "$REDIST/external/D3DMetal.framework" ]; then
    echo "Error: D3DMetal.framework not found in $REDIST/external"
    exit 1
fi

# Save Wine's own Direct3D DLLs for the WineD3D backend, if not already saved.
if [ ! -d "$LIBRARIES/WineD3D" ]; then
    mkdir -p "$LIBRARIES/WineD3D/x64"
    for dll in "$LIBRARIES/Wine/lib/wine/x86_64-windows"/*.dll; do
        [ -f "$dll" ] || continue
        name=$(basename "$dll")
        case "$name" in
            d3d10core.dll|d3d11.dll|d3d12.dll|dxgi.dll|nvapi64.dll|atidxx64.dll)
                cp "$dll" "$LIBRARIES/WineD3D/x64/$name"
                ;;
        esac
    done
fi

echo "==> Installing D3DMetal from $REDIST into $LIBRARIES/Wine/lib"
ditto "$REDIST" "$LIBRARIES/Wine/lib"

echo "==> Done. Restart Reantry to use the D3DMetal backend."
