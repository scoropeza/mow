#!/bin/bash
# Patch LLM.swift HuggingFaceModel.getDownloadURLStrings() regex:
# The greedy `.*` in the download URL pattern matches across HTML attributes on
# minified Hugging Face pages, producing garbage URLs (e.g. the generic /models
# page instead of the .gguf download link). Fix: use `[^"]*` to stay within
# a single href="…" attribute value.
#
# Run after resolving packages and before building, or integrate as a build phase.
# In CI, set DERIVED to your -derivedDataPath (e.g. build).
# (No set -e: grep returns 1 when already patched, which would fail a build phase.)

DERIVED="${DERIVED:-build}"
FILE=""

# Search under the derivedDataPath used by mise / CI
f="$DERIVED/SourcePackages/checkouts/LLM.swift/Sources/LLM/LLM.swift"
[ -f "$f" ] && FILE="$f"

# Fallback: Xcode default DerivedData
if [ -z "$FILE" ]; then
  for dir in "${HOME}/Library/Developer/Xcode/DerivedData"/mow-*; do
    [ -d "$dir" ] || continue
    f="$dir/SourcePackages/checkouts/LLM.swift/Sources/LLM/LLM.swift"
    [ -f "$f" ] && FILE="$f" && break
  done
fi

if [ -z "$FILE" ]; then
  echo "patch-llm-swift: LLM.swift checkout not found under $DERIVED. Resolve packages first."
  exit 0
fi

# The buggy line (Swift raw string literal):
#   let downloadURLPattern = #"(?<=href=").*\.gguf\?download=true"#
# Fix: replace .* with [^"]* so the match stays within a single href attribute.
if grep -qF '(?<=href=").*\.gguf' "$FILE" 2>/dev/null; then
  sed -i.bak 's/(?<=href=").\.\\\.gguf/(?<=href=")[^"]*\\.gguf/g' "$FILE"
  # If the above sed didn't work (escaping varies), try a more literal approach
  if grep -qF '(?<=href=").*\.gguf' "$FILE" 2>/dev/null; then
    # Use perl for reliable literal replacement
    perl -i.bak -pe 's/\Q(?<=href=").*\.gguf\E/(?<=href=")[^"]*\\.gguf/g' "$FILE"
  fi
  rm -f "${FILE}.bak"
  echo "Patched LLM.swift: fixed greedy regex in getDownloadURLStrings()."
else
  echo "patch-llm-swift: already patched or pattern not found."
fi
exit 0
