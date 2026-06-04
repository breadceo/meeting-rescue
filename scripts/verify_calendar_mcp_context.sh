#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_PATH="$ROOT_DIR/scripts/calendar_mcp_smoke.schema.json"
OUTPUT_DIR="$ROOT_DIR/.tmp/calendar-mcp-smoke"
CODEX_STDERR="$OUTPUT_DIR/codex-calendar.stderr"
CLAUDE_STDERR="$OUTPUT_DIR/claude-calendar.stderr"
COMMAND_TIMEOUT_SECONDS="${COMMAND_TIMEOUT_SECONDS:-90}"
mkdir -p "$OUTPUT_DIR"

if ! codex mcp get google-calendar >/dev/null 2>&1; then
  echo "BLOCK: Codex google-calendar MCP is not configured." >&2
  echo "Run: codex mcp add google-calendar --url https://calendarmcp.googleapis.com/mcp/v1" >&2
  echo "Then: codex mcp login google-calendar" >&2
  exit 10
fi

if ! claude mcp list 2>/dev/null | grep -E "Google Calendar.*Connected|Google Calendar.*✓ Connected" >/dev/null; then
  echo "BLOCK: Claude Code Google Calendar MCP is not connected." >&2
  exit 11
fi

PROMPT='Use only the connected Google Calendar MCP server to fetch calendar events overlapping now through the next 2 hours. Do not use app connectors, browser automation, local shell date commands, memory, or any fallback data source. Return only JSON matching the provided schema. Include at most 5 events. If there are no events, return an empty events array after actually checking Google Calendar MCP.'

if ! perl -e 'alarm shift; exec @ARGV' "$COMMAND_TIMEOUT_SECONDS" \
  codex exec \
    --model gpt-5.4-mini \
    --skip-git-repo-check \
    --disable apps \
    --disable tool_search \
    --sandbox read-only \
    --output-schema "$SCHEMA_PATH" \
    - > "$OUTPUT_DIR/codex-calendar.json" 2> "$CODEX_STDERR" <<EOF
$PROMPT
Set provider to "codex" and mcpServer to "google-calendar".
EOF
then
  cat "$CODEX_STDERR" >&2
  if grep -q "Auth required" "$CODEX_STDERR"; then
    echo "BLOCK: Codex google-calendar MCP requires authentication; app connector fallback is disabled." >&2
    exit 12
  fi
  echo "BLOCK: Codex google-calendar MCP smoke failed." >&2
  exit 13
fi

if grep -q "Auth required" "$CODEX_STDERR"; then
  cat "$CODEX_STDERR" >&2
  echo "BLOCK: Codex google-calendar MCP requires authentication; app connector fallback is disabled." >&2
  exit 12
fi

if ! grep -q "mcp: google-calendar/list_events (completed)" "$CODEX_STDERR"; then
  cat "$CODEX_STDERR" >&2
  echo "BLOCK: Codex did not complete google-calendar/list_events through MCP." >&2
  exit 14
fi

SCHEMA_JSON="$(cat "$SCHEMA_PATH")"
if ! perl -e 'alarm shift; exec @ARGV' "$COMMAND_TIMEOUT_SECONDS" \
  claude -p \
    --output-format json \
    --input-format text \
    --no-session-persistence \
    --json-schema "$SCHEMA_JSON" \
    "$PROMPT Set provider to \"claude\" and mcpServer to \"Google Calendar\"." \
    > "$OUTPUT_DIR/claude-calendar.json" 2> "$CLAUDE_STDERR"; then
  cat "$CLAUDE_STDERR" >&2
  echo "BLOCK: Claude Code Google Calendar MCP smoke failed." >&2
  exit 15
fi

python3 - "$OUTPUT_DIR/codex-calendar.json" "$OUTPUT_DIR/claude-calendar.json" <<'PY'
import json
import sys

for path in sys.argv[1:]:
    raw = open(path, encoding="utf-8").read()
    data = json.loads(raw)
    if "structured_output" in data:
        data = data["structured_output"]
    if isinstance(data, str):
        data = json.loads(data)
    assert data["provider"] in {"codex", "claude"}, data
    assert data["mcpServer"], data
    assert isinstance(data["events"], list), data
    print(f"PASS {data['provider']}: {len(data['events'])} calendar events fetched")
PY
