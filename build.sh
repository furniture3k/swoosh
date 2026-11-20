#!/bin/zsh
# Builds Swoosh.app into ./build. Usage: ./build.sh [--install] [--run]
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/Swoosh.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Swoosh "$APP/Contents/MacOS/Swoosh"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Use a stable signing identity if you have one (keeps the Accessibility grant
# across rebuilds); otherwise ad-hoc sign.
codesign --force --deep --sign "${SWOOSH_SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
if [[ " $* " == *" --install "* ]]; then
  pkill -x Swoosh 2>/dev/null || true
  rm -rf /Applications/Swoosh.app && cp -R "$APP" /Applications/
  APP=/Applications/Swoosh.app
  echo "Installed to $APP"
fi
if [[ " $* " == *" --run "* ]]; then open "$APP"; fi
