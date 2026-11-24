#!/bin/zsh
# Builds FlashCardsQA.app into mac/dist/. Pass --install to copy it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/FlashCardsQA"

APP="dist/FlashCardsQA.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FlashCardsQA"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Ad-hoc signature: runs on this Mac without an Apple Developer account.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/FlashCardsQA.app"
  cp -R "$APP" /Applications/
  echo "Installed /Applications/FlashCardsQA.app"
fi
