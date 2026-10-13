#!/bin/zsh
# One command for the programmatic part of the eval: logic tests + NL-capture scores + app build.
# Usage (from anywhere): ios/Eval/run-eval.sh
set -e
cd "$(dirname "$0")/.."
echo "== Logic tests and NL-capture eval"
swift test 2>&1 | grep -E "CAPTURE|Executed .* tests|error:|failed" | sort -u
echo "== App build (iOS Simulator)"
xcodebuild -project One.xcodeproj -scheme One -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | grep -E "\.swift:[0-9]+:[0-9]+: (warning|error)|\*\* BUILD" | sort -u
