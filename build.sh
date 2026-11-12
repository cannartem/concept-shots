#!/bin/bash
# Builds ConceptShots.app: double-click opens the dialog, Contents/MacOS/shots is also the command-line tool for MCP.
set -e
cd "$(dirname "$0")"
APP="ConceptShots.app"
rm -rf "$APP" shots
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O Shots.swift -o "$APP/Contents/MacOS/shots"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>ConceptShots</string>
<key>CFBundleIdentifier</key><string>local.conceptshots</string>
<key>CFBundleExecutable</key><string>shots</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>ConceptShots</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
EOF
# icon: draw 1024 px, resize to all sizes, pack into .icns
TMP=$(mktemp -d)
swiftc -O make-icon.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/icon.png"
mkdir "$TMP/ConceptShots.iconset"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$TMP/icon.png" --out "$TMP/ConceptShots.iconset/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$TMP/icon.png" --out "$TMP/ConceptShots.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/ConceptShots.iconset" -o "$APP/Contents/Resources/ConceptShots.icns"
rm -rf "$TMP"
codesign --force --sign - "$APP"
echo "Built: $PWD/$APP"
