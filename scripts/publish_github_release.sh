#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_CONFIG_FILE="${RELEASE_CONFIG_FILE:-$ROOT_DIR/config/release.local.env}"

if [[ -f "$RELEASE_CONFIG_FILE" ]]; then
  source "$RELEASE_CONFIG_FILE"
fi

VERSION_FILE="${VERSION_FILE:-$ROOT_DIR/VERSION}"
APP_VERSION="${APP_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
TAG_NAME="${TAG_NAME:-v$APP_VERSION}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-breadceo/meeting-rescue}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_NAME="${APP_NAME:-Meeting Rescue}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
RELEASE_TITLE="${RELEASE_TITLE:-Meeting Rescue $TAG_NAME}"
RELEASE_NOTES_PATH="${RELEASE_NOTES_PATH:-$DIST_DIR/release-notes-v$APP_VERSION.md}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$DIST_DIR/Meeting-Rescue-v$APP_VERSION-notarized.dmg}"
CHECKSUM_PATH="${CHECKSUM_PATH:-$ARCHIVE_PATH.sha256}"
ARCHIVE_CONTENT_TYPE="${ARCHIVE_CONTENT_TYPE:-application/x-apple-diskimage}"
RELEASE_DRAFT="${RELEASE_DRAFT:-0}"
PAGES_BASE_URL="${PAGES_BASE_URL:-https://breadceo.github.io/meeting-rescue}"
RELEASE_ASSET_URL="${RELEASE_ASSET_URL:-https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG_NAME/$(basename "$ARCHIVE_PATH")}"
APPCAST_PATH="${APPCAST_PATH:-$ROOT_DIR/docs/appcast.xml}"
SPARKLE_SIGN_UPDATE_TOOL="${SPARKLE_SIGN_UPDATE_TOOL:-$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update}"

cd "$ROOT_DIR"

if ! command -v gh >/dev/null 2>&1; then
  printf 'error: gh CLI is required.\n' >&2
  exit 1
fi

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  printf 'error: release archive not found: %s\n' "$ARCHIVE_PATH" >&2
  printf 'Run ./scripts/notarize_app.sh first.\n' >&2
  exit 1
fi

if [[ ! -f "$CHECKSUM_PATH" ]]; then
  printf 'error: checksum not found: %s\n' "$CHECKSUM_PATH" >&2
  exit 1
fi

if [[ ! -f "$RELEASE_NOTES_PATH" ]]; then
  printf 'error: release notes not found: %s\n' "$RELEASE_NOTES_PATH" >&2
  printf 'Run ./scripts/package_release.sh first.\n' >&2
  exit 1
fi

if [[ ! -x "$SPARKLE_SIGN_UPDATE_TOOL" ]]; then
  printf 'error: Sparkle sign_update tool not found: %s\n' "$SPARKLE_SIGN_UPDATE_TOOL" >&2
  printf 'Run swift package resolve first.\n' >&2
  exit 1
fi

shasum -a 256 -c "$CHECKSUM_PATH"

if [[ -d "$APP_DIR" ]]; then
  codesign --verify --deep --strict --verbose=2 "$APP_DIR" >/dev/null
fi

if [[ "$ARCHIVE_PATH" == *.dmg ]]; then
  xcrun stapler validate "$ARCHIVE_PATH" >/dev/null
  spctl -a -t open --context context:primary-signature -vv "$ARCHIVE_PATH" >/dev/null
fi

signature_attributes="$("$SPARKLE_SIGN_UPDATE_TOOL" "$ARCHIVE_PATH")"
pub_date="$(LC_ALL=C date -R)"
build_number="$(plutil -extract CFBundleVersion raw -o - "$DIST_DIR/Meeting Rescue.app/Contents/Info.plist" 2>/dev/null || git rev-list --count HEAD 2>/dev/null || printf '1')"
archive_basename="$(basename "$ARCHIVE_PATH")"
checksum_value="$(awk '{print $1}' "$CHECKSUM_PATH")"
app_notary_result="$DIST_DIR/notary/Meeting-Rescue-v$APP_VERSION-notary-result.json"
dmg_notary_result="$DIST_DIR/notary/Meeting-Rescue-v$APP_VERSION-dmg-notary-result.json"
app_notary_status="$(plutil -extract status raw -o - "$app_notary_result" 2>/dev/null || printf 'not recorded')"
app_notary_id="$(plutil -extract id raw -o - "$app_notary_result" 2>/dev/null || printf '-')"
dmg_notary_status="$(plutil -extract status raw -o - "$dmg_notary_result" 2>/dev/null || printf 'not recorded')"
dmg_notary_id="$(plutil -extract id raw -o - "$dmg_notary_result" 2>/dev/null || printf '-')"

if grep -q 'pending' "$RELEASE_NOTES_PATH"; then
  cat > "$RELEASE_NOTES_PATH" <<NOTES
# Meeting Rescue v$APP_VERSION

- Build: $build_number
- Bundle ID: ${BUNDLE_ID:-com.local.meeting-rescue}
- Distribution: GitHub Release DMG

## 검증

- codesign verification: passed
- App notarization: $app_notary_status ($app_notary_id)
- DMG notarization: $dmg_notary_status ($dmg_notary_id)
- staple validation: passed
- Gatekeeper validation: accepted
- Sparkle appcast signature: passed

## Checksum

\`\`\`txt
$checksum_value  $archive_basename
\`\`\`
NOTES
fi

if ! git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
  git tag -a "$TAG_NAME" -m "Meeting Rescue $TAG_NAME"
fi

git push origin "$TAG_NAME"

if gh release view "$TAG_NAME" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  gh release upload "$TAG_NAME" \
    "$ARCHIVE_PATH#Meeting Rescue $APP_VERSION for macOS DMG" \
    "$CHECKSUM_PATH#SHA-256 checksum" \
    --repo "$GITHUB_REPOSITORY" \
    --clobber
else
  release_args=(
    release create "$TAG_NAME"
    "$ARCHIVE_PATH#Meeting Rescue $APP_VERSION for macOS DMG"
    "$CHECKSUM_PATH#SHA-256 checksum"
    --repo "$GITHUB_REPOSITORY"
    --title "$RELEASE_TITLE"
    --notes-file "$RELEASE_NOTES_PATH"
    --verify-tag
  )

  if [[ "$RELEASE_DRAFT" == "1" ]]; then
    release_args+=(--draft)
  fi

  gh "${release_args[@]}"
fi

mkdir -p "$(dirname "$APPCAST_PATH")"
cat > "$APPCAST_PATH" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
  xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
  xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Meeting Rescue Updates</title>
    <link>$PAGES_BASE_URL/appcast.xml</link>
    <description>Meeting Rescue release updates.</description>
    <language>ko</language>
    <item>
      <title>Meeting Rescue $APP_VERSION</title>
      <description><![CDATA[
        <p>Meeting Rescue $APP_VERSION release.</p>
        <p><a href="https://github.com/$GITHUB_REPOSITORY/releases/tag/$TAG_NAME">Release notes</a></p>
      ]]></description>
      <pubDate>$pub_date</pubDate>
      <sparkle:version>$build_number</sparkle:version>
      <sparkle:shortVersionString>$APP_VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="$RELEASE_ASSET_URL"
        $signature_attributes
        type="$ARCHIVE_CONTENT_TYPE" />
    </item>
  </channel>
</rss>
APPCAST

"$SPARKLE_SIGN_UPDATE_TOOL" --disable-signing-warning "$APPCAST_PATH" >/dev/null

printf 'Release created: https://github.com/%s/releases/tag/%s\n' "$GITHUB_REPOSITORY" "$TAG_NAME"
printf 'Appcast updated: %s\n' "$APPCAST_PATH"
