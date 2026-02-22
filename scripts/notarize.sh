#!/bin/bash
# Notarize Mow.app for distribution (task 14.2).
# Submit the app to Apple, wait for approval, then staple the notarization ticket.
#
# Prerequisites:
#   1. App must be signed with "Developer ID Application" (Release build or archive).
#   2. Create an App-Specific Password: https://appleid.apple.com → Sign-In and Security
#      → App-Specific Passwords → Generate. Use this for NOTARYTOOL; never use your main Apple ID password.
#   3. Set environment variables (or pass as arguments):
#        APPLE_ID          – Your Apple ID email
#        APPLE_APP_SPECIFIC_PASSWORD – The app-specific password from step 2
#        TEAM_ID           – Your 10-character team ID (e.g. from developer.apple.com/account → Membership)
#        CODESIGN_IDENTITY – (optional) If set, re-signs the app with Developer ID + timestamp before submitting.
#                           Use when the app was built with ad-hoc signing (e.g. "Developer ID Application: Name (TEAM_ID)").
#
# Usage:
#   ./scripts/notarize.sh [path-to-Mow.app]
#   If path is omitted, uses the Release app from DerivedData.
#
# Example (env vars set):
#   export APPLE_ID="you@example.com"
#   export APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   export TEAM_ID="XXXXXXXXXX"
#   ./scripts/notarize.sh
#
# Or with a built app:
#   ./scripts/notarize.sh /path/to/Mow.app

set -e

APP_PATH="$1"
APP_NAME="Mow.app"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"

if [ -z "$APP_PATH" ]; then
  APP_PATH=$(find "$DERIVED" -name "$APP_NAME" -path "*/Build/Products/Release/*" 2>/dev/null | grep -v Index.noindex | head -1)
  if [ -z "$APP_PATH" ]; then
    echo "Error: $APP_NAME not found. Build for Release in Xcode (Product → Scheme → Edit Scheme → Run → Build Configuration: Release, then Archive or Build), or pass the path: $0 /path/to/Mow.app"
    exit 1
  fi
  echo "Using Release app: $APP_PATH"
fi

if [ ! -d "$APP_PATH" ]; then
  echo "Error: Not a directory: $APP_PATH"
  exit 1
fi

if [ "$(basename "$APP_PATH")" != "$APP_NAME" ]; then
  echo "Error: Expected path to $APP_NAME, got: $APP_PATH"
  exit 1
fi

if [ -z "$APPLE_ID" ] || [ -z "$APPLE_APP_SPECIFIC_PASSWORD" ]; then
  echo "Error: Set APPLE_ID and APPLE_APP_SPECIFIC_PASSWORD (and optionally TEAM_ID). See script header."
  exit 1
fi

# If CODESIGN_IDENTITY is set, re-sign the app with Developer ID + secure timestamp first.
# Use this when the app was built with ad-hoc signing (e.g. mise build without a Developer ID cert).
if [ -n "$CODESIGN_IDENTITY" ]; then
  echo "Re-signing with Developer ID + timestamp (CODESIGN_IDENTITY is set)..."
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  "$SCRIPT_DIR/sign-for-notarization.sh" "$APP_PATH"
fi

# App must be signed with "Developer ID Application" and secure timestamp for notarization.
# Create zip for submission (Apple requires zip for .app)
ZIP_PATH="${TMPDIR:-/tmp}/mow-notarize-$(date +%s).zip"
echo "Creating zip for submission..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Submit and wait
echo "Submitting to Apple for notarization..."
SUBMIT_OUT=$(mktemp)
trap 'rm -f "$SUBMIT_OUT"' EXIT

if [ -n "$TEAM_ID" ]; then
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait 2>&1 | tee "$SUBMIT_OUT"
else
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait 2>&1 | tee "$SUBMIT_OUT"
fi

# Parse submission ID and status from output
SUB_ID=$(grep -E '^\s*id:' "$SUBMIT_OUT" | tail -1 | sed 's/.*id:[[:space:]]*//')
STATUS=$(grep -E '^\s*status:' "$SUBMIT_OUT" | tail -1 | sed 's/.*status:[[:space:]]*//')

if [ "$STATUS" != "Accepted" ]; then
  echo ""
  echo "Notarization was rejected (status: ${STATUS:-unknown}). Apple's log:"
  echo "---"
  if [ -n "$SUB_ID" ]; then
    if [ -n "$TEAM_ID" ]; then
      xcrun notarytool log "$SUB_ID" --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID" 2>&1 || true
    else
      xcrun notarytool log "$SUB_ID" --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" 2>&1 || true
    fi
  else
    echo "Could not get submission ID; check output above."
  fi
  echo "---"
  echo "Fix the issues above (often: sign with Developer ID Application, enable Hardened Runtime), then re-run."
  exit 1
fi

# Staple the notarization ticket to the app
echo "Stapling notarization ticket to app..."
xcrun stapler staple "$APP_PATH"

# Cleanup
rm -f "$ZIP_PATH"

echo "Done. $APP_PATH is notarized and ready for distribution (e.g. in a DMG)."
