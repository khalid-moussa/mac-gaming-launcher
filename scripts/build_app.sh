#!/bin/bash
# Builds build/MacGamingLauncher.app (release, arm64) and signs it ad hoc.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="MacGamingLauncher"
VERSION="2.0.0"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

echo "==> swift build (release, arm64)"
swift build -c release --arch arm64
BIN_PATH="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"

echo "==> Bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_PATH" "$CONTENTS/MacOS/$APP_NAME"
[ -f "$PROJECT_DIR/AppIcon.icns" ] && cp "$PROJECT_DIR/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.khalid.MacGamingLauncher</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>Mac Gaming Launcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleDevelopmentRegion</key><string>de</string>
    <key>LSMinimumSystemVersion</key><string>27.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>LSSupportsGameMode</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

echo "==> Codesign (ad hoc)"
codesign --force --sign - --timestamp=none "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"

echo "==> Fertig: $APP_BUNDLE"
echo "    open \"$APP_BUNDLE\""
