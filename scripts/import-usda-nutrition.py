"""Rebuild the offline catalog from the unmodified official USDA SR Legacy ZIP.
Usage: python3 scripts/import-usda-nutrition.py /path/to/download.zip
No manually entered nutrition values or inferred missing macros are imported.
"""
import csv
import hashlib
import io
import json
import math
from pathlib import Path
import sys
import zipfile

SOURCE = 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip'
EXPECTED_SHA256 = 'b80817294b8850530aaedf2e515c02593b1824f763a0ff356e5c2081643e6fd0'
NUTRIENTS = {'1008': 'kcal', '1003': 'protein', '1005': 'carbs', '1004': 'fat'}

def build(archive):
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    if checksum != EXPECTED_SHA256:
        raise ValueError('Unexpected archive: obtain the official USDA SR Legacy April 2018 ZIP; review source/version before changing this checksum')
    with zipfile.ZipFile(archive) as z:
        def rows(name):
            path = next(p for p in z.namelist() if p.endswith('/' + name))
            return csv.DictReader(io.TextIOWrapper(z.open(path), encoding='utf-8-sig'))
        nutrients = {}
        for r in rows('food_nutrient.csv'):
            key = NUTRIENTS.get(r['nutrient_id'])
            if key and r['amount'].strip():
                value = float(r['amount'])
                if math.isfinite(value) and value >= 0:
                    nutrients.setdefault(r['fdc_id'], {})[key] = value
        foods = []
        for r in rows('food.csv'):
            n = nutrients.get(r['fdc_id'], {})
            if set(n) != set(NUTRIENTS.values()): continue
            if n['kcal'] > 1000 or any(n[k] > 100 for k in ['protein', 'carbs', 'fat']): continue
            foods.append(dict(id='usda:' + r['fdc_id'], name=r['description'],
                              brand=None, basis='g', source='usda', sourceID=r['fdc_id'],
                              sourceDate='2018-04', **n))
    foods.sort(key=lambda f: f['name'].casefold())
    return dict(sourceURL=SOURCE, archiveSHA256=checksum,
                release='USDA SR Legacy April 2018', foods=foods)

if __name__ == '__main__':
    data = build(Path(sys.argv[1]))
    dest = Path(__file__).resolve().parent.parent / 'smartmarket/Resources/NutritionCatalog.json'
    dest.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f"Imported {len(data['foods'])} complete source records to {dest}")
