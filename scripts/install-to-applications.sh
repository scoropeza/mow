#!/bin/bash
# USED ONLY FOR DEBUGGING PURPOSES
# Copy Mow.app to /Applications and fix code signing so it opens (no "damaged or incomplete").
# Run from repo root: ./scripts/install-to-applications.sh
# Prereq: build the app in Xcode first (Product → Build, destination: My Mac).

set -e
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
APP_NAME="Mow.app"

# Find the macOS built app (exclude Index build and iOS/simulator)
SRC=$(find "$DERIVED" -name "$APP_NAME" -path "*/Build/Products/Debug/*" 2>/dev/null | grep -v Index.noindex | grep -v -i iphone | grep -v -i simulator | head -1)
if [ -z "$SRC" ]; then
  echo "Error: $APP_NAME not found. Build the app in Xcode first (⌘B, destination: My Mac)."
  exit 1
fi

# Ensure it looks like a valid app bundle
if [ ! -f "$SRC/Contents/MacOS/mow" ] && [ ! -f "$SRC/Contents/MacOS/$(basename "$APP_NAME" .app)" ]; then
  EXEC_NAME=$(ls "$SRC/Contents/MacOS/" 2>/dev/null | head -1)
  if [ -z "$EXEC_NAME" ]; then
    echo "Error: $SRC does not look like a valid app bundle (no Contents/MacOS executable)."
    echo "Found at: $SRC"
    exit 1
  fi
fi

DEST="/Applications/$APP_NAME"
echo "Copying $SRC → $DEST"
rm -rf "$DEST"
ditto "$SRC" "$DEST"

echo "Removing quarantine..."
xattr -cr "$DEST"

echo "Re-signing app (ad-hoc)..."
# Sign without --deep to avoid "bundle format unrecognized" on nested content
codesign --force --sign - "$DEST"

echo "Done. Opening..."
open "$DEST"
