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

    def test_regional_dishes_are_calculated_not_typed_in(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('regional', ROOT / 'scripts/build-regional-dishes.py')
        regional = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(regional)
        path = ROOT / 'smartmarket/Resources/RegionalDishes.json'
        committed = json.loads(path.read_text())
        # The committed file is exactly what the script builds from the recipes and the USDA catalogue.
        self.assertEqual(regional.build(), committed['foods'])
        catalog = {f['sourceID']: f for f in json.loads((ROOT / 'smartmarket/Resources/NutritionCatalog.json').read_text())['foods']}
        self.assertGreaterEqual(len(committed['foods']), 40)
        self.assertEqual(len({f['id'] for f in committed['foods']}), len(committed['foods']))
        for f in committed['foods']:
            self.assertEqual(f['source'], 'regional')
            self.assertEqual(f['id'], 'regional:' + f['sourceID'])
            self.assertIn(f['dataset'], {'lithuanian', 'middleEastern'})
            self.assertTrue(f['searchNames'])
            self.assertTrue(f['summary'].startswith('Made with '))
            # Recompute from the recipe written beside the values.
            for nutrient in ['kcal', 'protein', 'carbs', 'fat']:
                total = sum(catalog[i['usda']][nutrient] * i['grams'] / 100 for i in f['recipe'])
                self.assertAlmostEqual(f[nutrient], total * 100 / f['finishedWeightG'], delta=0.06)
        names = ' '.join(f['name'].lower() for f in committed['foods'])
        for dish in ['cepelinai', 'šaltibarščiai', 'kugelis', 'shawarma', 'koshari', 'ful medames', 'kunafa']:
            self.assertIn(dish, names)

if __name__ == '__main__': unittest.main()
