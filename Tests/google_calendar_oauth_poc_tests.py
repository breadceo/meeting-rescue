import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "google_calendar_oauth_poc.py"


def load_poc_module(test_case):
    test_case.assertTrue(SCRIPT_PATH.exists(), f"{SCRIPT_PATH} should exist")
    spec = importlib.util.spec_from_file_location("google_calendar_oauth_poc", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GoogleCalendarOAuthPOCTests(unittest.TestCase):
    def setUp(self):
        self.poc = load_poc_module(self)

    def test_loads_installed_client_without_exposing_secret(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "client_secret.json"
            path.write_text(
                json.dumps(
                    {
                        "installed": {
                            "client_id": "client-id.apps.googleusercontent.com",
                            "client_secret": "secret-value",
                            "redirect_uris": ["http://localhost"],
                        }
                    }
                ),
                encoding="utf-8",
            )

            config = self.poc.load_installed_client_config(path)

            self.assertEqual(config.client_id, "client-id.apps.googleusercontent.com")
            self.assertEqual(config.client_secret, "secret-value")
            self.assertEqual(config.redirect_host, "localhost")
            self.assertNotIn("secret-value", repr(config))

    def test_builds_authorization_url_with_pkce_and_calendar_scope(self):
        config = self.poc.InstalledClientConfig(
            client_id="client-id.apps.googleusercontent.com",
            client_secret="secret-value",
            redirect_host="localhost",
        )

        url = self.poc.build_authorization_url(
            config=config,
            redirect_uri="http://localhost:49152/",
            code_challenge="challenge-value",
            state="state-value",
        )

        self.assertTrue(url.startswith("https://accounts.google.com/o/oauth2/v2/auth?"))
        self.assertIn("client_id=client-id.apps.googleusercontent.com", url)
        self.assertIn("redirect_uri=http%3A%2F%2Flocalhost%3A49152%2F", url)
        self.assertIn("response_type=code", url)
        self.assertIn("access_type=offline", url)
        self.assertIn("prompt=consent", url)
        self.assertIn("code_challenge=challenge-value", url)
        self.assertIn("code_challenge_method=S256", url)
        self.assertIn(
            "scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcalendar.events.readonly",
            url,
        )

    def test_builds_events_list_url_for_primary_calendar_window(self):
        url = self.poc.build_events_list_url(
            calendar_id="primary",
            time_min="2026-06-08T10:45:00+09:00",
            time_max="2026-06-08T12:30:00+09:00",
            max_results=10,
        )

        self.assertTrue(
            url.startswith("https://www.googleapis.com/calendar/v3/calendars/primary/events?")
        )
        self.assertIn("singleEvents=true", url)
        self.assertIn("orderBy=startTime", url)
        self.assertIn("maxResults=10", url)
        self.assertIn("timeMin=2026-06-08T10%3A45%3A00%2B09%3A00", url)
        self.assertIn("timeMax=2026-06-08T12%3A30%3A00%2B09%3A00", url)

    def test_converts_google_events_to_meeting_rescue_context(self):
        response = {
            "items": [
                {
                    "id": "event-1",
                    "summary": "Weekly Product Sync",
                    "start": {"dateTime": "2026-06-08T11:00:00+09:00"},
                    "end": {"dateTime": "2026-06-08T12:00:00+09:00"},
                    "organizer": {"email": "owner@example.com"},
                    "attendees": [
                        {"email": "owner@example.com"},
                        {"displayName": "Teammate"},
                    ],
                    "location": "Zigbang(2F)_Meeting Room L3",
                    "description": "agenda " * 400,
                    "recurringEventId": "series-1",
                }
            ]
        }

        context = self.poc.to_meeting_rescue_context(response)

        self.assertEqual(context["source"], "google-calendar-api")
        self.assertEqual(context["events"][0]["id"], "google:event-1")
        self.assertEqual(context["events"][0]["title"], "Weekly Product Sync")
        self.assertEqual(context["events"][0]["startDateText"], "2026-06-08T11:00:00+09:00")
        self.assertEqual(context["events"][0]["endDateText"], "2026-06-08T12:00:00+09:00")
        self.assertEqual(context["events"][0]["organizer"], "owner@example.com")
        self.assertEqual(context["events"][0]["attendees"], ["owner@example.com", "Teammate"])
        self.assertEqual(context["events"][0]["location"], "Zigbang(2F)_Meeting Room L3")
        self.assertEqual(context["events"][0]["recurrenceID"], "series-1")
        self.assertLessEqual(len(context["events"][0]["descriptionExcerpt"]), 1200)


if __name__ == "__main__":
    unittest.main()
