#!/usr/bin/env bash
set -euo pipefail

# Build Libraries.tar.gz, the Wine libraries downloaded by the setup wizard.
#
# Usage:
#   ./scripts/build_libraries.sh [--engine gptk|staging|sikarugir|crossover] [--wine-dir <path>]
#                                [--gptk <path>] [--version X.Y.Z] [--publish]
#
#   --engine <name>  Wine build to package. Defaults to gptk.
#                    gptk:    Gcenx's Game Porting Toolkit build (CrossOver based, D3DMetal
#                             included). Version set with GPTK_VERSION (default 3.0-3).
#                    staging: Gcenx's Wine Staging build, optionally merged with Apple's
#                             D3DMetal through --gptk.
#                    sikarugir: Sikarugir's WS12WineSikarugir Wine 11.0 (unified wow64, macOS
#                             patches, DXMT's winemetal.dll). Version set with SIKARUGIR_ENGINE
#                             (default WS12WineSikarugir11.0_1).
#                    crossover: Wine built from the CodeWeavers CrossOver sources by
#                             scripts/build_crossover_wine.sh, given with --wine-dir.
#                             Optionally merged with Apple's D3DMetal through --gptk.
#   --wine-dir <path> crossover engine only. Wine folder produced by build_crossover_wine.sh
#                    (bin/wine, bin/wineserver, lib/, share/). It is copied, not moved.
#   --gptk <path>    staging and crossover engines only. Game Porting Toolkit to bundle D3DMetal from:
#                    the mounted DMG
#                    (e.g. "/Volumes/Evaluation environment for Windows games 3.0")
#                    or its "redist" folder. Download it from
#                    https://developer.apple.com/download/all/?q=game%20porting%20toolkit
#   --version X.Y.Z  Version written to WhiskyWineVersion.plist. Defaults to today's date
#                    as YYYY.M.(D*100) (2026.10.2000), which is higher than the 11.18.0
#                    installed by the fallback. Must increase on every publish so installed
#                    apps offer the update: for a second build on the same day add one to
#                    the patch number, e.g. 2026.10.2001 (see docs/Releasing.md).
#   --publish        Upload Libraries.tar.gz and WhiskyWineVersion.plist to the
#                    "libraries" release with the GitHub CLI (gh).
#
# Component versions can be overridden with environment variables, e.g.
#   WINE_VERSION=11.19 ./scripts/build_libraries.sh

GPTK_VERSION="${GPTK_VERSION:-3.0-3}"
SIKARUGIR_ENGINE="${SIKARUGIR_ENGINE:-WS12WineSikarugir11.0_1}"
WINE_VERSION="${WINE_VERSION:-11.18}"
WINE_FLAVOR="${WINE_FLAVOR:-staging}" # staging or devel
DXVK_VERSION="${DXVK_VERSION:-v1.10.3-20230507-repack}"
MOLTENVK_VERSION="${MOLTENVK_VERSION:-v1.4.2}"
WINETRICKS_VERSION="${WINETRICKS_VERSION:-20260125}"

REPOSITORY="criptore/reantry"
RELEASE_TAG="libraries"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="/tmp/libraries-build"
OUTPUT_DIR="$PROJECT_DIR/build"

ENGINE="gptk"
GPTK_PATH=""
WINE_DIR=""
LIBRARIES_VERSION=""
PUBLISH=0

require_value() {
    if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "Error: $1 needs a value"
        exit 1
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --engine) require_value "$@"; ENGINE="$2"; shift 2 ;;
        --gptk) require_value "$@"; GPTK_PATH="$2"; shift 2 ;;
        --wine-dir) require_value "$@"; WINE_DIR="$2"; shift 2 ;;
        --version) require_value "$@"; LIBRARIES_VERSION="$2"; shift 2 ;;
        --publish) PUBLISH=1; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

case "$ENGINE" in
    gptk|staging|sikarugir|crossover) ;;
    *) echo "Error: --engine must be gptk, staging, sikarugir or crossover, got '$ENGINE'"; exit 1 ;;
esac
if [ "$ENGINE" = "crossover" ]; then
    if [ -z "$WINE_DIR" ]; then
        echo "Error: --engine crossover needs --wine-dir <path>, the folder built by"
        echo "       scripts/build_crossover_wine.sh"
        exit 1
    fi
    if [ ! -x "$WINE_DIR/bin/wine" ] || [ ! -x "$WINE_DIR/bin/wineserver" ] || [ ! -d "$WINE_DIR/lib/wine" ]; then
        echo "Error: $WINE_DIR does not look like a Wine folder (bin/wine, bin/wineserver, lib/wine)"
        exit 1
    fi
    WINE_DIR="$(cd "$WINE_DIR" && pwd)"
    # Written by build_crossover_wine.sh: "Wine built from the CrossOver X.Y.Z sources ..."
    CROSSOVER_VERSION=$(sed -n '1s/.*CrossOver \([0-9.]*\) .*/\1/p' "$WINE_DIR/share/doc/wine/SOURCE.txt" 2>/dev/null || true)
    CROSSOVER_VERSION="${CROSSOVER_VERSION:-unknown}"
elif [ -n "$WINE_DIR" ]; then
    echo "Error: --wine-dir is only used with --engine crossover"
    exit 1
fi
if [ "$ENGINE" = "gptk" ] && [ -n "$GPTK_PATH" ]; then
    echo "Error: --gptk is not needed with --engine gptk, D3DMetal is already included."
    echo "       Use --engine staging or crossover to merge Apple's Game Porting Toolkit into Wine."
    exit 1
fi
if [ "$ENGINE" = "sikarugir" ] && [ -n "$GPTK_PATH" ]; then
    echo "Error: --gptk cannot be used with --engine sikarugir, it ships its own DXMT based graphics."
    echo "       Use --engine staging or crossover to merge Apple's Game Porting Toolkit into Wine."
    exit 1
fi

if [ -z "$LIBRARIES_VERSION" ]; then
    # YYYY.M.(D*100), leaving the last two digits for more builds on the same day
    LIBRARIES_VERSION="$(date +%Y).$((10#$(date +%m))).$((10#$(date +%d) * 100))"
fi
if ! [[ "$LIBRARIES_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version must look like X.Y.Z, got '$LIBRARIES_VERSION'"
    exit 1
fi
IFS=. read -r VERSION_MAJOR VERSION_MINOR VERSION_PATCH <<< "$LIBRARIES_VERSION"

download() {
    echo "    $1"
    curl -fL --retry 3 --progress-bar -o "$2" "$1"
}

echo "==> Preparing $BUILD_DIR"
rm -rf "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT
mkdir -p "$BUILD_DIR/downloads" "$BUILD_DIR/extract" "$BUILD_DIR/Libraries"
LIBRARIES="$BUILD_DIR/Libraries"
DOWNLOADS="$BUILD_DIR/downloads"

echo "==> Downloading components"
if [ "$ENGINE" = "gptk" ]; then
    download "https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-$GPTK_VERSION/game-porting-toolkit-$GPTK_VERSION.tar.xz" \
        "$DOWNLOADS/wine.tar.xz"
elif [ "$ENGINE" = "sikarugir" ]; then
    download "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/$SIKARUGIR_ENGINE.tar.xz" \
        "$DOWNLOADS/wine.tar.xz"
elif [ "$ENGINE" = "crossover" ]; then
    # Only needed when the Wine folder has no MoltenVK of its own.
    if [ ! -f "$WINE_DIR/lib/libMoltenVK.dylib" ]; then
        download "https://github.com/KhronosGroup/MoltenVK/releases/download/$MOLTENVK_VERSION/MoltenVK-macos.tar" \
            "$DOWNLOADS/moltenvk.tar"
    fi
else
    download "https://github.com/Gcenx/macOS_Wine_builds/releases/download/$WINE_VERSION/wine-$WINE_FLAVOR-$WINE_VERSION-osx64.tar.xz" \
        "$DOWNLOADS/wine.tar.xz"
    download "https://github.com/KhronosGroup/MoltenVK/releases/download/$MOLTENVK_VERSION/MoltenVK-macos.tar" \
        "$DOWNLOADS/moltenvk.tar"
fi
download "https://github.com/Gcenx/DXVK-macOS/releases/download/$DXVK_VERSION/dxvk-macOS-async-$DXVK_VERSION.tar.gz" \
    "$DOWNLOADS/dxvk.tar.gz"
download "https://raw.githubusercontent.com/Winetricks/winetricks/$WINETRICKS_VERSION/src/winetricks" \
    "$LIBRARIES/winetricks"
download "https://raw.githubusercontent.com/Winetricks/winetricks/$WINETRICKS_VERSION/files/verbs/all.txt" \
    "$LIBRARIES/verbs.txt"
chmod +x "$LIBRARIES/winetricks"

if [ "$ENGINE" = "gptk" ]; then
    echo "==> Installing Game Porting Toolkit $GPTK_VERSION"
elif [ "$ENGINE" = "sikarugir" ]; then
    echo "==> Installing Sikarugir engine $SIKARUGIR_ENGINE"
elif [ "$ENGINE" = "crossover" ]; then
    echo "==> Installing CrossOver Wine from $WINE_DIR"
else
    echo "==> Installing Wine $WINE_FLAVOR $WINE_VERSION"
fi
if [ "$ENGINE" = "crossover" ]; then
    # ditto keeps symlinks, permissions and code signatures.
    ditto "$WINE_DIR" "$BUILD_DIR/extract/crossover-wine"
    WINE_ROOT="$BUILD_DIR/extract/crossover-wine"
elif [ "$ENGINE" = "sikarugir" ]; then
    tar -xf "$DOWNLOADS/wine.tar.xz" -C "$BUILD_DIR/extract"
    # Layout: wswine.bundle/{bin,lib,share,version,dxmt_extescape}. version and dxmt_extescape
    # stay inside Libraries/Wine.
    WINE_ROOT=$(find "$BUILD_DIR/extract" -maxdepth 3 -type d -name "wswine.bundle" | head -1)
else
    tar -xf "$DOWNLOADS/wine.tar.xz" -C "$BUILD_DIR/extract"
    WINE_ROOT=$(find "$BUILD_DIR/extract" -maxdepth 4 -type d -path "*.app/Contents/Resources/wine" | head -1)
fi
if [ -z "$WINE_ROOT" ]; then
    echo "Error: wine folder not found in the Wine archive"
    exit 1
fi
mv "$WINE_ROOT" "$LIBRARIES/Wine"

if [ "$ENGINE" = "gptk" ]; then
    # The app always runs bin/wine, the GPTK build only ships wine64.
    if [ ! -e "$LIBRARIES/Wine/bin/wine" ]; then
        if [ ! -e "$LIBRARIES/Wine/bin/wine64" ]; then
            echo "Error: neither bin/wine nor bin/wine64 found in the archive"
            exit 1
        fi
        ln -s wine64 "$LIBRARIES/Wine/bin/wine"
    fi
    # Started as "wine", the loader looks for wine-preloader. Without it new prefixes get an
    # empty syswow64 and 32-bit programs fail.
    if [ ! -e "$LIBRARIES/Wine/bin/wine-preloader" ]; then
        if [ ! -e "$LIBRARIES/Wine/bin/wine64-preloader" ]; then
            echo "Error: neither bin/wine-preloader nor bin/wine64-preloader found in the archive"
            exit 1
        fi
        ln -s wine64-preloader "$LIBRARIES/Wine/bin/wine-preloader"
    fi
    if [ ! -d "$LIBRARIES/Wine/lib/external/D3DMetal.framework" ]; then
        echo "Error: D3DMetal.framework not found in the archive"
        exit 1
    fi
elif [ "$ENGINE" = "sikarugir" ]; then
    if [ ! -x "$LIBRARIES/Wine/bin/wine" ] || [ ! -e "$LIBRARIES/Wine/bin/wineserver" ]; then
        echo "Error: bin/wine or bin/wineserver not found in the Sikarugir archive"
        exit 1
    fi
elif [ "$ENGINE" = "crossover" ]; then
    if [ -f "$LIBRARIES/Wine/lib/libMoltenVK.dylib" ]; then
        echo "==> Keeping the MoltenVK bundled by build_crossover_wine.sh"
    else
        echo "==> Installing MoltenVK $MOLTENVK_VERSION"
        tar -xf "$DOWNLOADS/moltenvk.tar" -C "$BUILD_DIR/extract"
        cp "$BUILD_DIR/extract/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" "$LIBRARIES/Wine/lib/libMoltenVK.dylib"
    fi
else
    echo "==> Installing MoltenVK $MOLTENVK_VERSION"
    tar -xf "$DOWNLOADS/moltenvk.tar" -C "$BUILD_DIR/extract"
    cp "$BUILD_DIR/extract/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" "$LIBRARIES/Wine/lib/libMoltenVK.dylib"
fi

echo "==> Installing DXVK $DXVK_VERSION"
tar -xzf "$DOWNLOADS/dxvk.tar.gz" -C "$BUILD_DIR/extract"
mkdir -p "$LIBRARIES/DXVK"
cp -R "$BUILD_DIR/extract/dxvk-macOS-async-$DXVK_VERSION/x64" "$LIBRARIES/DXVK/x64"
cp -R "$BUILD_DIR/extract/dxvk-macOS-async-$DXVK_VERSION/x32" "$LIBRARIES/DXVK/x32"

if [ "$ENGINE" = "gptk" ]; then
    echo "==> Note: no WineD3D folder is built, the original wined3d DLLs are not in the archive."
    echo "    The WineD3D backend uses D3DMetal's builtin DLLs with this engine."
elif [ "$ENGINE" = "sikarugir" ]; then
    echo "==> Note: no WineD3D folder is built with the sikarugir engine."
elif [ -n "$GPTK_PATH" ]; then
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

    echo "==> Saving Wine's Direct3D DLLs for the WineD3D backend"
    mkdir -p "$LIBRARIES/WineD3D/x64"
    for dll in "$REDIST"/wine/x86_64-windows/*.dll; do
        name=$(basename "$dll")
        if [ -f "$LIBRARIES/Wine/lib/wine/x86_64-windows/$name" ]; then
            cp "$LIBRARIES/Wine/lib/wine/x86_64-windows/$name" "$LIBRARIES/WineD3D/x64/$name"
        fi
    done

    echo "==> Installing D3DMetal from $REDIST"
    ditto "$REDIST" "$LIBRARIES/Wine/lib"
else
    echo "==> No --gptk given, building without D3DMetal"
fi

echo "==> Writing WhiskyWineVersion.plist ($LIBRARIES_VERSION)"
cat > "$LIBRARIES/WhiskyWineVersion.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>version</key>
	<dict>
		<key>build</key>
		<string></string>
		<key>major</key>
		<integer>$VERSION_MAJOR</integer>
		<key>minor</key>
		<integer>$VERSION_MINOR</integer>
		<key>patch</key>
		<integer>$VERSION_PATCH</integer>
		<key>preRelease</key>
		<string></string>
	</dict>
</dict>
</plist>
EOF
plutil -lint "$LIBRARIES/WhiskyWineVersion.plist"

echo "==> Creating Libraries.tar.gz"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/Libraries.tar.gz" "$OUTPUT_DIR/WhiskyWineVersion.plist"
COPYFILE_DISABLE=1 tar -czf "$OUTPUT_DIR/Libraries.tar.gz" -C "$BUILD_DIR" Libraries
cp "$LIBRARIES/WhiskyWineVersion.plist" "$OUTPUT_DIR/WhiskyWineVersion.plist"

if [ "$PUBLISH" -eq 1 ]; then
    echo "==> Publishing to the $RELEASE_TAG release of $REPOSITORY"
    if ! gh release view "$RELEASE_TAG" --repo "$REPOSITORY" &>/dev/null; then
        gh release create "$RELEASE_TAG" --repo "$REPOSITORY" --title "Wine libraries" \
            --notes "Wine libraries downloaded by the setup wizard. Updated independently from app releases."
    fi
    gh release upload "$RELEASE_TAG" --repo "$REPOSITORY" --clobber \
        "$OUTPUT_DIR/Libraries.tar.gz" "$OUTPUT_DIR/WhiskyWineVersion.plist"
fi

rm -rf "$BUILD_DIR"

echo "==> Done: $OUTPUT_DIR/Libraries.tar.gz (version $LIBRARIES_VERSION)"
if [ "$ENGINE" = "gptk" ]; then
    echo "    Game Porting Toolkit $GPTK_VERSION (D3DMetal included), DXVK $DXVK_VERSION, winetricks $WINETRICKS_VERSION"
elif [ "$ENGINE" = "sikarugir" ]; then
    echo "    Sikarugir engine $SIKARUGIR_ENGINE (DXMT included), DXVK $DXVK_VERSION, winetricks $WINETRICKS_VERSION"
elif [ "$ENGINE" = "crossover" ]; then
    echo "    CrossOver $CROSSOVER_VERSION Wine from $WINE_DIR, DXVK $DXVK_VERSION, winetricks $WINETRICKS_VERSION"
else
    echo "    Wine $WINE_FLAVOR $WINE_VERSION, DXVK $DXVK_VERSION, MoltenVK $MOLTENVK_VERSION, winetricks $WINETRICKS_VERSION"
fi
if [ -n "$GPTK_PATH" ]; then
    echo "    D3DMetal from $GPTK_PATH"
fi
