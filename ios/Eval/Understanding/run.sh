#!/bin/zsh
# On-device model eval (spike). Needs Apple Intelligence on this Mac; the simulator borrows the host's model.
# Usage: ios/Eval/Understanding/run.sh [--sim] [trials] [variants: raw,table,A,A2,B]
#        CASES=Eval/Understanding/understanding-cases-r3.json ios/Eval/Understanding/run.sh 3 raw,A2
set -e
cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
SRC=(One/Capture.swift One/Logic.swift One/Understanding.swift Eval/Understanding/main.swift)
CASES_FILE="${CASES:-$PWD/Eval/Understanding/understanding-cases.json}"
if [[ "$1" == "--sim" ]]; then
  shift
  SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
  swiftc -O -sdk "$SDK" -target arm64-apple-ios27.0-simulator "${SRC[@]}" -o "$OUT/eval" 2>&1 | grep -E "error" || true
  xcrun simctl spawn booted "$OUT/eval" "$CASES_FILE" "${1:-2}" "${2:-raw,table,A,A2,B}"
else
  swiftc -O "${SRC[@]}" -o "$OUT/eval" 2>&1 | grep -E "error" || true
  "$OUT/eval" "$CASES_FILE" "${1:-2}" "${2:-raw,table,A,A2,B}"
fi
