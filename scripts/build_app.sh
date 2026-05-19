#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_CONFIG_FILE="${RELEASE_CONFIG_FILE:-$ROOT_DIR/config/release.local.env}"

if [[ -f "$RELEASE_CONFIG_FILE" ]]; then
  # Local release settings may contain signing identity or notary profile names.
  # Keep this file out of git; see config/release.env.example.
  source "$RELEASE_CONFIG_FILE"
fi

CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="${APP_NAME:-Meeting Rescue}"
BUNDLE_ID="${BUNDLE_ID:-com.local.meeting-rescue}"
VERSION_FILE="${VERSION_FILE:-$ROOT_DIR/VERSION}"
APP_VERSION="${APP_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || printf '1')}"
APP_COPYRIGHT="${APP_COPYRIGHT:-Local development build}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_ICON_SOURCE="$ROOT_DIR/Sources/MeetingRescue/Resources/AppIcon.png"
APP_ICON_NAME="AppIcon"

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION" --product MeetingRescue

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE="$BIN_DIR/MeetingRescue"
RESOURCE_BUNDLE="$BIN_DIR/MeetingRescue_MeetingRescue.bundle"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/MeetingRescue"
chmod +x "$MACOS_DIR/MeetingRescue"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/MeetingRescue_MeetingRescue.bundle"
fi

if [[ -f "$APP_ICON_SOURCE" ]] && command -v iconutil >/dev/null 2>&1; then
  ICONSET_DIR="$(mktemp -d "${TMPDIR:-/tmp}/meeting-rescue-iconset.XXXXXX")/$APP_ICON_NAME.iconset"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$APP_ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$APP_ICON_NAME.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>ko</string>
  <key>CFBundleExecutable</key>
  <string>MeetingRescue</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHumanReadableCopyright</key>
  <string>$APP_COPYRIGHT</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>Meeting Rescue는 사용자가 선택한 Recordings 폴더의 transcript 파일을 읽기 위해 Documents 접근이 필요합니다.</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign_args=(--force --deep)
  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign_args+=(--options runtime --timestamp --sign "$SIGN_IDENTITY")
  else
    codesign_args+=(--sign -)
  fi
  if [[ -n "${CODESIGN_ENTITLEMENTS:-}" ]]; then
    codesign_args+=(--entitlements "$CODESIGN_ENTITLEMENTS")
  fi
  codesign "${codesign_args[@]}" "$APP_DIR" >/dev/null
fi

printf 'Built app: %s\n' "$APP_DIR"
