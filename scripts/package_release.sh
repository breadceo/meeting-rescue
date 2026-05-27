#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_CONFIG_FILE="${RELEASE_CONFIG_FILE:-$ROOT_DIR/config/release.local.env}"

if [[ -f "$RELEASE_CONFIG_FILE" ]]; then
  source "$RELEASE_CONFIG_FILE"
fi

APP_NAME="${APP_NAME:-Meeting Rescue}"
VERSION_FILE="${VERSION_FILE:-$ROOT_DIR/VERSION}"
APP_VERSION="${APP_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || printf '1')}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ARCHIVE_BASENAME="${ARCHIVE_BASENAME:-Meeting-Rescue-v$APP_VERSION}"
DMG_PATH="$DIST_DIR/$ARCHIVE_BASENAME.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
RELEASE_NOTES_PATH="${RELEASE_NOTES_PATH:-$DIST_DIR/release-notes-v$APP_VERSION.md}"
OVERWRITE_RELEASE_NOTES="${OVERWRITE_RELEASE_NOTES:-1}"
APP_RELEASE_NOTES_RESOURCE="${APP_RELEASE_NOTES_RESOURCE:-$ROOT_DIR/Sources/MeetingRescue/Resources/ReleaseNotes.md}"

cd "$ROOT_DIR"

APP_VERSION="$APP_VERSION" BUILD_NUMBER="$BUILD_NUMBER" BUNDLE_ID="${BUNDLE_ID:-com.local.meeting-rescue}" \
  "$ROOT_DIR/scripts/generate_release_notes.sh" bundle "$APP_RELEASE_NOTES_RESOURCE"

"$ROOT_DIR/scripts/build_app.sh"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$DMG_PATH" "$CHECKSUM_PATH"
DMG_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/meeting-rescue-dmg.XXXXXX")"
trap 'rm -rf "$DMG_STAGING_DIR"' EXIT
ditto "$APP_DIR" "$DMG_STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
hdiutil create \
  -volname "$APP_NAME $APP_VERSION" \
  -srcfolder "$DMG_STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null
shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"

if [[ "$OVERWRITE_RELEASE_NOTES" == "1" || ! -f "$RELEASE_NOTES_PATH" ]]; then
  APP_VERSION="$APP_VERSION" BUILD_NUMBER="$BUILD_NUMBER" BUNDLE_ID="${BUNDLE_ID:-com.local.meeting-rescue}" \
    "$ROOT_DIR/scripts/generate_release_notes.sh" dist-pending "$RELEASE_NOTES_PATH"
fi

printf 'Release archive: %s\n' "$DMG_PATH"
printf 'Checksum: %s\n' "$CHECKSUM_PATH"
printf 'Release notes: %s\n' "$RELEASE_NOTES_PATH"
