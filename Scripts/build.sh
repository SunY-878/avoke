#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
CONFIGURATION="${CONFIGURATION:-release}"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP="$TASK_ROOT/dist/Sky Island.app"
RES="$APP/Contents/Resources"
VENDOR="$TASK_ROOT/Vendor/MediaRemoteAdapter"
FRAMEWORK="$RES/MediaRemoteAdapter.framework"
mkdir -p "$APP/Contents/MacOS" "$RES" "$FRAMEWORK/Versions/A/Resources"
cp "$BIN_DIR/SkyIsland" "$APP/Contents/MacOS/SkyIsland"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$VENDOR/bin/mediaremote-adapter.pl" "$RES/"
cp "$VENDOR/LICENSE" "$RES/MediaRemoteAdapter-LICENSE.txt"
cp THIRD_PARTY_NOTICES.md "$RES/"
echo "Building native media adapter…"
xcrun clang -dynamiclib -fobjc-arc -fmodules -fvisibility=default -mmacosx-version-min=14.0 \
    -I "$VENDOR/include" -I "$VENDOR/src" \
    "$VENDOR"/src/adapter/*.m "$VENDOR"/src/private/*.m "$VENDOR"/src/utility/*.m \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name '@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter' \
    -o "$FRAMEWORK/Versions/A/MediaRemoteAdapter"
cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleVersion</key><string>0.1.0</string>
</dict></plist>
PLIST
ln -sfn A "$FRAMEWORK/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$FRAMEWORK/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$FRAMEWORK/Resources"
if [ ! -f "$RES/AppIcon.icns" ] || [ Scripts/make-icon.swift -nt "$RES/AppIcon.icns" ]; then
    swift Scripts/make-icon.swift "$TASK_ROOT/.build/AppIcon.iconset"
    iconutil -c icns "$TASK_ROOT/.build/AppIcon.iconset" -o "$RES/AppIcon.icns"
fi
codesign --force --sign - "$FRAMEWORK"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "Ready: $APP"
