#!/bin/bash
set -euo pipefail

APP_NAME="MomentumControl"
PROJECT_DIR="MomentumControl"
BUILD_DIR="build"
OUTPUT_DIR="dist"

cd "$(dirname "$0")"

# Check for Xcode
if ! command -v xcodebuild &>/dev/null; then
    echo "Error: Xcode is required to build. Install it from the App Store."
    exit 1
fi

# Generate Xcode project if xcodegen is available and project.yml exists
if [ -f "$PROJECT_DIR/project.yml" ] && command -v xcodegen &>/dev/null; then
    echo "==> Generating Xcode project..."
    (cd "$PROJECT_DIR" && xcodegen generate)
fi

echo "==> Building $APP_NAME (Release)..."
xcodebuild \
    -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tail -5

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Build failed — $APP_PATH not found."
    exit 1
fi

# Ad-hoc sign so it runs on other Macs without being rejected outright
echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "$APP_PATH"

# Package
mkdir -p "$OUTPUT_DIR"
VERSION=$(defaults read "$(pwd)/$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
ZIP_NAME="${APP_NAME}-v${VERSION}-macOS.zip"

ABSOLUTE_OUTPUT="$(pwd)/$OUTPUT_DIR"
echo "==> Creating $OUTPUT_DIR/$ZIP_NAME..."
(cd "$(dirname "$APP_PATH")" && zip -r -y -q "$ABSOLUTE_OUTPUT/$ZIP_NAME" "$APP_NAME.app")

echo ""
echo "Done! Distributable archive: $OUTPUT_DIR/$ZIP_NAME"
echo ""
echo "To create a GitHub release:"
echo "  gh release create v$VERSION $OUTPUT_DIR/$ZIP_NAME --title \"$APP_NAME v$VERSION\" --notes \"Pre-built macOS app\""
