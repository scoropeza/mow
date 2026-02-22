#!/bin/bash
# Reset TCC (privacy) permissions for Mów so the system will prompt again on next launch.
# Use when switching builds (e.g. Xcode vs Applications) or when the app shows "denied"
# but System Settings shows the app as allowed (different build = different TCC client).
#
# Usage:
#   ./scripts/reset-permissions.sh
#   Or: mise run reset-permissions
#
# Steps: Quit Mów first, run this script, then launch the app you want and click Allow when prompted.
#
# If Microphone reset fails: ensure Terminal has Full Disk Access and try again from a new
# Terminal window. On some macOS versions Apple blocks Microphone reset; then the only
# workaround is to reinstall the app (remove Mow.app, install fresh, grant when prompted).

set -e

BUNDLE_ID="com.daedalus-labs.mow"

echo "Resetting TCC permissions for $BUNDLE_ID ..."
echo ""

reset_one() {
  local service="$1"
  local err
  err=$(tccutil reset "$service" "$BUNDLE_ID" 2>&1) || true
  if [ -z "$err" ]; then
    echo "  $service: reset"
    return 0
  else
    echo "  $service: failed — $err"
    if [ "$service" = "Microphone" ]; then
      echo ""
      echo "  → If Terminal has Full Disk Access and you still see this, macOS may block Microphone"
      echo "    reset on this version. Use the reinstall workaround below."
    fi
    return 1
  fi
}

mic_ok=0
echo "  Running: tccutil reset Microphone $BUNDLE_ID"
reset_one "Microphone" || mic_ok=1
echo "  Running: tccutil reset Accessibility $BUNDLE_ID"
reset_one "Accessibility" || true

echo ""
if [ $mic_ok -ne 0 ]; then
  echo "Microphone was not reset. Workaround when tccutil is blocked by macOS:"
  echo ""
  echo "  1. Quit Mów (menu bar → Quit Mów)."
  echo "  2. Move Mow.app to Trash (e.g. from Applications)."
  echo "  3. Empty Trash."
  echo "  4. Install again (drag from DMG or run the build) and open Mów."
  echo "  5. When the system \"Allow\" dialog appears, click Allow for Microphone."
  echo ""
  echo "  A fresh install gets a new TCC entry and will prompt again."
  echo ""
fi
echo "Next: launch Mów (the build you want to use) and grant Microphone (and Accessibility in System Settings) when prompted."
