"""Regression checks for the release resource boundary; no real secrets used."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class BundleBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bundle = Path(self.temp.name) / "Mealio.app"
        self.bundle.mkdir()
        for name in ("Info.plist", "Privacy.md", "Support.md"):
            (self.bundle / name).write_text("fixture")

    def check_bundle(self):
        return subprocess.run(
            [sys.executable, str(Path(__file__).with_name("check-ios-bundle.py")), str(self.bundle)],
            capture_output=True, text=True,
        )

    def test_clean_bundle_passes(self):
        self.assertEqual(self.check_bundle().returncode, 0)

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


if __name__ == "__main__":
    unittest.main()
