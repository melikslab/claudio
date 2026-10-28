#!/bin/zsh
# Compila y empaqueta Claudio.app (sin Xcode, solo con las Command Line Tools).
#   ./build-app.sh           Apple Silicon (build/Claudio.app)
#   ./build-app.sh --intel   Intel, como app aparte (build/intel/Claudio.app)
#   VERSION=1.2.3 ./build-app.sh   versión que aparece en la app
set -e
cd "$(dirname "$0")"
VERSION=${VERSION:-0.2.1}

if [[ "$1" == "--intel" ]]; then
    ARCH=x86_64
    OUT=build/intel
else
    ARCH=arm64
    OUT=build
fi
swift build -c release --triple $ARCH-apple-macosx14.0
BINARY=.build/$ARCH-apple-macosx/release/Claudio

APP=$OUT/Claudio.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Claudio"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/PetSprites.png "$APP/Contents/Resources/PetSprites.png"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Claudio</string>
    <key>CFBundleIdentifier</key><string>com.melikslab.claudio</string>
    <key>CFBundleExecutable</key><string>Claudio</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Listo: $(pwd)/$APP ($(lipo -archs "$APP/Contents/MacOS/Claudio"), versión $VERSION)"
