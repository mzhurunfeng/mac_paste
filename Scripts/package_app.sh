#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="${MACPASTE_PACKAGE_CONFIG:-$ROOT_DIR/Scripts/package_app.conf}"
ENV_CONFIGURATION="${MACPASTE_CONFIGURATION:-}"
ENV_INSTALL_DIR="${MACPASTE_INSTALL_DIR:-}"
ENV_CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

CONFIGURATION="release"
APP_DIR="$ROOT_DIR/.build/MacPaste.app"
INSTALL_APP=0
INSTALL_DIR="/Applications"
CODESIGN_IDENTITY=""

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

if [[ -n "$ENV_CONFIGURATION" ]]; then
    CONFIGURATION="$ENV_CONFIGURATION"
fi
if [[ -n "$ENV_INSTALL_DIR" ]]; then
    INSTALL_DIR="$ENV_INSTALL_DIR"
fi
if [[ -n "$ENV_CODESIGN_IDENTITY" ]]; then
    CODESIGN_IDENTITY="$ENV_CODESIGN_IDENTITY"
fi

for arg in "$@"; do
    case "$arg" in
        debug|release)
            CONFIGURATION="$arg"
            ;;
        --install)
            INSTALL_APP=1
            ;;
        *)
            echo "usage: $0 [debug|release] [--install]" >&2
            exit 2
            ;;
    esac
done

BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
INSTALL_APP_DIR="$INSTALL_DIR/MacPaste.app"

swift build -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/MenuBarIcon.svg" "$APP_DIR/Contents/Resources/MenuBarIcon.svg"
cp "$BUILD_DIR/MacPaste" "$APP_DIR/Contents/MacOS/MacPaste"

if [[ -n "$CODESIGN_IDENTITY" ]]; then
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$APP_DIR"
else
    echo "warning: CODESIGN_IDENTITY is empty; unsigned builds may require accessibility and login-item permission again after rebuild." >&2
fi

if [[ "$INSTALL_APP" -eq 1 ]]; then
    ditto "$APP_DIR" "$INSTALL_APP_DIR"
    echo "$INSTALL_APP_DIR"
else
    echo "$APP_DIR"
fi
