#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="/tmp/reantry-build"
STAGING_DIR="$BUILD_DIR/staging"
DMG_NAME="Reantry.dmg"
DMG_OUTPUT="$PROJECT_DIR/$DMG_NAME"
SCHEME="Whisky"
CONFIGURATION="Release"

echo "==> Cleaning previous build artifacts..."
rm -rf "$BUILD_DIR"
rm -f "$DMG_OUTPUT"
mkdir -p "$BUILD_DIR"

echo "==> Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
    -project "$PROJECT_DIR/Whisky.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "Reantry.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
    echo "Error: Reantry.app not found in DerivedData"
    exit 1
fi

echo "==> Staging DMG contents..."
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/Reantry.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating DMG..."
hdiutil create \
    -volname "Reantry" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_OUTPUT"

echo "==> Cleaning up..."
rm -rf "$BUILD_DIR"

echo "==> Done! DMG created at: $DMG_OUTPUT"
