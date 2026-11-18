#!/bin/bash
# Runs every test: the engine tests, the app workflow tests, then the app's own self-test.
#   ./scripts/test.sh
# With Xcode this is plain `swift test`. A Mac with only the Command Line Tools does not find Swift Testing
# by itself, so this script names the folder of Testing.framework.
set -euo pipefail
cd "$(dirname "$0")/.."
CLT="/Library/Developer/CommandLineTools"
FW="$CLT/Library/Developer/Frameworks"
FLAGS=()
if [[ "$(xcode-select -p 2>/dev/null)" == "$CLT"* && -d "$FW/Testing.framework" ]]; then
  FLAGS=(-Xswiftc "-F$FW" -Xlinker "-F$FW" -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$CLT/Library/Developer/usr/lib")
fi
swift test ${FLAGS[@]+"${FLAGS[@]}"}
if [[ "${1:-}" == "--selftest" ]]; then      # opens the app window for a few seconds
  swift build --product DupeSweep
  "$(swift build --show-bin-path)/DupeSweep" --selftest
fi
