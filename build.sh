#!/bin/zsh
# Runs the tests, then builds Swoosh.app into ./build.
# Usage: ./build.sh [--skip-tests] [--install] [--run]
set -euo pipefail
cd "$(dirname "$0")"
run_tests() {
  # The Command Line Tools' macro plugin server occasionally fails to load
  # swift-testing's macros when many files compile in parallel. Retry only that
  # specific toolchain error; genuine test failures still stop the build.
  local log=$(mktemp)
  for attempt in 1 2 3; do
    if swift test --scratch-path .build/tests 2>&1 | tee "$log" | grep -E '✔ Test run|✘|error:'; then :; fi
    if grep -q '✔ Test run with' "$log"; then rm -f "$log"; return 0; fi
    grep -q "plugin for module 'TestingMacros' not found" "$log" || { rm -f "$log"; return 1; }
    echo "Retrying tests (toolchain macro plugin hiccup, attempt $attempt)…"
  done
  rm -f "$log"; return 1
}
if [[ " $* " != *" --skip-tests "* ]]; then run_tests; fi
[[ -f Resources/AppIcon.icns ]] || swift Scripts/make-icon.swift Resources/AppIcon.icns
swift build -c release
APP=build/Swoosh.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Swoosh "$APP/Contents/MacOS/Swoosh"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sign with a stable identity when one exists, so macOS keeps the Accessibility
# permission across rebuilds. Falls back to ad-hoc signing (re-grant each build).
IDENTITY="${SWOOSH_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --deep --timestamp=none --sign "${IDENTITY:--}" "$APP"
echo "Signed with: ${IDENTITY:-ad-hoc}"
echo "Built $APP"
if [[ " $* " == *" --install "* ]]; then
  pkill -x Swoosh 2>/dev/null || true
  rm -rf /Applications/Swoosh.app && cp -R "$APP" /Applications/
  APP=/Applications/Swoosh.app
  echo "Installed to $APP"
fi
if [[ " $* " == *" --run "* ]]; then open "$APP"; fi
