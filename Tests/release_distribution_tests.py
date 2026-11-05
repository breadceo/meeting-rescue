import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ReleaseDistributionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)
        self.dist = self.work / "dist"
        self.dist.mkdir()
        (self.dist / "Meeting Rescue.app").mkdir()
        self.calls = self.work / "calls.jsonl"
        self.bin = self.work / "bin"
        self.bin.mkdir()
        stub = self.bin / "stub"
        stub.write_text(f"#!{sys.executable}\n" + r'''
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps([name] + args) + "\n")
if name == "xcrun":
    sys.exit(0 if os.environ.get("NOTARY_VALID") == "1" else 1)
if name == "codesign" and os.environ.get("INVALID_CODE_SIGNATURE") == "1":
    sys.exit(1)
if name == "gh" and args[:2] == ["release", "view"]:
    sys.exit(1)
if name == "git" and args[:1] == ["rev-parse"]:
    sys.exit(1)
if name == "plutil":
    print("130")
if name == "sign_update":
    if os.environ.get("INVALID_UPDATE_SIGNATURE") == "1" and "--verify" in args:
        sys.exit(1)
    if "--verify" not in args and any(x.endswith(".dmg") for x in args):
        print('sparkle:edSignature="test-signature" length="7"')
''', encoding="utf-8")
        stub.chmod(0o755)
        for name in ["git", "gh", "xcrun", "spctl", "codesign", "plutil", "sign_update"]:
            (self.bin / name).symlink_to(stub)
        self.changelog = self.work / "CHANGELOG.md"
        self.changelog.write_text("## [9.9.9]\n\n- Test release.\n")
        for suffix in ["", "-notarized"]:
            archive = self.dist / f"Meeting-Rescue-v9.9.9{suffix}.dmg"
            archive.write_bytes(b"fixture")
            Path(str(archive) + ".sha256").write_text(
                hashlib.sha256(b"fixture").hexdigest() + "  " + str(archive) + "\n"
            )
        (self.dist / "release-notes-v9.9.9.md").write_text("pending")
        self.env = dict(os.environ, PATH=str(self.bin) + ":" + os.environ["PATH"],
                        CALL_LOG=str(self.calls), RELEASE_CONFIG_FILE="/dev/null",
                        APP_VERSION="9.9.9", CHANGELOG_PATH=str(self.changelog),
                        DIST_DIR=str(self.dist), APPCAST_PATH=str(self.work / "appcast.xml"),
                        RELEASES_DOCS_DIR=str(self.work / "releases"),
                        SPARKLE_SIGN_UPDATE_TOOL=str(self.bin / "sign_update"),
                        UPDATE_FEED_REPOSITORY="example/updates")
        self.env.pop("RELEASE_NOTARIZED", None)

    def publish(self, **env):
        return subprocess.run([str(ROOT / "scripts/publish_github_release.sh")],
                              env=dict(self.env, **env), capture_output=True, text=True)

    def logged_calls(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def test_unnotarized_release_skips_apple_checks_but_verifies_update_signature(self):
        result = self.publish(RELEASE_NOTARIZED="0")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.logged_calls()
        self.assertFalse(any(c[0] in ["xcrun", "spctl"] for c in calls))
        self.assertTrue(any(c[:2] == ["codesign", "--verify"] for c in calls))
        self.assertTrue(any(c[:2] == ["sign_update", "--verify"] for c in calls))
        release = next(c for c in calls if c[:3] == ["gh", "release", "create"])
        self.assertTrue(any("Meeting-Rescue-v9.9.9.dmg#" in x for x in release))
        notes = (self.dist / "release-notes-v9.9.9.md").read_text()
        self.assertIn("unnotarized", notes.lower())
        self.assertNotIn("Gatekeeper validation: accepted", notes)
        self.assertNotIn("staple validation: passed", notes)

    def test_notarization_is_still_required_by_default(self):
        result = self.publish()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(any(c[0] == "xcrun" for c in self.logged_calls()))
        self.assertFalse(any(c[:3] == ["gh", "release", "create"] for c in self.logged_calls()))

    def test_notarized_default_still_publishes_after_apple_checks(self):
        result = self.publish(NOTARY_VALID="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.logged_calls()
        self.assertTrue(any(c[0] == "spctl" for c in calls))
        release = next(c for c in calls if c[:3] == ["gh", "release", "create"])
        self.assertTrue(any("Meeting-Rescue-v9.9.9-notarized.dmg#" in x for x in release))
        self.assertNotIn("unnotarized", (self.dist / "release-notes-v9.9.9.md").read_text().lower())

    def test_invalid_mode_is_rejected_before_external_actions(self):
        result = self.publish(RELEASE_NOTARIZED="typo")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("RELEASE_NOTARIZED", result.stderr)
        self.assertEqual(self.logged_calls(), [])

    def test_unnotarized_release_still_rejects_bad_checksum_or_signatures(self):
        for failure in ["checksum", "code", "update"]:
            with self.subTest(failure=failure):
                self.calls.unlink(missing_ok=True)
                archive = self.dist / "Meeting-Rescue-v9.9.9.dmg"
                archive.write_bytes(b"bad" if failure == "checksum" else b"fixture")
                result = self.publish(RELEASE_NOTARIZED="0",
                                      INVALID_CODE_SIGNATURE="1" if failure == "code" else "0",
                                      INVALID_UPDATE_SIGNATURE="1" if failure == "update" else "0")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any(c[:3] == ["gh", "release", "create"] for c in self.logged_calls()))

    def test_unnotarized_notes_ignore_stale_accepted_notary_results(self):
        output = self.work / "notes.md"
        result = subprocess.run([str(ROOT / "scripts/generate_release_notes.sh"), "dist-verified", str(output)],
                                env=dict(self.env, RELEASE_NOTARIZED="0", APP_NOTARY_STATUS="Accepted",
                                         DMG_NOTARY_STATUS="Accepted"), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        notes = output.read_text()
        self.assertIn("unnotarized", notes.lower())
        self.assertNotIn("Accepted", notes)
        self.assertNotIn("Gatekeeper validation: accepted", notes)


if __name__ == "__main__":
    unittest.main()
