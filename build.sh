#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h}"
APP_DIR="$ROOT_DIR/output/Soomfon Raccourcis.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" /private/tmp/soomfon-swift-cache
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 -O \
  -module-cache-path /private/tmp/soomfon-swift-cache \
  "$ROOT_DIR"/Sources/*.swift \
  -framework AppKit -framework SwiftUI -framework IOKit -framework Carbon -framework ApplicationServices \
  -o "$APP_DIR/Contents/MacOS/SoomfonRaccourcis"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Soomfon Raccourcis</string>
<key>CFBundleDisplayName</key><string>Soomfon Raccourcis</string>
<key>CFBundleExecutable</key><string>SoomfonRaccourcis</string>
<key>CFBundleIdentifier</key><string>fr.local.soomfon-raccourcis</string>
<key>CFBundleVersion</key><string>18</string>
<key>CFBundleShortVersionString</key><string>0.9.6</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSInputMonitoringUsageDescription</key><string>Recevoir les appuis des boutons du boîtier Soomfon.</string>
</dict></plist>
PLIST
codesign --force --sign - --identifier fr.local.soomfon-raccourcis "$APP_DIR"
if [[ "${1:-}" != "--compile-only" ]]; then
  "$APP_DIR/Contents/MacOS/SoomfonRaccourcis" --self-test
fi
print "Application prête : $APP_DIR"
