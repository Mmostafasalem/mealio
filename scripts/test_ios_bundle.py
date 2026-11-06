"""Regression checks for the release resource boundary; no real secrets used."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import shutil
import plistlib


class BundleBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bundle = Path(self.temp.name) / "Mealio.app"
        self.bundle.mkdir()
        for name in ("Info.plist", "Privacy.md", "Support.md"):
            (self.bundle / name).write_text("fixture")
        source = Path(__file__).resolve().parent.parent / "smartmarket/PrivacyInfo.xcprivacy"
        shutil.copyfile(source, self.bundle / "PrivacyInfo.xcprivacy")

    def check_bundle(self, *options):
        return subprocess.run(
            [sys.executable, str(Path(__file__).with_name("check-ios-bundle.py")), str(self.bundle), *options],
            capture_output=True, text=True,
        )

    def test_clean_bundle_passes(self):
        self.assertEqual(self.check_bundle().returncode, 0)

    def test_release_configuration_requires_a_real_key_without_printing_it(self):
        for key in ("", "$(API_KEY)", "private-but-short"):
            (self.bundle / "Info.plist").write_bytes(plistlib.dumps({"API_KEY":key,"API_BASE_URL":"https://example.test"}))
            result=self.check_bundle("--release-config")
            self.assertNotEqual(result.returncode,0)
            if key: self.assertNotIn(key,result.stdout+result.stderr)

    def test_release_configuration_accepts_key_and_https(self):
        (self.bundle / "Info.plist").write_bytes(plistlib.dumps({"API_KEY":"s"*64,"API_BASE_URL":"https://example.test"}))
        self.assertEqual(self.check_bundle("--release-config").returncode,0)

    def test_release_configuration_rejects_cleartext_endpoint(self):
        (self.bundle / "Info.plist").write_bytes(plistlib.dumps({"API_KEY":"s"*64,"API_BASE_URL":"http://example.test"}))
        self.assertNotEqual(self.check_bundle("--release-config").returncode,0)

    def test_environment_variants_are_rejected(self):
        for name in (".env.production", ".env.local", ".env.staging"):
            with self.subTest(name=name):
                path = self.bundle / name
                path.write_text("SYNTHETIC_SECRET=never-print-this-value")
                result = self.check_bundle()
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("never-print-this-value", result.stdout + result.stderr)
                path.unlink()

    def test_nested_backend_and_build_files_are_rejected(self):
        nested = self.bundle / "Resources"
        nested.mkdir()
        for name in ("server.py", "module.pyc", "Secrets.xcconfig", "deals_data.json", "CACHEDIR.TAG", "nodeids"):
            with self.subTest(name=name):
                path = nested / name
                path.write_text("fixture")
                self.assertNotEqual(self.check_bundle().returncode, 0)
                path.unlink()

    def test_missing_offline_policy_is_rejected(self):
        (self.bundle / "Privacy.md").unlink()
        self.assertNotEqual(self.check_bundle().returncode, 0)

    def test_missing_privacy_manifest_is_rejected(self):
        (self.bundle / "PrivacyInfo.xcprivacy").unlink()
        self.assertNotEqual(self.check_bundle().returncode, 0)

    def test_outdated_privacy_manifest_is_rejected(self):
        for contents in (b"not a plist", plistlib.dumps({})):
            with self.subTest(contents=contents[:20]):
                (self.bundle / "PrivacyInfo.xcprivacy").write_bytes(contents)
                self.assertNotEqual(self.check_bundle().returncode, 0)


if __name__ == "__main__":
    unittest.main()
