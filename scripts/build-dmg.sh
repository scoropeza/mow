#!/bin/bash
# Create a DMG for distribution.
# Run after exporting and notarizing Mow.app (see docs/RELEASE.md).
#
# If you see "Operation not permitted" from hdiutil, run this script (or: mise run dmg)
# in the macOS Terminal app; IDEs may not have Full Disk Access needed for DMG creation.
#
# Usage:
#   ./scripts/build-dmg.sh [path-to-Mow.app] [output-dmg-path]
#   If paths omitted: uses Release app from DerivedData, writes mow-<version>.dmg in current dir.

set -e

APP_PATH="$1"
DMG_PATH="$2"
APP_NAME="Mow.app"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"

if [ -z "$APP_PATH" ]; then
  APP_PATH=$(find "$DERIVED" -name "$APP_NAME" -path "*/Build/Products/Release/*" 2>/dev/null | grep -v Index.noindex | head -1)
  if [ -z "$APP_PATH" ]; then
    echo "Error: $APP_NAME not found. Export from archive or pass: $0 /path/to/Mow.app [output.dmg]"
    exit 1
  fi
  echo "Using: $APP_PATH"
fi

if [ ! -d "$APP_PATH" ]; then
  echo "Error: Not a directory: $APP_PATH"
  exit 1
fi

# Version from app's Info.plist, or default
VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0")
DMG_NAME="mow-${VERSION}.dmg"
# ASCII volume name to avoid encoding/permission issues with hdiutil and /Volumes
VOLUME_NAME="Mow ${VERSION}"

if [ -z "$DMG_PATH" ]; then
  DMG_PATH="$(pwd)/$DMG_NAME"
fi

# Unmount any leftover volume from a previous run (avoids "Operation not permitted" on stale mount)
if [ -d "/Volumes/$VOLUME_NAME" ]; then
  hdiutil detach "/Volumes/$VOLUME_NAME" -quiet 2>/dev/null || true
fi

echo "Creating $DMG_PATH ..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# DMG with Applications symlink (common pattern)
ln -s /Applications "$TMP_DIR/Applications"
cp -R "$APP_PATH" "$TMP_DIR/"

hdiutil create -volname "$VOLUME_NAME" -srcfolder "$TMP_DIR" -ov -format UDZO "$DMG_PATH"
echo "Done: $DMG_PATH"
