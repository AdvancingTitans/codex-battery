#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
VERSION="$(<VERSION)"
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 "Invalid VERSION"; exit 1; }
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-battery.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP="$BUILD_DIR/Codex Battery.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist
for ARCH in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" -framework AppKit -framework ServiceManagement CodexBattery.swift -o "$BUILD_DIR/CodexBattery-$ARCH"
done
xcrun lipo -create "$BUILD_DIR/CodexBattery-arm64" "$BUILD_DIR/CodexBattery-x86_64" -output "$APP/Contents/MacOS/CodexBattery"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexBattery</string>
<key>CFBundleIdentifier</key><string>io.github.advancingtitans.codexbattery</string>
<key>CFBundleName</key><string>Codex Battery</string>
<key>CFBundleDisplayName</key><string>Codex Battery</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string><string>ja</string></array>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 AdvancingTitans. MIT License.</string>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
for LANG in en zh-Hans ja; do
  "$APP/Contents/MacOS/CodexBattery" -AppleLanguages "($LANG)" --self-test
done
ARCHIVE="CodexBattery-$VERSION-universal.zip"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > SHA256SUMS)
print "Built dist/$ARCHIVE"
