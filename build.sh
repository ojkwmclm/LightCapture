#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
APP="轻截 LightCapture.app"
BUILD_CACHE="${TMPDIR:-/tmp}/lightcapture-module-cache"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_CACHE"
xcrun swiftc Source/Localization.swift Source/EditorUI.swift Source/Canvas.swift Source/RecordingSetup.swift Source/Recorder.swift Source/main.swift -o "$APP/Contents/MacOS/LightCapture" -module-cache-path "$BUILD_CACHE" -target arm64-apple-macos15.0 -framework AppKit -framework Vision -framework ScreenCaptureKit -framework AVFoundation -framework Carbon
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LightCapture</string>
<key>CFBundleIdentifier</key><string>local.lightcapture.app</string>
<key>CFBundleName</key><string>轻截 LightCapture</string>
<key>CFBundleDisplayName</key><string>轻截 LightCapture</string>
<key>CFBundleIconFile</key><string>LightCapture.icns</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.21</string>
<key>CFBundleVersion</key><string>40</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>仅在你选择麦克风录屏时采集麦克风声音，并保存在本机录屏文件中。</string>
<key>NSScreenCaptureUsageDescription</key><string>用于你主动发起的截图和录屏。</string>
</dict></plist>
PLIST
cp -R Assets/en.lproj Assets/zh-Hans.lproj "$APP/Contents/Resources/"
cp Assets/LightCapture.icns "$APP/Contents/Resources/LightCapture.icns"
codesign --force --sign - "$APP"
echo "已构建：$PWD/$APP"
