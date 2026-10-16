#!/bin/zsh
# Round 4: Apple FM on shared capture/edit case files, writes JSON per-case outputs.
# Usage: ios/Eval/Understanding/round4/run.sh <understanding-dir> <out-dir> [trials]
set -e
cd "$(dirname "$0")/../../.."
OUT=$(mktemp -d)
# Understanding.swift / Capture.swift / Logic.swift only; the harness has its own main.
swiftc -O One/Capture.swift One/Logic.swift One/Understanding.swift Eval/Understanding/round4/main.swift -o "$OUT/round4" 2>&1 | grep -E "error" || true
"$OUT/round4" "$1" "$2" "${3:-5}" "$PWD"
