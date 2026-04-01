#!/bin/bash
# Ad-hoc sign Mow.app for local development (no Developer ID needed).
#
# What this does:
#   1. Signs embedded frameworks (e.g. llama.framework) with ad-hoc identity
#   2. Signs the main app with dev entitlements (sandbox disabled, library
#      validation disabled) so the app can launch and load all frameworks
#
# Why: Release builds expect a Developer ID certificate. Without one, the app
# crashes on launch because macOS Library Validation rejects embedded frameworks
# with mismatched signatures. This script re-signs everything consistently.
#
# Usage: ./scripts/sign-for-dev.sh [path-to-Mow.app]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_PATH="${1:-}"
if [ -z "$APP_PATH" ]; then
  APP_PATH="$REPO_ROOT/build/Build/Products/Release/Mow.app"
fi
if [ ! -d "$APP_PATH" ] || [ "$(basename "$APP_PATH")" != "Mow.app" ]; then
  echo "Error: Mow.app not found at $APP_PATH"
  echo "Usage: $0 [path-to-Mow.app]"
  exit 1
fi

# Generate dev entitlements (sandbox off, library validation off).
DEV_ENTITLEMENTS=$(mktemp /tmp/mow-dev-entitlements.XXXXXX.plist)
trap 'rm -f "$DEV_ENTITLEMENTS"' EXIT

cat > "$DEV_ENTITLEMENTS" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.device.audio-input</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
</dict>
</plist>
EOF

echo "Ad-hoc signing nested frameworks..."
# 1) Binaries inside .framework (e.g. llama.framework/Versions/A/llama)
find "$APP_PATH/Contents/Frameworks" -type d -name "*.framework" 2>/dev/null | while read -r fw; do
  for bin in "$fw/Versions/A/"*; do
    [ -f "$bin" ] && file -b "$bin" | grep -q Mach-O && \
      codesign --force --sign "-" "$bin"
  done
  codesign --force --sign "-" "$fw"
done
# 2) Any .dylib in Frameworks
find "$APP_PATH/Contents/Frameworks" -name "*.dylib" -type f 2>/dev/null | while read -r dylib; do
  codesign --force --sign "-" "$dylib"
done

echo "Ad-hoc signing main app with dev entitlements..."
codesign --force --sign "-" --entitlements "$DEV_ENTITLEMENTS" "$APP_PATH"

echo "Done. $APP_PATH is ad-hoc signed for local development."
echo ""
echo "Note: You may need to (re-)grant Microphone and Accessibility permissions"
echo "after signing. See docs/guides/DEVELOPER_GUIDE.md for details."
