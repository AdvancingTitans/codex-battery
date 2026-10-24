#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-battery.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP="$BUILD_DIR/Codex Battery.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -O -swift-version 5 -framework AppKit -framework ServiceManagement CodexBattery.swift -o "$APP/Contents/MacOS/CodexBattery"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexBattery</string>
<key>CFBundleIdentifier</key><string>local.yjw.codexbattery</string>
<key>CFBundleName</key><string>Codex Battery</string>
<key>CFBundleDisplayName</key><string>Codex Battery</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.1</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/CodexBattery" --self-test

ditto -c -k --norsrc --noextattr --keepParent "$APP" "$PWD/Codex Battery.zip"
