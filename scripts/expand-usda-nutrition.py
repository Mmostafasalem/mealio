"""Append verified official USDA Foundation and FNDDS reference records.
Run the SR Legacy importer first, then this script with the two official JSON ZIPs.
"""
import hashlib
import json
import math
from pathlib import Path
import sys
import zipfile

SOURCES = [
    ('foundation', '2026-10', 'FoundationFoods',
     'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_2026-10-29.zip',
     'dd414cc9f1a132626bad354ef6655972c78b44aff14f16114dc899708663c579'),
    ('survey', '2021-2023', 'SurveyFoods',
     'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip',
     'dfb06ae7ddc397ccd570b91c14b75438ab2ba39f64f22d321f61d4a52a77f3eb'),
]

def records(path, source):
    dataset, date, key, url, checksum = source
    if hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
        raise ValueError('Archive checksum does not match ' + dataset)
    with zipfile.ZipFile(path) as z:
        data = json.loads(z.read(next(n for n in z.namelist() if n.endswith('.json'))))
    result = []
    for food in data[key]:
        values = {str(n['nutrient']['id']): n['amount'] for n in food.get('foodNutrients', []) if 'amount' in n and 'nutrient' in n}
        # Prefer conventional kcal; newer Foundation records use documented Atwater energy IDs.
        energy = next((values[i] for i in ['1008', '2048', '2047'] if i in values), None)
        n = {'kcal': energy, 'protein': values.get('1003'), 'carbs': values.get('1005'), 'fat': values.get('1004')}
        if any(v is None or isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or v < 0 for v in n.values()): continue
        if n['kcal'] > 1000 or any(n[k] > 100 for k in ['protein', 'carbs', 'fat']): continue
        identifier = str(food['fdcId'])
        result.append(dict(id='usda:' + identifier, sourceID=identifier, name=food['description'], brand=None,
                           basis='g', source='usda', sourceDate=date, dataset=dataset, **n))
    return result

if __name__ == '__main__':
    destination = Path(__file__).resolve().parent.parent / 'smartmarket/Resources/NutritionCatalog.json'
    data = json.loads(destination.read_text())
    # Re-running replaces the supplementary datasets rather than duplicating them.
    base = [f for f in data['foods'] if f.get('dataset', 'srLegacy') == 'srLegacy']
    metadata = [dict(dataset='srLegacy', release='2018-04', sourceURL=data['sourceURL'], archiveSHA256=data['archiveSHA256'], count=len(base))]
    for path, source in zip(sys.argv[1:], SOURCES, strict=True):
        added = records(Path(path), source)
        base.extend(added)
        metadata.append(dict(dataset=source[0], release=source[1], sourceURL=source[3], archiveSHA256=source[4], count=len(added)))
        print(source[0], len(added))
    if len({f['id'] for f in base}) != len(base): raise ValueError('Duplicate FDC IDs')
    data['foods'] = sorted(base, key=lambda f: f['name'].casefold())
    data['sources'] = metadata
    data['release'] = 'USDA SR Legacy, Foundation and FNDDS reference foods'
    destination.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n')
    print('Total complete records:',len(base))
