#!/usr/bin/env python3
"""Google Calendar OAuth/API spike for Meeting Rescue.

This script intentionally keeps OAuth credentials out of the repository. Pass
the downloaded OAuth client JSON with --credentials, and it stores the user's
token under ~/.meeting-rescue by default.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import http.server
import json
import os
import secrets
import socketserver
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path


AUTHORIZATION_ENDPOINT = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"
EVENTS_ENDPOINT_TEMPLATE = (
    "https://www.googleapis.com/calendar/v3/calendars/{calendar_id}/events"
)
CALENDAR_SCOPE = "https://www.googleapis.com/auth/calendar.events.readonly"
TOKEN_EXPIRY_SKEW_SECONDS = 60
DEFAULT_TOKEN_PATH = (
    Path.home() / ".meeting-rescue" / "google-calendar-oauth" / "token.json"
)


class InstalledClientConfig:
    def __init__(self, client_id, client_secret, redirect_host="localhost"):
        self.client_id = client_id
        self.client_secret = client_secret
        self.redirect_host = redirect_host

    def __repr__(self):
        return (
            "InstalledClientConfig("
            f"client_id={self.client_id!r}, "
            f"redirect_host={self.redirect_host!r})"
        )


class OAuthRedirectState:
    def __init__(self):
        self.code = None
        self.error = None
        self.state = None
        self.query = {}
        self.event = threading.Event()


def load_installed_client_config(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    installed = data.get("installed")
    if not isinstance(installed, dict):
        raise ValueError("OAuth client JSON must contain an 'installed' object")

    client_id = installed.get("client_id")
    client_secret = installed.get("client_secret")
    if not client_id or not client_secret:
        raise ValueError("OAuth client JSON is missing client_id or client_secret")

    redirect_uris = installed.get("redirect_uris") or ["http://localhost"]
    redirect_uri = redirect_uris[0]
    redirect_host = urllib.parse.urlparse(redirect_uri).hostname or "localhost"
    return InstalledClientConfig(
        client_id=client_id,
        client_secret=client_secret,
        redirect_host=redirect_host,
    )


def make_code_verifier():
    return _without_padding(base64.urlsafe_b64encode(secrets.token_bytes(64)))


def make_code_challenge(verifier):
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    return _without_padding(base64.urlsafe_b64encode(digest))


def build_authorization_url(config, redirect_uri, code_challenge, state):
    query = urllib.parse.urlencode(
        {
            "client_id": config.client_id,
            "redirect_uri": redirect_uri,
            "response_type": "code",
            "scope": CALENDAR_SCOPE,
            "access_type": "offline",
            "prompt": "consent",
            "code_challenge": code_challenge,
            "code_challenge_method": "S256",
            "state": state,
        }
    )
    return f"{AUTHORIZATION_ENDPOINT}?{query}"


def build_events_list_url(calendar_id, time_min, time_max, max_results):
    encoded_calendar_id = urllib.parse.quote(calendar_id, safe="")
    endpoint = EVENTS_ENDPOINT_TEMPLATE.format(calendar_id=encoded_calendar_id)
    query = urllib.parse.urlencode(
        {
            "timeMin": time_min,
            "timeMax": time_max,
            "singleEvents": "true",
            "orderBy": "startTime",
            "maxResults": str(max_results),
        }
    )
    return f"{endpoint}?{query}"


def to_meeting_rescue_context(response, fetched_at=None):
    fetched_at = fetched_at or dt.datetime.now(dt.timezone.utc).isoformat()
    events = []
    for item in response.get("items", []):
        events.append(
            {
                "id": f"google:{item.get('id', '')}",
                "title": item.get("summary", ""),
                "startDateText": _event_datetime_text(item.get("start", {})),
                "endDateText": _event_datetime_text(item.get("end", {})),
                "organizer": _email_or_name(item.get("organizer", {})),
                "attendees": [
                    _email_or_name(attendee)
                    for attendee in item.get("attendees", [])
                    if _email_or_name(attendee)
                ],
                "location": item.get("location", ""),
                "recurrenceID": item.get("recurringEventId", ""),
                "descriptionExcerpt": _truncate(item.get("description", ""), 1200),
            }
        )

    return {
        "source": "google-calendar-api",
        "fetchedAt": fetched_at,
        "events": events,
    }


def load_token(path):
    token_path = Path(path).expanduser()
    if not token_path.exists():
        return None
    return json.loads(token_path.read_text(encoding="utf-8"))


def save_token(path, token):
    token_path = Path(path).expanduser()
    token_path.parent.mkdir(parents=True, exist_ok=True)
    token_path.write_text(json.dumps(token, indent=2, sort_keys=True), encoding="utf-8")
    os.chmod(token_path, 0o600)


def exchange_code_for_token(config, redirect_uri, code, code_verifier):
    payload = {
        "client_id": config.client_id,
        "client_secret": config.client_secret,
        "code": code,
        "code_verifier": code_verifier,
        "grant_type": "authorization_code",
        "redirect_uri": redirect_uri,
    }
    return _post_form_json(TOKEN_ENDPOINT, payload)


def refresh_access_token(config, refresh_token):
    payload = {
        "client_id": config.client_id,
        "client_secret": config.client_secret,
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
    }
    return _post_form_json(TOKEN_ENDPOINT, payload)


def fetch_calendar_events(access_token, calendar_id, time_min, time_max, max_results):
    url = build_events_list_url(calendar_id, time_min, time_max, max_results)
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def ensure_access_token(config, token_path, no_browser=False, auth_timeout=180):
    token = load_token(token_path)
    if token and not _token_is_expired(token):
        return token["access_token"]

    if token and token.get("refresh_token"):
        refreshed = refresh_access_token(config, token["refresh_token"])
        token.update(_token_with_expiry(refreshed))
        save_token(token_path, token)
        return token["access_token"]

    oauth_token = run_browser_oauth_flow(config, no_browser=no_browser, timeout=auth_timeout)
    token = _token_with_expiry(oauth_token)
    save_token(token_path, token)
    return token["access_token"]


def run_browser_oauth_flow(config, no_browser=False, timeout=180):
    redirect_state = OAuthRedirectState()
    expected_state = secrets.token_urlsafe(24)
    code_verifier = make_code_verifier()
    code_challenge = make_code_challenge(code_verifier)

    with _redirect_server(config.redirect_host, redirect_state) as server:
        _, port = server.server_address
        redirect_uri = f"http://{_format_redirect_host(config.redirect_host)}:{port}/"
        authorization_url = build_authorization_url(
            config=config,
            redirect_uri=redirect_uri,
            code_challenge=code_challenge,
            state=expected_state,
        )

        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            _open_authorization_url(authorization_url, no_browser)

            if not redirect_state.event.wait(timeout):
                raise TimeoutError("Timed out waiting for OAuth browser redirect")

            if redirect_state.error:
                raise RuntimeError(f"OAuth authorization failed: {redirect_state.error}")
            if redirect_state.state != expected_state:
                raise RuntimeError("OAuth state mismatch")
            if not redirect_state.code:
                raise RuntimeError("OAuth redirect did not include an authorization code")

            return exchange_code_for_token(
                config=config,
                redirect_uri=redirect_uri,
                code=redirect_state.code,
                code_verifier=code_verifier,
            )
        finally:
            server.shutdown()


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Fetch Google Calendar events through the Meeting Rescue OAuth POC."
    )
    parser.add_argument(
        "--credentials",
        required=True,
        help="Path to the downloaded OAuth 2.0 installed-client JSON.",
    )
    parser.add_argument(
        "--token",
        default=str(DEFAULT_TOKEN_PATH),
        help=f"Path for local user token cache. Default: {DEFAULT_TOKEN_PATH}",
    )
    parser.add_argument("--calendar-id", default="primary")
    parser.add_argument("--time-min", default=None, help="RFC3339 lower bound.")
    parser.add_argument("--time-max", default=None, help="RFC3339 upper bound.")
    parser.add_argument("--max-results", type=int, default=10)
    parser.add_argument(
        "--no-browser",
        action="store_true",
        help="Print the authorization URL instead of opening the default browser.",
    )
    parser.add_argument("--auth-timeout", type=int, default=180)
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    config = load_installed_client_config(args.credentials)
    time_min, time_max = _resolve_time_window(args.time_min, args.time_max)

    access_token = ensure_access_token(
        config=config,
        token_path=args.token,
        no_browser=args.no_browser,
        auth_timeout=args.auth_timeout,
    )
    response = fetch_calendar_events(
        access_token=access_token,
        calendar_id=args.calendar_id,
        time_min=time_min,
        time_max=time_max,
        max_results=args.max_results,
    )
    context = to_meeting_rescue_context(response)
    print(json.dumps(context, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


class _RedirectHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        query = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        self.server.redirect_state.query = query
        self.server.redirect_state.code = _first(query.get("code"))
        self.server.redirect_state.error = _first(query.get("error"))
        self.server.redirect_state.state = _first(query.get("state"))
        self.server.redirect_state.event.set()

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(
            b"<html><body><h1>Meeting Rescue authorization received.</h1>"
            b"<p>You can close this browser tab.</p></body></html>"
        )

    def log_message(self, format, *args):
        return


class _ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True


def _redirect_server(host, redirect_state):
    server = _ThreadedTCPServer((host, 0), _RedirectHandler)
    server.redirect_state = redirect_state
    return server


def _post_form_json(url, payload):
    data = urllib.parse.urlencode(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {error.code} from {url}: {_safe_google_error(body)}")


def _safe_google_error(body):
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        return body[:500]
    return json.dumps(
        {
            key: data.get(key)
            for key in ("error", "error_description", "error_uri")
            if key in data
        },
        ensure_ascii=False,
    )


def _token_with_expiry(response):
    now = int(dt.datetime.now(dt.timezone.utc).timestamp())
    token = dict(response)
    expires_in = int(token.get("expires_in", 0))
    token["expires_at"] = now + expires_in
    return token


def _token_is_expired(token):
    expires_at = int(token.get("expires_at", 0))
    now = int(dt.datetime.now(dt.timezone.utc).timestamp())
    return expires_at <= now + TOKEN_EXPIRY_SKEW_SECONDS


def _resolve_time_window(time_min, time_max):
    if time_min and time_max:
        return time_min, time_max
    now = dt.datetime.now().astimezone()
    start = now.replace(microsecond=0)
    end = start + dt.timedelta(hours=2)
    return time_min or start.isoformat(), time_max or end.isoformat()


def _open_authorization_url(url, no_browser):
    if no_browser:
        print("Open this URL in a browser to authorize Meeting Rescue:")
        print(url)
        return
    print("Opening browser for Google Calendar authorization...")
    webbrowser.open(url)


def _event_datetime_text(value):
    return value.get("dateTime") or value.get("date") or ""


def _email_or_name(value):
    return value.get("email") or value.get("displayName") or ""


def _truncate(value, limit):
    if len(value) <= limit:
        return value
    return value[:limit]


def _without_padding(value):
    return value.decode("ascii").rstrip("=")


def _first(value):
    if not value:
        return None
    return value[0]


def _format_redirect_host(host):
    if ":" in host and not host.startswith("["):
        return f"[{host}]"
    return host


if __name__ == "__main__":
    raise SystemExit(main())
