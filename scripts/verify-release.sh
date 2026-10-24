#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
VERSION="$(<VERSION)"
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-battery-verify.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
(cd dist && shasum -a 256 -c SHA256SUMS)
ditto -x -k "dist/CodexBattery-$VERSION-universal.zip" "$CHECK_DIR"
APP="$CHECK_DIR/Codex Battery.app"
BIN="$APP/Contents/MacOS/CodexBattery"
codesign --verify --strict "$APP"
xcrun lipo "$BIN" -verify_arch arm64 x86_64
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist")" == "13.0" ]]
for LANG in en zh-Hans ja; do
  "$BIN" -AppleLanguages "($LANG)" --self-test
done
print "PASS: clean extraction, SHA-256, signature, both architectures, version and 3 languages"
