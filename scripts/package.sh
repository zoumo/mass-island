#!/bin/bash
# Package Mass Island as DMG (no Apple Developer ID required)
# Usage: ./scripts/package.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Mass Island"
DMG_NAME="MassIsland"

echo "=== Packaging $APP_NAME ==="
echo ""

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$PROJECT_DIR"

# Build Release
echo "Building..."
XCODEBUILD_CMD=(xcodebuild -scheme ClaudeIsland -configuration Release \
    -derivedDataPath "$BUILD_DIR/derived" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    ENABLE_HARDENED_RUNTIME=NO)

set +e
if command -v xcpretty &> /dev/null; then
    "${XCODEBUILD_CMD[@]}" 2>&1 | xcpretty
    BUILD_EXIT=${PIPESTATUS[0]}
else
    "${XCODEBUILD_CMD[@]}"
    BUILD_EXIT=$?
fi
set -e

if [ "$BUILD_EXIT" -ne 0 ]; then
    echo "ERROR: Build failed."
    exit 1
fi

# Locate built app
APP_PATH="$BUILD_DIR/derived/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    # Fallback: try ClaudeIsland.app
    APP_PATH="$BUILD_DIR/derived/Build/Products/Release/ClaudeIsland.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found in build output"
    ls -la "$BUILD_DIR/derived/Build/Products/Release/" 2>/dev/null
    exit 1
fi

echo ""
echo "App built: $APP_PATH"

# Get version
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
echo "Version: $VERSION"

# Create DMG
DMG_PATH="$BUILD_DIR/$DMG_NAME-$VERSION.dmg"
rm -f "$DMG_PATH"

echo ""
echo "Creating DMG..."

if command -v create-dmg &> /dev/null; then
    create-dmg \
        --volname "$APP_NAME" \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 150 200 \
        --app-drop-link 450 200 \
        --hide-extension "$APP_NAME.app" \
        "$DMG_PATH" \
        "$APP_PATH"
else
    echo "(install create-dmg for prettier DMG: brew install create-dmg)"
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$APP_PATH" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

echo ""
echo "=== Done ==="
echo "DMG: $DMG_PATH"
echo ""
echo "Installation:"
echo "  1. Open DMG, drag to Applications"
echo "  2. Run: xattr -cr /Applications/$APP_NAME.app"
echo "  3. Double-click to launch"
