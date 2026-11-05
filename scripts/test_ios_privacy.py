"""Release declarations for Mealio's current online-AI and private-sync scope.

Apple's collected-data values:
https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype
Review these expectations whenever the actual data flows change.
"""
from pathlib import Path
import plistlib
import unittest


class PrivacyDeclarationTests(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).resolve().parent.parent / "smartmarket/PrivacyInfo.xcprivacy"
        self.manifest = plistlib.loads(path.read_bytes())

    def test_current_data_flows_have_valid_separate_categories(self):
        types = {entry["NSPrivacyCollectedDataType"] for entry in self.manifest["NSPrivacyCollectedDataTypes"]}
        self.assertEqual(types, {
            "NSPrivacyCollectedDataTypePreciseLocation",
            "NSPrivacyCollectedDataTypeHealth",
            "NSPrivacyCollectedDataTypeFitness",
            "NSPrivacyCollectedDataTypeOtherUserContent",
        })

    def test_optional_online_content_does_not_claim_anonymity(self):
        entries = {entry["NSPrivacyCollectedDataType"]: entry for entry in self.manifest["NSPrivacyCollectedDataTypes"]}
        for name in ("Health", "Fitness", "OtherUserContent"):
            with self.subTest(category=name):
                self.assertTrue(entries.get("NSPrivacyCollectedDataType" + name, {}).get("NSPrivacyCollectedDataTypeLinked"))
        self.assertFalse(self.manifest["NSPrivacyTracking"])
        self.assertEqual(self.manifest["NSPrivacyTrackingDomains"], [])

    def test_user_defaults_reason_remains_declared(self):
        entries = self.manifest["NSPrivacyAccessedAPITypes"]
        reasons = next(x["NSPrivacyAccessedAPITypeReasons"] for x in entries
                       if x["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryUserDefaults")
        self.assertIn("CA92.1", reasons)


if __name__ == "__main__":
    unittest.main()
