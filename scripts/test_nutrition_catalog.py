"""Checks the generated catalog against source provenance and serving units."""
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
class NutritionImportTests(unittest.TestCase):
    def test_catalog_is_sourced_and_complete(self):
        path = ROOT / 'smartmarket/Resources/NutritionCatalog.json'
        self.assertTrue(path.exists(), 'A sourced USDA catalog must replace the logger constants')
        data = json.loads(path.read_text())
        self.assertGreater(len(data['foods']), 7000)
        self.assertEqual(len({f['id'] for f in data['foods']}), len(data['foods']))
        self.assertEqual(len(data['archiveSHA256']), 64)
        self.assertTrue(data['sourceURL'].startswith('https://fdc.nal.usda.gov/'))
        for f in data['foods']:
            self.assertTrue(f['id'].startswith('usda:'))
            self.assertEqual(f['basis'], 'g')
            for k in ['kcal', 'protein', 'carbs', 'fat']:
                self.assertGreaterEqual(f[k], 0)
        chicken = [f for f in data['foods'] if 'chicken' in f['name'].lower() and 'breast' in f['name'].lower()]
        self.assertTrue(any('raw' in f['name'].lower() for f in chicken))
        self.assertTrue(any('cooked' in f['name'].lower() for f in chicken))
    def test_global_reference_sources_include_prepared_dishes(self):
        data = json.loads((ROOT / 'smartmarket/Resources/NutritionCatalog.json').read_text())
        self.assertGreater(len(data['foods']), 13000)
        datasets = {f.get('dataset', 'srLegacy') for f in data['foods']}
        self.assertEqual(datasets, {'srLegacy', 'foundation', 'survey'})
        survey = [f for f in data['foods'] if f.get('dataset') == 'survey']
        self.assertTrue(any('falafel' in f['name'].lower() for f in survey))
        self.assertTrue(any('restaurant' in f['name'].lower() for f in survey))
        self.assertEqual(len(data['sources']), 3)

if __name__ == '__main__': unittest.main()
