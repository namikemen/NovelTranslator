#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "Building NovelTranslator..."
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/NovelTranslator"
APP_DIR="$DIR/NovelTranslator.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

if [ -f "$DIR/scripts/vieneu_tts_bridge.py" ]; then
    cp "$DIR/scripts/vieneu_tts_bridge.py" "$RESOURCES_DIR/"
    chmod +x "$RESOURCES_DIR/vieneu_tts_bridge.py"
fi

cp "$BIN_PATH" "$MACOS_DIR/NovelTranslator"
chmod +x "$MACOS_DIR/NovelTranslator"

APP_VERSION="${APP_VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

cat << EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NovelTranslator</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.NovelTranslator</string>
    <key>CFBundleName</key>
    <string>NovelTranslator</string>
    <key>CFBundleDisplayName</key>
    <string>Novel Translator</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

codesign -s - --force --deep "$APP_DIR"

echo "NovelTranslator.app created successfully at $APP_DIR"
