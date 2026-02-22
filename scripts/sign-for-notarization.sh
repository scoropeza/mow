#!/bin/bash
# Re-sign Mow.app (and nested frameworks) with Developer ID and secure timestamp.
# Run this before notarize if your build used ad-hoc signing (e.g. mise build without a Developer ID cert).
#
# Requires: Developer ID Application certificate in your keychain.
# Set CODESIGN_IDENTITY to the full name (e.g. "Developer ID Application: Your Name (TEAM_ID)")
# or leave unset to use the first "Developer ID Application" identity found.
#
# Usage: ./scripts/sign-for-notarization.sh [path-to-Mow.app]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENTITLEMENTS="$REPO_ROOT/mow/mow/mow.entitlements"

APP_PATH="${1:-}"
if [ -z "$APP_PATH" ]; then
  BUILD_DIR="build"
  APP_PATH="$REPO_ROOT/$BUILD_DIR/Build/Products/Release/Mow.app"
fi
if [ ! -d "$APP_PATH" ] || [ "$(basename "$APP_PATH")" != "Mow.app" ]; then
  echo "Usage: $0 /path/to/Mow.app"
  exit 1
fi
if [ ! -f "$ENTITLEMENTS" ]; then
  echo "Error: Entitlements file not found: $ENTITLEMENTS"
  exit 1
fi

if [ -z "$CODESIGN_IDENTITY" ]; then
  CODESIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed 's/^[[:space:]]*[0-9]*) \([^"]*\)".*/\1/')
  if [ -z "$CODESIGN_IDENTITY" ]; then
    echo "Error: No 'Developer ID Application' identity found. Install the cert in Keychain or set CODESIGN_IDENTITY."
    exit 1
  fi
  echo "Using identity: $CODESIGN_IDENTITY"
fi

echo "Signing nested binaries and frameworks with Developer ID + timestamp..."
# 1) Binaries inside .framework (e.g. llama.framework/Versions/A/llama)
find "$APP_PATH/Contents/Frameworks" -type d -name "*.framework" 2>/dev/null | while read -r fw; do
  for bin in "$fw/Versions/A/"*; do
    [ -f "$bin" ] && file -b "$bin" | grep -q Mach-O && \
      codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp "$bin"
  done
  codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp "$fw"
done
# 2) Any .dylib in Frameworks
find "$APP_PATH/Contents/Frameworks" -name "*.dylib" -type f 2>/dev/null | while read -r dylib; do
  codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp "$dylib"
done
# 3) Main app bundle (must pass entitlements or re-sign strips them and TCC prompt won't show)
codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp --entitlements "$ENTITLEMENTS" "$APP_PATH"

echo "Done. $APP_PATH is signed for notarization."
