#!/bin/zsh
# Compila y empaqueta Claudio.app (sin Xcode, solo con las Command Line Tools).
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Claudio.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Claudio "$APP/Contents/MacOS/Claudio"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Claudio</string>
    <key>CFBundleIdentifier</key><string>com.melikslab.claudio</string>
    <key>CFBundleExecutable</key><string>Claudio</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Listo: $(pwd)/$APP"
