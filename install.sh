#!/bin/bash
set -e

APP_NAME="MomentumControl"
INSTALL_DIR="/Applications"
PROJECT_DIR="MomentumControl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BOLD}==> $1${NC}"; }
ok()    { echo -e "${GREEN}==> $1${NC}"; }
warn()  { echo -e "${YELLOW}==> $1${NC}"; }
fail()  { echo -e "${RED}==> $1${NC}"; exit 1; }

# Navigate to repo root (where this script lives)
cd "$(dirname "$0")"

# ── Prerequisites ────────────────────────────────────────────────

info "Checking prerequisites..."

if ! xcode-select -p &>/dev/null; then
    fail "Xcode Command Line Tools not found. Install with: xcode-select --install"
fi

if ! command -v xcodebuild &>/dev/null; then
    fail "Xcode not found. Install Xcode from the App Store."
fi

if ! command -v xcodegen &>/dev/null; then
    warn "XcodeGen not found. Installing via Homebrew..."
    if ! command -v brew &>/dev/null; then
        fail "Homebrew not found. Install from https://brew.sh or install XcodeGen manually."
    fi
    brew install xcodegen
fi

# ── Generate Xcode project ──────────────────────────────────────

info "Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate --quiet

# ── Build ────────────────────────────────────────────────────────

info "Building ${APP_NAME} (Release)..."
BUILD_DIR="$(mktemp -d)"

xcodebuild \
    -project "${APP_NAME}.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -quiet

APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    fail "Build failed — ${APP_NAME}.app not found."
fi

ok "Build succeeded."

# ── Install ──────────────────────────────────────────────────────

info "Installing to ${INSTALL_DIR}/${APP_NAME}.app..."

if [ -d "${INSTALL_DIR}/${APP_NAME}.app" ]; then
    warn "Existing installation found. Replacing..."
    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
fi

cp -R "$APP_PATH" "$INSTALL_DIR/"
rm -rf "$BUILD_DIR"

ok "${APP_NAME} installed to ${INSTALL_DIR}/${APP_NAME}.app"
echo ""
echo -e "${BOLD}Launch from Applications or run:${NC}"
echo "  open ${INSTALL_DIR}/${APP_NAME}.app"
