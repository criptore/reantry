#!/usr/bin/env bash
set -euo pipefail

# Build Libraries.tar.gz, the Wine libraries downloaded by the setup wizard.
#
# Usage:
#   ./scripts/build_libraries.sh [--gptk <path>] [--version X.Y.Z] [--publish]
#
#   --gptk <path>    Game Porting Toolkit to bundle D3DMetal from: the mounted DMG
#                    (e.g. "/Volumes/Evaluation environment for Windows games 3.0")
#                    or its "redist" folder. Download it from
#                    https://developer.apple.com/download/all/?q=game%20porting%20toolkit
#   --version X.Y.Z  Version written to WhiskyWineVersion.plist. Defaults to the Wine
#                    version (11.18 -> 11.18.0). Must increase on every publish so
#                    installed apps offer the update.
#   --publish        Upload Libraries.tar.gz and WhiskyWineVersion.plist to the
#                    "libraries" release with the GitHub CLI (gh).
#
# Component versions can be overridden with environment variables, e.g.
#   WINE_VERSION=11.19 ./scripts/build_libraries.sh

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

GPTK_PATH=""
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
        --gptk) require_value "$@"; GPTK_PATH="$2"; shift 2 ;;
        --version) require_value "$@"; LIBRARIES_VERSION="$2"; shift 2 ;;
        --publish) PUBLISH=1; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$LIBRARIES_VERSION" ]; then
    IFS=. read -r MAJOR MINOR PATCH <<< "$WINE_VERSION"
    LIBRARIES_VERSION="${MAJOR}.${MINOR:-0}.${PATCH:-0}"
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
download "https://github.com/Gcenx/macOS_Wine_builds/releases/download/$WINE_VERSION/wine-$WINE_FLAVOR-$WINE_VERSION-osx64.tar.xz" \
    "$DOWNLOADS/wine.tar.xz"
download "https://github.com/Gcenx/DXVK-macOS/releases/download/$DXVK_VERSION/dxvk-macOS-async-$DXVK_VERSION.tar.gz" \
    "$DOWNLOADS/dxvk.tar.gz"
download "https://github.com/KhronosGroup/MoltenVK/releases/download/$MOLTENVK_VERSION/MoltenVK-macos.tar" \
    "$DOWNLOADS/moltenvk.tar"
download "https://raw.githubusercontent.com/Winetricks/winetricks/$WINETRICKS_VERSION/src/winetricks" \
    "$LIBRARIES/winetricks"
download "https://raw.githubusercontent.com/Winetricks/winetricks/$WINETRICKS_VERSION/files/verbs/all.txt" \
    "$LIBRARIES/verbs.txt"
chmod +x "$LIBRARIES/winetricks"

echo "==> Installing Wine $WINE_FLAVOR $WINE_VERSION"
tar -xf "$DOWNLOADS/wine.tar.xz" -C "$BUILD_DIR/extract"
WINE_ROOT=$(find "$BUILD_DIR/extract" -maxdepth 4 -type d -path "*.app/Contents/Resources/wine" | head -1)
if [ -z "$WINE_ROOT" ]; then
    echo "Error: wine folder not found in the Wine archive"
    exit 1
fi
mv "$WINE_ROOT" "$LIBRARIES/Wine"

echo "==> Installing MoltenVK $MOLTENVK_VERSION"
tar -xf "$DOWNLOADS/moltenvk.tar" -C "$BUILD_DIR/extract"
cp "$BUILD_DIR/extract/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" "$LIBRARIES/Wine/lib/libMoltenVK.dylib"

echo "==> Installing DXVK $DXVK_VERSION"
tar -xzf "$DOWNLOADS/dxvk.tar.gz" -C "$BUILD_DIR/extract"
mkdir -p "$LIBRARIES/DXVK"
cp -R "$BUILD_DIR/extract/dxvk-macOS-async-$DXVK_VERSION/x64" "$LIBRARIES/DXVK/x64"
cp -R "$BUILD_DIR/extract/dxvk-macOS-async-$DXVK_VERSION/x32" "$LIBRARIES/DXVK/x32"

if [ -n "$GPTK_PATH" ]; then
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
echo "    Wine $WINE_FLAVOR $WINE_VERSION, DXVK $DXVK_VERSION, MoltenVK $MOLTENVK_VERSION, winetricks $WINETRICKS_VERSION"
if [ -n "$GPTK_PATH" ]; then
    echo "    D3DMetal from $GPTK_PATH"
fi
