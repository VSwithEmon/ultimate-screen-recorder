#!/bin/bash
# Builds ScreenRec.app (release) from the SwiftPM package and ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.2.1}"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/ScreenRecApp"
NAME="Ultimate Screen Recording"
APP="build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>local.ultimatescreenrecording.app</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key><string>Ultimate Screen Recording records your microphone as a separate audio track in your local project.</string>
  <key>NSCameraUseContinuityCameraDeviceType</key><true/>
  <key>NSCameraUsageDescription</key><string>Ultimate Screen Recording records your camera as a separate track in your local project.</string>
</dict></plist>
PLIST
# Ad-hoc signing. NOTE: every rebuild changes the code hash, so macOS may ask you to re-grant Screen Recording.
# For a stable identity, create a local "Code Signing" certificate in Keychain Access and set SIGN_ID to its name.
xattr -cr "$APP"   # strip Finder metadata/quarantine so the signature is valid
codesign --force --deep --sign "${SIGN_ID:--}" "$APP"
echo "Built $APP"
codesign --verify --deep --strict "$APP" && echo "Signature verified"
