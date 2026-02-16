#!/bin/bash
set -euo pipefail

APP_NAME="MomentumControl"
REPO="idokraicer/sennheiser-modifier"
INSTALL_DIR="/Applications"

echo "==> $APP_NAME Installer"
echo ""

# Check macOS version (requires 14.0+)
MACOS_VERSION=$(sw_vers -productVersion)
MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
if [ "$MAJOR" -lt 14 ]; then
    echo "Error: $APP_NAME requires macOS 14.0 (Sonoma) or later. You have $MACOS_VERSION."
    exit 1
fi

# Find the latest release asset
echo "==> Finding latest release..."
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" \
    | grep "browser_download_url.*macOS.zip" \
    | head -1 \
    | cut -d '"' -f 4)

if [ -z "$DOWNLOAD_URL" ]; then
    echo "Error: Could not find a release. Check https://github.com/$REPO/releases"
    exit 1
fi

TMPDIR_PATH=$(mktemp -d)
trap 'rm -rf "$TMPDIR_PATH"' EXIT

ZIP_PATH="$TMPDIR_PATH/$APP_NAME.zip"

echo "==> Downloading from $DOWNLOAD_URL..."
curl -L -o "$ZIP_PATH" "$DOWNLOAD_URL"

echo "==> Extracting..."
unzip -q "$ZIP_PATH" -d "$TMPDIR_PATH"

# Remove quarantine attribute (since app is not notarized)
xattr -cr "$TMPDIR_PATH/$APP_NAME.app" 2>/dev/null || true

# Kill running instance if any
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

# Install
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "==> Replacing existing installation..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

echo "==> Installing to $INSTALL_DIR..."
cp -R "$TMPDIR_PATH/$APP_NAME.app" "$INSTALL_DIR/"

echo "==> Launching $APP_NAME..."
open "$INSTALL_DIR/$APP_NAME.app"

echo ""
echo "Installed! $APP_NAME is now running in your menu bar."
