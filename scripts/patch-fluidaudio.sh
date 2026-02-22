#!/bin/bash
# Patch FluidAudio Qwen3AsrModels.swift for Swift 6 / strict type inference:
# 1) Closure parameter: "ptr in" -> "(ptr: UnsafeRawBufferPointer) in"
# 2) f16Ptr: add explicit "UnsafePointer<Float16>" type
# Run before building/archiving, or use the PatchFluidAudio aggregate target in Xcode.
# (No set -e: grep returns 1 when already patched, which would fail the Xcode build phase.)
# In CI, set DERIVED to your -derivedDataPath (e.g. build) so the script finds the checkout.
DERIVED="${DERIVED:-${HOME}/Library/Developer/Xcode/DerivedData}"
FILE=""
for dir in "$DERIVED"/mow-*; do
  [ -d "$dir" ] || continue
  f="$dir/SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/ASR/Qwen3/Qwen3AsrModels.swift"
  if [ -f "$f" ]; then
    FILE="$f"
    break
  fi
done
if [ -z "$FILE" ]; then
  echo "patch-fluidaudio: FluidAudio checkout not found under $DERIVED/mow-*. Resolve packages in Xcode first."
  exit 0
fi
PATCHED=0
# Fix 1: closure parameter type (resolves "Type of expression is ambiguous" at withUnsafeBytes)
if grep -q 'data.withUnsafeBytes { ptr in' "$FILE" 2>/dev/null; then
  sed -i.bak 's/data\.withUnsafeBytes { ptr in/data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in/g' "$FILE"
  rm -f "${FILE}.bak"
  PATCHED=1
fi
# Fix 2: f16Ptr explicit type (in case it was reverted or different version)
if ! grep -q 'let f16Ptr: UnsafePointer<Float16>' "$FILE" 2>/dev/null; then
  sed -i.bak 's/let f16Ptr = ptr\.baseAddress!/let f16Ptr: UnsafePointer<Float16> = ptr.baseAddress!/g' "$FILE"
  rm -f "${FILE}.bak"
  PATCHED=1
fi
# Fix 3: Float16 -> Float without triggering "No exact matches" (Swift 6): go through String(describing:)
REPL='result[i] = Float(String(describing: f16Ptr[i])) ?? 0'
# 3a: original
if grep -q 'result\[i\] = Float(f16Ptr\[i\])' "$FILE" 2>/dev/null; then
  sed -i.bak "s/^\([[:space:]]*\)result\[i\] = Float(f16Ptr\[i\])/\1$REPL/" "$FILE"
  rm -f "${FILE}.bak"
  PATCHED=1
fi
# 3b: (f16Ptr[i] as Double) as Float
if grep -q '(f16Ptr\[i\] as Double) as Float' "$FILE" 2>/dev/null; then
  sed -i.bak "s/^\([[:space:]]*\)result\[i\] = (f16Ptr\[i\] as Double) as Float/\1$REPL/" "$FILE"
  rm -f "${FILE}.bak"
  PATCHED=1
fi
# 3c: Float(Double(f16Ptr[i]))
if grep -q 'result\[i\] = Float(Double(f16Ptr\[i\]))' "$FILE" 2>/dev/null; then
  sed -i.bak "s/^\([[:space:]]*\)result\[i\] = Float(Double(f16Ptr\[i\]))/\1$REPL/" "$FILE"
  rm -f "${FILE}.bak"
  PATCHED=1
fi
# 3d: let value: Float16 = ...; result[i] = Float(value)
if grep -q 'let value: Float16 = f16Ptr\[i\]; result\[i\] = Float(value)' "$FILE" 2>/dev/null; then
  sed -i.bak "s/^\([[:space:]]*\)let value: Float16 = f16Ptr\[i\]; result\[i\] = Float(value)/\1$REPL/" "$FILE"
  rm -f "${FILE}.bak"
  PATCHED=1
fi
# 3e: NSNumber(value: f16Ptr[i]).floatValue (no exact match for NSNumber(value: Float16))
if grep -q 'NSNumber(value: f16Ptr\[i\])' "$FILE" 2>/dev/null; then
  sed -i.bak "s/^\([[:space:]]*\)result\[i\] = NSNumber(value: f16Ptr\[i\]).floatValue/\1$REPL/" "$FILE"
  rm -f "${FILE}.bak"
  PATCHED=1
fi
# Fix 4: Float16 is unavailable on macOS (package deployment target); use UInt16 + manual half-to-float
if grep -q 'let f16Ptr: UnsafePointer<Float16>' "$FILE" 2>/dev/null; then
  # 4a: replace Float16 with UInt16 and f16Ptr with u16Ptr; merge the two declaration lines into one
  sed -i.bak 's/\.assumingMemoryBound(to: Float16\.self)/.assumingMemoryBound(to: UInt16.self)/g' "$FILE"
  sed -i.bak 's/let f16Ptr: UnsafePointer<Float16> = ptr\.baseAddress!\.advanced(by: offset)/let u16Ptr = ptr.baseAddress!.advanced(by: offset).assumingMemoryBound(to: UInt16.self)/g' "$FILE"
  # Remove the now-orphaned line that only had ".assumingMemoryBound(to: UInt16.self)"
  sed -i.bak '/^[[:space:]]*\.assumingMemoryBound(to: UInt16\.self)[[:space:]]*$/d' "$FILE"
  # 4b: replace result[i] = ... with _halfToFloat(u16Ptr[i])
  sed -i.bak 's/result\[i\] = Float(String(describing: f16Ptr\[i\]) ?? 0/result[i] = _halfToFloat(u16Ptr[i])/g' "$FILE"
  sed -i.bak 's/result\[i\] = Float(String(describing: u16Ptr\[i\]) ?? 0/result[i] = _halfToFloat(u16Ptr[i])/g' "$FILE"
  # 4c: insert _halfToFloat helper after "let u16Ptr = ..."
  if ! grep -q '_halfToFloat' "$FILE" 2>/dev/null; then
    sed -i.bak '/let u16Ptr = ptr\.baseAddress!\.advanced(by: offset)\.assumingMemoryBound(to: UInt16\.self)/a\
\
            func _halfToFloat(_ b: UInt16) -> Float {\
                let s = Int((b >> 15) & 1)\
                let e = Int((b >> 10) & 0x1F)\
                let m = Int(b & 0x3FF)\
                if e == 0 { return Float(s == 0 ? 1 : -1) * (Float(m) / 1024.0) * Float(pow(2.0, -14.0)) }\
                if e == 31 { return m == 0 ? (s == 0 ? Float.infinity : -Float.infinity) : Float.nan }\
                return Float(bitPattern: UInt32((s << 31) | ((e - 15 + 127) << 23) | (m << 13)))\
            }
' "$FILE" 2>/dev/null
  fi
  # 4d: replace any remaining f16Ptr with u16Ptr (e.g. missed by 4b or different formatting)
  if grep -q 'f16Ptr' "$FILE" 2>/dev/null; then
    sed -i.bak 's/f16Ptr/u16Ptr/g' "$FILE"
    PATCHED=1
  fi
  rm -f "${FILE}.bak"
  PATCHED=1
fi
# Fix 5: if file still has any f16Ptr (e.g. Fix 4 already ran before so 4d was skipped), replace them now
if grep -q 'f16Ptr' "$FILE" 2>/dev/null; then
  sed -i.bak 's/f16Ptr/u16Ptr/g' "$FILE"
  rm -f "${FILE}.bak"
  PATCHED=1
fi
[ "$PATCHED" = 1 ] && echo "Patched FluidAudio Qwen3AsrModels.swift (type annotations)."
exit 0
