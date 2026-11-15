#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="MacGamingLauncher"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Building $APP_NAME for macOS (arm64)..."
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
swift build -c release --arch arm64

echo "==> Creating .app bundle structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
BIN_PATH="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

# Copy AppIcon if available
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Create Info.plist
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacGamingLauncher</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.khalid.MacGamingLauncher</string>
    <key>CFBundleName</key>
    <string>MacGamingLauncher</string>
    <key>CFBundleDisplayName</key>
    <string>Mac Gaming Launcher</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

echo "==> Successfully created $APP_BUNDLE"
echo "You can open it with: open \"$APP_BUNDLE\""
