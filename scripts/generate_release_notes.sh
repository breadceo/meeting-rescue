#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="${VERSION_FILE:-$ROOT_DIR/VERSION}"
APP_VERSION="${APP_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
CHANGELOG_PATH="${CHANGELOG_PATH:-$ROOT_DIR/CHANGELOG.md}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || printf '1')}"
BUNDLE_ID="${BUNDLE_ID:-com.local.meeting-rescue}"

MODE="${1:-}"
OUTPUT_PATH="${2:-}"

if [[ -z "$MODE" || -z "$OUTPUT_PATH" ]]; then
  printf 'usage: %s bundle|dist-pending|dist-verified|public-markdown|appcast-html OUTPUT_PATH\n' "$0" >&2
  exit 1
fi

release_body="$(
  awk -v version="$APP_VERSION" '
    BEGIN {
      in_section = 0
      found = 0
      target_bracket = "## [" version "]"
      target_plain = "## " version
    }
    /^##[[:space:]]/ {
      if (in_section) {
        exit
      }
      if (index($0, target_bracket) == 1 || index($0, target_plain) == 1) {
        in_section = 1
        found = 1
        next
      }
    }
    in_section {
      print
    }
    END {
      if (!found) {
        exit 2
      }
    }
  ' "$CHANGELOG_PATH" 2>/dev/null || true
)"

if [[ -z "${release_body//[[:space:]]/}" ]]; then
  release_body="- 이번 릴리즈의 사용자 변경사항을 CHANGELOG.md에 추가하세요."
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

case "$MODE" in
  bundle|public-markdown)
    {
      printf '# Meeting Rescue v%s\n\n' "$APP_VERSION"
      printf '%s\n' "$release_body"
    } > "$OUTPUT_PATH"
    ;;
  dist-pending)
    {
      printf '# Meeting Rescue v%s\n\n' "$APP_VERSION"
      printf '%s\n\n' "$release_body"
      printf '## 배포 정보\n\n'
      printf -- '- Build: %s\n' "$BUILD_NUMBER"
      printf -- '- Bundle ID: %s\n' "$BUNDLE_ID"
      printf -- '- Distribution: GitHub Release DMG\n\n'
      printf '## 검증\n\n'
      printf -- '- codesign verification: pending\n'
      printf -- '- notarization: pending\n'
      printf -- '- staple validation: pending\n'
    } > "$OUTPUT_PATH"
    ;;
  dist-verified)
    : "${APP_NOTARY_STATUS:=not recorded}"
    : "${APP_NOTARY_ID:=-}"
    : "${DMG_NOTARY_STATUS:=not recorded}"
    : "${DMG_NOTARY_ID:=-}"
    : "${CHECKSUM_VALUE:=not recorded}"
    : "${ARCHIVE_BASENAME:=archive.dmg}"
    {
      printf '# Meeting Rescue v%s\n\n' "$APP_VERSION"
      printf '%s\n\n' "$release_body"
      printf '## 배포 정보\n\n'
      printf -- '- Build: %s\n' "$BUILD_NUMBER"
      printf -- '- Bundle ID: %s\n' "$BUNDLE_ID"
      printf -- '- Distribution: GitHub Release DMG\n\n'
      printf '## 검증\n\n'
      printf -- '- codesign verification: passed\n'
      printf -- '- App notarization: %s (%s)\n' "$APP_NOTARY_STATUS" "$APP_NOTARY_ID"
      printf -- '- DMG notarization: %s (%s)\n' "$DMG_NOTARY_STATUS" "$DMG_NOTARY_ID"
      printf -- '- staple validation: passed\n'
      printf -- '- Gatekeeper validation: accepted\n'
      printf -- '- Sparkle appcast signature: passed\n\n'
      printf '## Checksum\n\n'
      printf '```txt\n'
      printf '%s  %s\n' "$CHECKSUM_VALUE" "$ARCHIVE_BASENAME"
      printf '```\n'
    } > "$OUTPUT_PATH"
    ;;
  appcast-html)
    {
      printf '<h2>Meeting Rescue v%s</h2>\n' "$APP_VERSION"
      awk '
        function escape(value) {
          gsub(/&/, "\\&amp;", value)
          gsub(/</, "\\&lt;", value)
          gsub(/>/, "\\&gt;", value)
          return value
        }
        BEGIN { in_list = 0 }
        /^### / {
          if (in_list) { print "</ul>"; in_list = 0 }
          line = substr($0, 5)
          print "<h3>" escape(line) "</h3>"
          next
        }
        /^- / {
          if (!in_list) { print "<ul>"; in_list = 1 }
          line = substr($0, 3)
          print "<li>" escape(line) "</li>"
          next
        }
        /^[[:space:]]*$/ {
          if (in_list) { print "</ul>"; in_list = 0 }
          next
        }
        {
          if (in_list) { print "</ul>"; in_list = 0 }
          print "<p>" escape($0) "</p>"
        }
        END {
          if (in_list) { print "</ul>" }
        }
      ' <<< "$release_body"
    } > "$OUTPUT_PATH"
    ;;
  *)
    printf 'error: unsupported mode: %s\n' "$MODE" >&2
    exit 1
    ;;
esac
