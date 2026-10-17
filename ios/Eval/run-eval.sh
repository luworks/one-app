#!/bin/zsh
# One command for the programmatic part of the eval.
# Usage: ios/Eval/run-eval.sh            logic tests + NL-capture scores + app build
#        ios/Eval/run-eval.sh --ui       also run the UI journeys (J1–J7) on a simulator
set -eo pipefail
cd "$(dirname "$0")/.."
echo "== Logic tests and NL-capture eval"
swift test 2>&1 | grep -E "CAPTURE|Executed .* tests|error:|failed" | sort -u
echo "== App build (iOS Simulator)"
xcodebuild -project One.xcodeproj -scheme One -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/xcode CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | grep -E "\.swift:[0-9]+:[0-9]+: (warning|error)|\*\* BUILD" | sort -u
if [[ "${1:-}" == "--ui" ]]; then
  echo "== UI journeys"
  SIM=$(xcrun simctl list devices available | grep -m1 -E "iPhone .*\(" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  xcodebuild test -project One.xcodeproj -scheme One -destination "id=$SIM" -derivedDataPath .build/xcode-test 2>&1 \
    | grep -E "Test Case .*(passed|failed|skipped)|COLD START|error:|\*\* TEST" | sort -u
  echo "== Cold start"
  Eval/cold-start.sh .build/xcode-test/Build/Products/Debug-iphonesimulator/One.app
fi
