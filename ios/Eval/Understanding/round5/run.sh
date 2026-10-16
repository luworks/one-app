#!/bin/zsh
# Round 5 edit eval. Usage: ios/Eval/Understanding/round5/run.sh <edit-cases.json> <out.json> [trials]
set -e
cd "$(dirname "$0")/../../.."
OUT=$(mktemp -d)
swiftc -O One/Capture.swift One/Logic.swift One/Editing.swift Eval/Understanding/round5/main.swift -o "$OUT/round5" 2>&1 | grep -E "error" || true
"$OUT/round5" "$1" "$2" "${3:-5}"
