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
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
NOTARY_DIR="$DIST_DIR/notary"
NOTARY_ZIP="$NOTARY_DIR/Meeting-Rescue-v$APP_VERSION-notary.zip"
NOTARY_RESULT="$NOTARY_DIR/Meeting-Rescue-v$APP_VERSION-notary-result.json"
FINAL_DMG="$DIST_DIR/Meeting-Rescue-v$APP_VERSION-notarized.dmg"
FINAL_CHECKSUM="$FINAL_DMG.sha256"
DMG_NOTARY_RESULT="$NOTARY_DIR/Meeting-Rescue-v$APP_VERSION-dmg-notary-result.json"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"

if [[ -z "$NOTARY_KEYCHAIN_PROFILE" ]]; then
  printf 'error: NOTARY_KEYCHAIN_PROFILE is required. Configure it in config/release.local.env.\n' >&2
  exit 1
fi

if [[ ! -d "$APP_DIR" ]]; then
  "$ROOT_DIR/scripts/build_app.sh"
fi

mkdir -p "$NOTARY_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$NOTARY_ZIP" "$NOTARY_RESULT" "$DMG_NOTARY_RESULT" "$FINAL_DMG" "$FINAL_CHECKSUM"
ditto -c -k --keepParent "$APP_DIR" "$NOTARY_ZIP"

xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
  --wait \
  --output-format json > "$NOTARY_RESULT"

submission_id="$(plutil -extract id raw -o - "$NOTARY_RESULT" 2>/dev/null || true)"
notary_status="$(plutil -extract status raw -o - "$NOTARY_RESULT" 2>/dev/null || true)"

if [[ "$notary_status" != "Accepted" ]]; then
  printf 'error: notarization status is %s\n' "${notary_status:-unknown}" >&2
  if [[ -n "$submission_id" ]]; then
    printf 'Run this for details:\n' >&2
    printf 'xcrun notarytool log %q --keychain-profile %q\n' "$submission_id" "$NOTARY_KEYCHAIN_PROFILE" >&2
  fi
  exit 1
fi

xcrun stapler staple "$APP_DIR"
xcrun stapler validate "$APP_DIR"
spctl -a -t exec -vv "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

DMG_STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/meeting-rescue-dmg.XXXXXX")"
trap 'rm -rf "$DMG_STAGING_DIR"' EXIT
ditto "$APP_DIR" "$DMG_STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
hdiutil create \
  -volname "$APP_NAME $APP_VERSION" \
  -srcfolder "$DMG_STAGING_DIR" \
  -format UDZO \
  -ov \
  "$FINAL_DMG" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$FINAL_DMG"
fi

xcrun notarytool submit "$FINAL_DMG" \
  --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
  --wait \
  --output-format json > "$DMG_NOTARY_RESULT"

dmg_submission_id="$(plutil -extract id raw -o - "$DMG_NOTARY_RESULT" 2>/dev/null || true)"
dmg_notary_status="$(plutil -extract status raw -o - "$DMG_NOTARY_RESULT" 2>/dev/null || true)"

if [[ "$dmg_notary_status" != "Accepted" ]]; then
  printf 'error: dmg notarization status is %s\n' "${dmg_notary_status:-unknown}" >&2
  if [[ -n "$dmg_submission_id" ]]; then
    printf 'Run this for details:\n' >&2
    printf 'xcrun notarytool log %q --keychain-profile %q\n' "$dmg_submission_id" "$NOTARY_KEYCHAIN_PROFILE" >&2
  fi
  exit 1
fi

xcrun stapler staple "$FINAL_DMG"
xcrun stapler validate "$FINAL_DMG"
spctl -a -t open --context context:primary-signature -vv "$FINAL_DMG"
shasum -a 256 "$FINAL_DMG" > "$FINAL_CHECKSUM"

printf 'Notarization accepted: %s\n' "$submission_id"
printf 'DMG notarization accepted: %s\n' "$dmg_submission_id"
printf 'Final archive: %s\n' "$FINAL_DMG"
printf 'Checksum: %s\n' "$FINAL_CHECKSUM"
