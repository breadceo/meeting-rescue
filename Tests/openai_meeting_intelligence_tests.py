import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/openai_meeting_intelligence.py"


class OpenAIMeetingIntelligenceTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.exists(), "OpenAI adapter must exist")
        spec = importlib.util.spec_from_file_location("openai_meeting", SCRIPT)
        self.api = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.api)

    def test_snapshot_uses_existing_schema_and_no_server_storage(self):
        body = self.api.build_request("JSON 객체 하나만 반환하세요.\nPayload:\n{}", "gpt-5.4-mini")
        self.assertFalse(body["store"])
        self.assertEqual(body["model"], "gpt-5.4-mini")
        fmt = body["text"]["format"]
        self.assertTrue(fmt["strict"])
        self.assertIn("topicTimeline", fmt["schema"]["properties"])
        self.assertNotIn("$schema", fmt["schema"])

    def test_patch_detection_does_not_use_untrusted_transcript_text(self):
        body = self.api.build_request("JSON patch 객체 하나만 반환하세요.\nPayload:\n{}", "test")
        self.assertIn("topicTimelineUpserts", body["text"]["format"]["schema"]["properties"])
        body = self.api.build_request('JSON 객체 하나만 반환하세요.\nPayload:\n{"text":"JSON patch 객체"}', "test")
        self.assertIn("topicTimeline", body["text"]["format"]["schema"]["properties"])

    def test_extracts_only_assistant_json_and_usage(self):
        response = {"status": "completed", "output": [
            {"type": "reasoning", "summary": []},
            {"type": "message", "content": [{"type": "output_text", "text": '{"meetingType":"planning"}'}]},
        ]}
        self.assertEqual(json.loads(self.api.response_text(response)), {"meetingType": "planning"})

    def test_rejects_refusal_incomplete_and_empty_output(self):
        for response in [
            {"status": "incomplete", "output": []},
            {"status": "completed", "output": []},
            {"status": "completed", "output": [{"type": "message", "content": [{"type": "refusal", "refusal": "no"}]}]},
            {"status": "completed", "output": [{"type": "message", "content": [{"type": "output_text", "text": "[]"}]}]},
        ]:
            with self.subTest(response=response), self.assertRaises(ValueError):
                self.api.response_text(response)

    def test_key_file_is_private_and_not_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            key_path = Path(tmp) / "private" / "key"
            self.api.save_key(key_path, "sk-test-secret")
            self.assertEqual(key_path.stat().st_mode & 0o777, 0o600)
            with patch.dict(os.environ, {}, clear=True):
                self.assertEqual(self.api.load_key(key_path), "sk-test-secret")
            with self.assertRaises(FileExistsError):
                self.api.save_key(key_path, "replacement")
            key_path.chmod(0o644)
            with patch.dict(os.environ, {}, clear=True), self.assertRaises(ValueError):
                self.api.load_key(key_path)

    def test_posts_responses_request_without_sdk(self):
        response = io.BytesIO(b'{"status":"completed","output":[]}')
        with patch.object(self.api, "urlopen", return_value=response) as send:
            result = self.api.call_api({"model": "test"}, "sk-test-secret")
        request = send.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.openai.com/v1/responses")
        self.assertEqual(request.get_header("Authorization"), "Bearer sk-test-secret")
        self.assertEqual(json.loads(request.data), {"model": "test"})
        self.assertEqual(result["status"], "completed")

    def test_http_error_does_not_leak_credentials_or_prompt(self):
        error = HTTPError("https://api.openai.com", 429, "sk-secret", {}, io.BytesIO(b'private transcript sk-secret'))
        with patch.object(self.api, "urlopen", side_effect=error), self.assertRaises(ValueError) as raised:
            self.api.call_api({}, "sk-secret")
        self.assertIn("429", str(raised.exception))
        self.assertNotIn("sk-secret", str(raised.exception))
        self.assertNotIn("transcript", str(raised.exception))

    def test_smoke_dry_run_needs_no_key_and_sends_no_request(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--smoke-test", "--dry-run"],
                                capture_output=True, text=True, env={"PATH": os.environ["PATH"]})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["model"], "gpt-6-luna")

    def test_luna_disables_reasoning_for_short_connection_test(self):
        body = self.api.build_request("Return ok true.", "gpt-6-luna", smoke_test=True)
        self.assertEqual(body["reasoning"], {"effort": "none"})

    def test_empty_prompt_is_rejected_before_network(self):
        with self.assertRaises(ValueError):
            self.api.build_request("  ", "test")

    def test_app_envelope_uses_response_model_and_real_usage(self):
        response = {"id": "resp-test", "model": "gpt-6-luna-2026-09-22", "usage": {
            "input_tokens": 1234, "output_tokens": 87, "total_tokens": 1321,
            "input_tokens_details": {"cached_tokens": 100},
            "output_tokens_details": {"reasoning_tokens": 12}}}
        envelope = self.api.app_result(response, '{"meetingType":"planning"}')
        self.assertEqual(envelope["meetingRescueResultVersion"], 1)
        self.assertEqual(envelope["usage"]["modelName"], "gpt-6-luna-2026-09-22")
        self.assertEqual(envelope["usage"]["inputTokens"], 1234)
        self.assertEqual(envelope["usage"]["responseID"], "resp-test")
        self.assertEqual(envelope["usage"]["cachedInputTokens"], 100)

    def test_missing_reported_usage_is_not_replaced_with_guesses(self):
        with self.assertRaises(ValueError):
            self.api.app_result({"model": "gpt-6-luna"}, '{}')

    def test_main_negotiates_envelope_without_breaking_legacy_app(self):
        response = {"id": "resp-test", "model": "gpt-6-luna", "status": "completed",
                    "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15},
                    "output": [{"type": "message", "content": [{"type": "output_text", "text": '{"meetingType":"planning"}'}]}]}
        for format_name in ["", "json-v1"]:
            output = io.StringIO()
            with patch.object(sys, "argv", [str(SCRIPT)]), \
                 patch.object(sys, "stdin", io.StringIO("JSON 객체\nPayload:\n{}")), \
                 patch.object(sys, "stdout", output), patch.object(sys, "stderr", io.StringIO()), \
                 patch.dict(os.environ, {"MEETING_RESCUE_RESULT_FORMAT": format_name}), \
                 patch.object(self.api, "load_key", return_value="sk-test"), \
                 patch.object(self.api, "call_api", return_value=response):
                self.assertEqual(self.api.main(), 0)
            body = json.loads(output.getvalue())
            if format_name:
                self.assertEqual(body["usage"]["inputTokens"], 10)
                self.assertEqual(json.loads(body["output"])["meetingType"], "planning")
            else:
                self.assertEqual(body, {"meetingType": "planning"})


if __name__ == "__main__":
    unittest.main()
