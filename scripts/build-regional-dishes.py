"""Builds smartmarket/Resources/RegionalDishes.json: dishes the USDA lists lack.

No nutrition value here is typed in by hand. Each dish is a typical home recipe
(ingredient weights and the weight of the finished dish), and its nutrition per
100 g is the sum of its ingredients' values from the bundled USDA catalogue
divided by that finished weight, the same method the app uses for a person's
own recipes. The recipes are Nourlo's; cooks vary, so the app labels the
result an estimate.

Run again after editing DISHES or the USDA catalogue:  python3 scripts/build-regional-dishes.py
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / 'smartmarket/Resources/NutritionCatalog.json'
OUTPUT = ROOT / 'smartmarket/Resources/RegionalDishes.json'

# USDA records used as ingredients: short key -> (FoodData Central id, the record's exact name).
# The name is checked against the catalogue, so a changed id can never slip through.
I = {
    'potato_raw': ('170026', 'Potatoes, flesh and skin, raw'),
    'potato_boiled': ('170440', 'Potatoes, boiled, cooked without skin, flesh, without salt'),
    'pork_ground': ('2514745', 'Pork, ground, raw'),
    'beef_ground': ('2705853', 'Beef, ground, raw'),
    'beef_chuck': ('2646174', 'Beef, chuck, roast, boneless, choice, raw'),
    'beef_stew': ('171206', 'Beef, chuck for stew, separable lean and fat, all grades, raw'),
    'lamb_ground': ('174370', 'Lamb, ground, raw'),
    'lamb_leg': ('174315', 'Lamb, leg, shank half, separable lean and fat, trimmed to 1/4" fat, choice, raw'),
    'chicken_thigh': ('2646171', 'Chicken, thigh, boneless, skinless, raw'),
    'chicken_breast': ('2646170', 'Chicken, breast, boneless, skinless, raw'),
    'bacon': ('2705890', 'Bacon or side pork, fresh, cooked'),
    'bologna': ('2706176', 'Bologna'),
    'egg': ('171287', 'Egg, whole, raw, fresh'),
    'egg_boiled': ('173424', 'Egg, whole, cooked, hard-boiled'),
    'milk': ('171265', 'Milk, whole, 3.25% milkfat, with added vitamin D'),
    'kefir': ('2705394', 'Kefir'),
    'yogurt': ('171284', 'Yogurt, plain, whole milk'),
    'sour_cream': ('2705614', 'Sour cream, regular'),
    'butter': ('173410', 'Butter, salted'),
    'farmer_cheese': ('2705749', "Cottage cheese, farmer's"),
    'mozzarella': ('170845', 'Cheese, mozzarella, whole milk'),
    'condensed_milk': ('171275', 'Milk, canned, condensed, sweetened'),
    'flour': ('169761', 'Wheat flour, white, all-purpose, unenriched'),
    'semolina': ('168933', 'Semolina, unenriched'),
    'phyllo': ('172791', 'Phyllo dough'),
    'pita': ('174915', 'Bread, pita, white, enriched'),
    'rye_bread': ('172684', 'Bread, rye'),
    'white_bread': ('174924', 'Bread, white, commercially prepared (includes soft bread crumbs)'),
    'butter_cookies': ('174950', 'Cookies, butter, commercially prepared, enriched'),
    'rice_raw': ('2512381', 'Rice, white, long grain, unenriched, raw'),
    'rice_cooked': ('2708408', 'Rice, white, cooked, no added fat'),
    'pasta_cooked': ('2708357', 'Pasta, cooked'),
    'bulgur_cooked': ('170287', 'Bulgur, cooked'),
    'buckwheat_cooked': ('170686', 'Buckwheat groats, roasted, cooked'),
    'lentils_cooked': ('172421', 'Lentils, mature seeds, cooked, boiled, without salt'),
    'chickpeas_cooked': ('173757', 'Chickpeas (garbanzo beans, bengal gram), mature seeds, cooked, boiled, without salt'),
    'fava_cooked': ('2707367', 'Fava beans, cooked'),
    'tahini': ('170189', 'Seeds, sesame butter, tahini, from roasted and toasted kernels (most common type)'),
    'sesame': ('170150', 'Seeds, sesame seeds, whole, dried'),
    'pine_nuts': ('170591', 'Nuts, pine nuts, dried'),
    'almonds': ('2346393', 'Nuts, almonds, whole, raw'),
    'coconut': ('170170', 'Nuts, coconut meat, dried (desiccated), not sweetened'),
    'olive_oil': ('171413', 'Oil, olive, salad or cooking'),
    'sunflower_oil': ('171025', 'Oil, sunflower, linoleic, (approx. 65%)'),
    'mayonnaise': ('171009', 'Salad dressing, mayonnaise, regular'),
    'sugar': ('169655', 'Sugars, granulated'),
    'cocoa': ('169593', 'Cocoa, dry powder, unsweetened'),
    'onion': ('170000', 'Onions, raw'),
    'spring_onion': ('170005', 'Onions, spring or scallions (includes tops and bulb), raw'),
    'garlic': ('169230', 'Garlic, raw'),
    'carrot': ('170393', 'Carrots, raw'),
    'carrot_boiled': ('170394', 'Carrots, cooked, boiled, drained, without salt'),
    'cabbage': ('169975', 'Cabbage, raw'),
    'beets_boiled': ('169146', 'Beets, cooked, boiled, drained'),
    'cucumber': ('2709784', 'Cucumber, raw'),
    'pickles': ('168558', 'Pickles, cucumber, dill or kosher dill'),
    'peas': ('170104', 'Peas, green, canned, no salt added, drained solids'),
    'tomato': ('170457', 'Tomatoes, red, ripe, raw, year round average'),
    'tomato_sauce': ('169074', 'Tomato sauce, canned, no salt added'),
    'tomato_paste': ('2685580', 'Tomato, paste, canned, without salt added'),
    'green_pepper': ('170427', 'Peppers, sweet, green, raw'),
    'eggplant': ('169228', 'Eggplant, raw'),
    'eggplant_cooked': ('2709929', 'Eggplant, cooked, no added fat'),
    'zucchini': ('169291', 'Squash, summer, zucchini, includes skin, raw'),
    'okra': ('169260', 'Okra, raw'),
    'spinach': ('168462', 'Spinach, raw'),
    'romaine': ('169247', 'Lettuce, cos or romaine, raw'),
    'jute_cooked': ('168420', 'Jute, potherb, cooked, boiled, drained, without salt'),
    'parsley': ('170416', 'Parsley, fresh'),
    'mint': ('173475', 'Spearmint, fresh'),
    'dill': ('172233', 'Dill weed, fresh'),
    'lemon_juice': ('167747', 'Lemon juice, raw'),
    'thyme': ('170938', 'Spices, thyme, dried'),
    'cumin': ('170923', 'Spices, cumin seed'),
    'yeast': ('2710005', 'Yeast'),
    'chicken_stock': ('172884', 'Soup, stock, chicken, home-prepared'),
    'falafel': ('172455', 'Falafel, home-prepared'),
    'salt': ('173468', 'Salt, table'),
    'water': ('2710707', 'Water, tap'),
}

LT, ME = 'lithuanian', 'middleEastern'

# (slug, name, cuisine, other names people search by, {ingredient: grams}, finished weight in grams, how the weight was reached)
DISHES = [
    # ---- Lithuanian ----
    ('cepelinai-meat', 'Cepelinai, potato dumplings with meat, with bacon and sour cream sauce', LT,
     ['cepelinai', 'cepelinai su mėsa', 'didžkukuliai', 'zeppelins'],
     {'potato_raw': 1000, 'potato_boiled': 250, 'pork_ground': 300, 'onion': 100, 'bacon': 80, 'sour_cream': 120, 'salt': 8},
     1500, 'Grated potato is squeezed (about 300 g of liquid goes, the starch is returned); the pork cooks inside the dumpling.'),
    ('cepelinai-curd', 'Cepelinai, potato dumplings with curd cheese, with sour cream and butter', LT,
     ['cepelinai su varške', 'varškės cepelinai', 'didžkukuliai su varške'],
     {'potato_raw': 1000, 'potato_boiled': 250, 'farmer_cheese': 300, 'egg': 50, 'sour_cream': 150, 'butter': 30, 'salt': 8},
     1480, 'Grated potato is squeezed, as for the meat version.'),
    ('saltibarsciai', 'Šaltibarščiai, cold beet soup with kefir', LT,
     ['saltibarsciai', 'šaltibarščiai', 'cold beet soup', 'pink soup', 'cold borscht', 'lithuanian cold soup'],
     {'kefir': 1000, 'beets_boiled': 300, 'cucumber': 200, 'egg_boiled': 100, 'spring_onion': 30, 'dill': 15, 'salt': 6},
     1650, 'Nothing is cooked: the finished weight is the sum of what goes in. Potatoes served alongside are not included.'),
    ('kugelis', 'Kugelis, baked potato pudding with bacon', LT,
     ['kugelis', 'bulvių plokštainis', 'plokštainis', 'potato pudding', 'potato kugel'],
     {'potato_raw': 1500, 'bacon': 150, 'onion': 150, 'egg': 150, 'milk': 200, 'salt': 12},
     1700, 'Baked for about 90 minutes; roughly a fifth of the weight leaves as steam.'),
    ('bulviniai-blynai', 'Bulviniai blynai, fried potato pancakes', LT,
     ['bulviniai blynai', 'potato pancakes', 'tarkainiai', 'draniki'],
     {'potato_raw': 1000, 'onion': 80, 'egg': 50, 'flour': 40, 'sunflower_oil': 60, 'salt': 8},
     940, 'About a quarter of the batter weight leaves as steam; 60 g of oil is what the pancakes keep.'),
    ('zemaiciu-blynai', 'Žemaičių blynai, potato pancakes filled with meat', LT,
     ['zemaiciu blynai', 'žemaičių blynai', 'samogitian pancakes'],
     {'potato_boiled': 1000, 'egg': 50, 'flour': 60, 'pork_ground': 300, 'onion': 80, 'sunflower_oil': 50, 'salt': 8},
     1400, 'Made from boiled potato, so little water is lost; the pork loses about a fifth while it is fried.'),
    ('koldunai', 'Koldūnai, boiled dumplings with meat, with butter', LT,
     ['koldunai', 'koldūnai', 'koldūnai su mėsa', 'lithuanian dumplings', 'pelmeni'],
     {'flour': 300, 'egg': 50, 'water': 120, 'pork_ground': 200, 'beef_ground': 150, 'onion': 50, 'butter': 20, 'salt': 8},
     890, 'The dough takes up a little cooking water; the meat loses about a fifth.'),
    ('kibinai', 'Kibinai, baked pastries with lamb', LT,
     ['kibinai', 'kibinas', 'karaim pastry', 'kybyn'],
     {'flour': 500, 'butter': 200, 'sour_cream': 150, 'egg': 50, 'lamb_leg': 600, 'onion': 150, 'salt': 12},
     1450, 'Baked; about an eighth of the weight leaves as steam.'),
    ('balandeliai', 'Balandėliai, cabbage rolls with meat and rice in tomato sauce', LT,
     ['balandeliai', 'balandėliai', 'stuffed cabbage rolls', 'cabbage rolls', 'golubtsy'],
     {'cabbage': 800, 'pork_ground': 250, 'beef_ground': 250, 'rice_raw': 100, 'onion': 100, 'carrot': 100,
      'tomato_sauce': 300, 'sour_cream': 100, 'sunflower_oil': 20, 'water': 300, 'salt': 12},
     1950, 'Simmered covered; about a sixth of the weight evaporates. The sauce is included.'),
    ('varskeciai', 'Varškėčiai, fried curd cheese pancakes', LT,
     ['varskeciai', 'varškėčiai', 'curd pancakes', 'syrniki', 'cottage cheese pancakes'],
     {'farmer_cheese': 500, 'egg': 100, 'flour': 80, 'sugar': 40, 'sunflower_oil': 30},
     680, 'About a tenth of the batter weight leaves as steam; 30 g of oil is kept.'),
    ('varskes-spurgos', 'Varškės spurgos, fried curd cheese doughnuts', LT,
     ['varskes spurgos', 'varškės spurgos', 'curd doughnuts', 'spurgos'],
     {'farmer_cheese': 400, 'flour': 250, 'egg': 100, 'sugar': 60, 'sunflower_oil': 70},
     815, 'Deep fried: a little water leaves and about 70 g of oil is taken up.'),
    ('lietiniai', 'Lietiniai, thin pancakes, plain', LT,
     ['lietiniai', 'lietiniai blynai', 'thin pancakes', 'crepes', 'blynai'],
     {'flour': 250, 'milk': 500, 'egg': 150, 'sugar': 15, 'sunflower_oil': 30, 'butter': 20},
     680, 'Thin batter loses about 30% of its weight on the pan.'),
    ('lietiniai-varske', 'Lietiniai su varške, thin pancakes filled with curd cheese', LT,
     ['lietiniai su varške', 'lietiniai su varske', 'curd crepes', 'pancakes with curd'],
     {'flour': 250, 'milk': 500, 'egg': 150, 'sugar': 55, 'sunflower_oil': 30, 'butter': 20, 'farmer_cheese': 400, 'sour_cream': 50},
     1170, 'The pancakes as above, plus an uncooked curd filling.'),
    ('kotletai', 'Kotletai, fried pork patties', LT,
     ['kotletai', 'kiaulienos kotletai', 'meat patties', 'cutlets', 'maltinukai'],
     {'pork_ground': 500, 'onion': 80, 'egg': 50, 'white_bread': 50, 'milk': 50, 'sunflower_oil': 25, 'salt': 8},
     595, 'Fried; a little over a fifth of the weight is lost, and about 25 g of oil is kept.'),
    ('troskinti-kopustai', 'Troškinti kopūstai, braised cabbage', LT,
     ['troskinti kopustai', 'troškinti kopūstai', 'braised cabbage', 'stewed cabbage'],
     {'cabbage': 1000, 'onion': 100, 'carrot': 100, 'sunflower_oil': 30, 'tomato_paste': 30, 'water': 100, 'salt': 10},
     1000, 'Braised until soft; roughly a quarter of the weight evaporates.'),
    ('grikiu-kose', 'Grikių košė, buckwheat porridge with butter', LT,
     ['grikiu kose', 'grikių košė', 'grikiai su sviestu', 'buckwheat porridge', 'kasha'],
     {'buckwheat_cooked': 500, 'butter': 25, 'salt': 3},
     528, 'Cooked buckwheat with butter stirred in.'),
    ('balta-misraine', 'Balta mišrainė, potato salad with peas, egg, sausage and mayonnaise', LT,
     ['balta misraine', 'balta mišrainė', 'mišrainė', 'olivier salad', 'russian salad', 'potato salad lithuanian'],
     {'potato_boiled': 400, 'carrot_boiled': 150, 'peas': 150, 'pickles': 150, 'egg_boiled': 150, 'bologna': 150, 'mayonnaise': 150, 'salt': 4},
     1300, 'Nothing is cooked after mixing: the finished weight is the sum of what goes in.'),
    ('kepta-duona', 'Kepta duona, fried rye bread with garlic', LT,
     ['kepta duona', 'kepta duona su česnaku', 'fried bread', 'fried rye bread', 'garlic bread lithuanian'],
     {'rye_bread': 300, 'sunflower_oil': 50, 'garlic': 15, 'salt': 3},
     335, 'The bread dries a little and keeps about 50 g of oil. A cheese sauce is not included.'),
    ('tinginys', 'Tinginys, no-bake cocoa and biscuit cake', LT,
     ['tinginys', 'lazy cake', 'lithuanian lazy cake', 'chocolate salami'],
     {'butter_cookies': 400, 'condensed_milk': 380, 'butter': 150, 'cocoa': 30},
     960, 'Not baked: the finished weight is the sum of what goes in.'),

    # ---- Middle Eastern ----
    ('shawarma-chicken', 'Shawarma, chicken, meat only', ME,
     ['chicken shawarma', 'shawarma', 'shawerma', 'شاورما دجاج', 'شاورما', 'شاورما فراخ'],
     {'chicken_thigh': 1000, 'yogurt': 100, 'olive_oil': 30, 'lemon_juice': 30, 'garlic': 20, 'cumin': 10, 'salt': 12},
     740, 'Roasted: chicken thigh keeps about 70% of its raw weight, plus the marinade that clings.'),
    ('shawarma-beef', 'Shawarma, beef, meat only', ME,
     ['beef shawarma', 'meat shawarma', 'شاورما لحم', 'شاورما لحمة'],
     {'beef_stew': 1000, 'olive_oil': 30, 'lemon_juice': 30, 'garlic': 20, 'cumin': 10, 'salt': 12},
     700, 'Roasted: trimmed beef keeps about two thirds of its raw weight.'),
    ('shawarma-chicken-wrap', 'Shawarma wrap, chicken, in pita with garlic yogurt sauce and pickles', ME,
     ['chicken shawarma wrap', 'shawarma sandwich', 'shawarma wrap', 'ساندويتش شاورما', 'سندويش شاورما', 'شاورما عربي'],
     {'chicken_thigh': 205, 'yogurt': 50, 'olive_oil': 6, 'lemon_juice': 6, 'garlic': 7, 'cumin': 2, 'pita': 80, 'pickles': 30, 'tomato': 30, 'salt': 3},
     323, 'One wrap: 150 g of roasted chicken, an 80 g pita, sauce and vegetables.'),
    ('shish-tawook', 'Shish tawook, grilled marinated chicken skewers', ME,
     ['shish tawook', 'shish taouk', 'tawook', 'شيش طاووق', 'شيش طاوق'],
     {'chicken_breast': 1000, 'yogurt': 150, 'olive_oil': 30, 'lemon_juice': 40, 'garlic': 20, 'tomato_paste': 20, 'salt': 12},
     760, 'Grilled: chicken breast keeps a little over 70% of its raw weight, plus the marinade that clings.'),
    ('kofta', 'Kofta, grilled minced beef and lamb', ME,
     ['kofta', 'kafta', 'kofta kebab', 'كفتة', 'كفته', 'كفتة مشوية'],
     {'beef_ground': 700, 'lamb_ground': 300, 'onion': 120, 'parsley': 40, 'cumin': 6, 'salt': 14},
     840, 'Grilled: the mince loses a little over a quarter of its weight.'),
    ('koshari', 'Koshari, rice, lentils and pasta with tomato sauce and fried onions', ME,
     ['koshari', 'kushari', 'koshary', 'كشري', 'كشرى'],
     {'rice_cooked': 300, 'lentils_cooked': 200, 'pasta_cooked': 200, 'chickpeas_cooked': 80, 'tomato_sauce': 250,
      'garlic': 10, 'onion': 150, 'sunflower_oil': 30, 'salt': 6},
     1120, 'Assembled from cooked parts; the onions lose about half their weight when fried.'),
    ('ful-medames', 'Ful medames, stewed fava beans with olive oil and lemon', ME,
     ['ful medames', 'ful', 'foul', 'fava beans egyptian', 'فول مدمس', 'فول'],
     {'fava_cooked': 500, 'olive_oil': 30, 'lemon_juice': 30, 'garlic': 10, 'cumin': 4, 'tomato': 60, 'parsley': 10, 'salt': 5},
     645, 'Cooked beans dressed at the table: the finished weight is the sum of what goes in.'),
    ('mujaddara', 'Mujaddara, lentils and rice with caramelised onions', ME,
     ['mujaddara', 'mujadara', 'mjadra', 'مجدرة', 'مجدره'],
     {'lentils_cooked': 400, 'rice_cooked': 400, 'onion': 300, 'olive_oil': 50, 'cumin': 4, 'salt': 8},
     990, 'The onions lose over half their weight as they caramelise.'),
    ('tabbouleh', 'Tabbouleh, parsley and bulgur salad', ME,
     ['tabbouleh', 'tabouli', 'tabbouli', 'تبولة', 'تبوله'],
     {'parsley': 150, 'bulgur_cooked': 120, 'tomato': 250, 'spring_onion': 40, 'mint': 15, 'olive_oil': 50, 'lemon_juice': 50, 'salt': 5},
     680, 'A salad: the finished weight is the sum of what goes in.'),
    ('fattoush', 'Fattoush, mixed salad with toasted pita', ME,
     ['fattoush', 'fatoush', 'فتوش'],
     {'tomato': 250, 'cucumber': 250, 'romaine': 150, 'green_pepper': 80, 'spring_onion': 40, 'parsley': 20, 'mint': 10,
      'pita': 80, 'olive_oil': 50, 'lemon_juice': 40, 'salt': 5},
     970, 'A salad: the finished weight is the sum of what goes in.'),
    ('baba-ghanoush', 'Baba ghanoush, roasted eggplant dip with tahini', ME,
     ['baba ghanoush', 'baba ganoush', 'mutabbal', 'moutabal', 'بابا غنوج', 'متبل'],
     {'eggplant_cooked': 500, 'tahini': 80, 'lemon_juice': 40, 'garlic': 10, 'olive_oil': 25, 'salt': 5},
     660, 'Made from already roasted eggplant: the finished weight is the sum of what goes in.'),
    ('tahini-sauce', 'Tahini sauce, tarator', ME,
     ['tahini sauce', 'tarator', 'طحينة', 'صلصة طحينة', 'طرطور'],
     {'tahini': 100, 'water': 100, 'lemon_juice': 40, 'garlic': 5, 'salt': 3},
     248, 'Stirred together: the finished weight is the sum of what goes in.'),
    ('toum', 'Toum, garlic sauce', ME,
     ['toum', 'garlic sauce', 'toumeya', 'ثوم', 'ثومية', 'تومية'],
     {'garlic': 100, 'sunflower_oil': 400, 'lemon_juice': 60, 'salt': 6},
     566, 'An emulsion: the finished weight is the sum of what goes in.'),
    ('shakshuka', 'Shakshuka, eggs poached in tomato and pepper sauce', ME,
     ['shakshuka', 'shakshouka', 'شكشوكة', 'شكشوكه'],
     {'tomato': 600, 'tomato_sauce': 200, 'onion': 120, 'green_pepper': 150, 'olive_oil': 40, 'garlic': 10, 'egg': 300, 'cumin': 3, 'salt': 8},
     1150, 'The sauce simmers down by about a fifth before the eggs go in.'),
    ('manakish-zaatar', "Manakish, flatbread with za'atar and olive oil", ME,
     ['manakish', 'manaeesh', 'manakeesh', 'zaatar bread', "za'atar manakish", 'مناقيش', 'مناقيش زعتر', 'منقوشة'],
     {'flour': 500, 'water': 300, 'yeast': 7, 'olive_oil': 90, 'thyme': 20, 'sesame': 20, 'salt': 10},
     800, 'Baked; about 15% of the weight leaves as steam.'),
    ('sfiha', 'Sfiha, open meat pies with lamb', ME,
     ['sfiha', 'sfeeha', 'lahm bi ajeen', 'meat pies', 'صفيحة', 'لحم بعجين'],
     {'flour': 500, 'water': 290, 'yeast': 7, 'olive_oil': 30, 'lamb_ground': 400, 'tomato': 200, 'onion': 150, 'pine_nuts': 20, 'salt': 12},
     1260, 'Baked: the dough loses about 13% and the topping about 30%.'),
    ('fatayer-spinach', 'Fatayer, spinach pies', ME,
     ['fatayer', 'spinach fatayer', 'spinach pies', 'فطاير سبانخ', 'فطائر سبانخ', 'فطاير'],
     {'flour': 500, 'water': 290, 'yeast': 7, 'olive_oil': 90, 'spinach': 600, 'onion': 150, 'lemon_juice': 40, 'salt': 12},
     1210, 'Baked: the spinach wilts to about half its weight before filling.'),
    ('kibbeh', 'Kibbeh, fried bulgur and lamb croquettes', ME,
     ['kibbeh', 'kubbeh', 'kibbe', 'كبة', 'كبه', 'كبة مقلية'],
     {'bulgur_cooked': 400, 'lamb_ground': 500, 'onion': 120, 'pine_nuts': 30, 'sunflower_oil': 60, 'cumin': 4, 'salt': 12},
     950, 'Deep fried: about 15% of the weight is lost and about 60 g of oil is taken up.'),
    ('hawawshi', 'Hawawshi, pita baked with spiced minced beef', ME,
     ['hawawshi', 'hawaoshi', 'حواوشي', 'حواوشى'],
     {'pita': 400, 'beef_ground': 500, 'onion': 150, 'green_pepper': 80, 'cumin': 5, 'salt': 10},
     965, 'Baked: the filling loses about a fifth of its weight, the bread very little.'),
    ('kabsa', 'Kabsa, spiced rice with chicken', ME,
     ['kabsa', 'kabsah', 'machboos', 'كبسة', 'كبسه', 'كبسة دجاج'],
     {'chicken_thigh': 800, 'rice_raw': 400, 'onion': 150, 'tomato': 200, 'carrot': 100, 'sunflower_oil': 40, 'water': 900, 'cumin': 6, 'salt': 14},
     2060, 'The rice takes up about 1.8 times its weight in water; the chicken keeps about three quarters of its weight.'),
    ('mansaf', 'Mansaf, lamb with rice and yogurt sauce', ME,
     ['mansaf', 'منسف'],
     {'lamb_leg': 1000, 'rice_raw': 400, 'yogurt': 500, 'butter': 40, 'almonds': 30, 'pine_nuts': 20, 'pita': 100, 'water': 900, 'salt': 14},
     2360, 'The lamb keeps about 65% of its weight, the rice takes up water and the yogurt sauce reduces a little.'),
    ('maqluba', 'Maqluba, upside-down rice with chicken and eggplant', ME,
     ['maqluba', 'makloubeh', 'maqlooba', 'مقلوبة', 'مقلوبه'],
     {'eggplant': 500, 'sunflower_oil': 60, 'chicken_thigh': 600, 'rice_raw': 400, 'onion': 100, 'water': 900, 'cumin': 5, 'salt': 14},
     2030, 'The eggplant is fried first and keeps about 60 g of oil; the rice takes up water.'),
    ('mahshi-zucchini', 'Mahshi, zucchini stuffed with rice and minced beef in tomato sauce', ME,
     ['mahshi', 'mahshi kousa', 'stuffed zucchini', 'kousa mahshi', 'محشي', 'محشي كوسة', 'كوسا محشي'],
     {'zucchini': 1000, 'rice_raw': 200, 'beef_ground': 250, 'tomato_sauce': 300, 'onion': 80, 'water': 300, 'salt': 12},
     1900, 'Simmered covered; the rice takes up the cooking liquid and about a tenth evaporates.'),
    ('bamia', 'Bamia, okra and beef stew in tomato sauce', ME,
     ['bamia', 'bamya', 'okra stew', 'بامية', 'باميه', 'بامية باللحم'],
     {'okra': 500, 'beef_chuck': 400, 'tomato_sauce': 300, 'onion': 100, 'garlic': 10, 'sunflower_oil': 30, 'water': 300, 'salt': 10},
     1400, 'Simmered about an hour; roughly 15% of the weight evaporates.'),
    ('mesaqaa', "Mesaqa'a, fried eggplant baked with minced beef and tomato", ME,
     ['mesaqaa', "mesaqa'a", 'moussaka egyptian', 'musaqaa', 'مسقعة', 'مسقعه'],
     {'eggplant': 800, 'sunflower_oil': 80, 'beef_ground': 300, 'tomato_sauce': 400, 'onion': 100, 'green_pepper': 100, 'garlic': 10, 'salt': 10},
     1400, 'The eggplant loses about a third when fried and keeps about 80 g of oil; then everything is baked.'),
    ('molokhia', 'Molokhia, jute leaf soup', ME,
     ['molokhia', 'mulukhiyah', 'molokhiya', 'ملوخية', 'ملوخيه'],
     {'jute_cooked': 400, 'chicken_stock': 600, 'garlic': 20, 'butter': 30, 'salt': 6},
     1040, 'The soup only: chicken or rice served with it is not included.'),
    ('falafel-wrap', 'Falafel wrap, in pita with tahini sauce and salad', ME,
     ['falafel wrap', 'taameya sandwich', 'ساندويتش فلافل', 'سندويش فلافل', 'ساندويتش طعمية'],
     {'falafel': 150, 'pita': 80, 'tahini': 15, 'water': 15, 'lemon_juice': 5, 'tomato': 40, 'cucumber': 40, 'pickles': 20},
     365, 'One wrap: the finished weight is the sum of what goes in.'),
    ('kunafa', 'Kunafa, shredded pastry with cheese and sugar syrup', ME,
     ['kunafa', 'knafeh', 'konafa', 'kunefe', 'كنافة', 'كنافه', 'كنافة بالجبن'],
     {'phyllo': 500, 'butter': 250, 'mozzarella': 500, 'sugar': 300, 'water': 200},
     1530, 'Calculated with phyllo for the kataifi pastry and mozzarella for the usual akkawi or nabulsi cheese; the syrup is reduced before pouring.'),
    ('basbousa', 'Basbousa, semolina cake with sugar syrup', ME,
     ['basbousa', 'basbosa', 'namoura', 'harissa cake', 'بسبوسة', 'بسبوسه', 'نمورة'],
     {'semolina': 400, 'sugar': 400, 'yogurt': 250, 'butter': 150, 'coconut': 50, 'water': 250},
     1280, 'Baked, losing about an eighth of the batter weight, then soaked with reduced syrup.'),
]

SLUG = re.compile(r'^[a-z0-9]+(-[a-z0-9]+)*$')
READABLE = {  # how an ingredient is named in the short "made with" line
    'potato_raw': 'potatoes', 'potato_boiled': 'potatoes', 'pork_ground': 'pork', 'beef_ground': 'beef', 'beef_chuck': 'beef', 'beef_stew': 'beef',
    'lamb_ground': 'lamb', 'lamb_leg': 'lamb', 'chicken_thigh': 'chicken', 'chicken_breast': 'chicken', 'egg_boiled': 'egg',
    'sour_cream': 'sour cream', 'farmer_cheese': 'curd cheese', 'condensed_milk': 'condensed milk', 'rye_bread': 'rye bread',
    'white_bread': 'bread', 'butter_cookies': 'butter biscuits', 'rice_raw': 'rice', 'rice_cooked': 'rice', 'pasta_cooked': 'pasta',
    'bulgur_cooked': 'bulgur', 'buckwheat_cooked': 'buckwheat', 'lentils_cooked': 'lentils', 'chickpeas_cooked': 'chickpeas',
    'fava_cooked': 'fava beans', 'pine_nuts': 'pine nuts', 'olive_oil': 'olive oil', 'sunflower_oil': 'oil', 'spring_onion': 'spring onion',
    'carrot_boiled': 'carrot', 'beets_boiled': 'beets', 'tomato_sauce': 'tomato sauce', 'tomato_paste': 'tomato paste',
    'green_pepper': 'green pepper', 'eggplant_cooked': 'eggplant', 'jute_cooked': 'jute leaves', 'lemon_juice': 'lemon juice',
    'chicken_stock': 'chicken stock', 'romaine': 'lettuce', 'phyllo': 'pastry', 'sesame': 'sesame seeds', 'thyme': "za'atar thyme",
}
SILENT = {'salt', 'water', 'yeast', 'cumin'}


def build():
    catalog = {f['sourceID']: f for f in json.loads(CATALOG.read_text())['foods']}
    for key, (identifier, name) in I.items():
        record = catalog.get(identifier)
        if record is None or record['name'] != name:
            raise SystemExit(f'Ingredient {key}: USDA record {identifier} is missing or is no longer "{name}"')
        if record['basis'] != 'g':
            raise SystemExit(f'Ingredient {key} is not measured per 100 g')

    foods, seen = [], set()
    for slug, name, cuisine, names, recipe, finished, method in DISHES:
        if not SLUG.match(slug) or slug in seen:
            raise SystemExit(f'Bad or repeated id: {slug}')
        seen.add(slug)
        total_in = sum(recipe.values())
        # A finished dish weighs between a third of what went in and all of it: nothing here gains weight.
        if not (total_in * 0.33 <= finished <= total_in + 0.5):
            raise SystemExit(f'{slug}: finished weight {finished} g does not fit {total_in} g of ingredients')
        totals = {k: 0.0 for k in ('kcal', 'protein', 'carbs', 'fat')}
        for key, grams in recipe.items():
            if grams <= 0:
                raise SystemExit(f'{slug}: {key} has no weight')
            record = catalog[I[key][0]]
            for nutrient in totals:
                totals[nutrient] += record[nutrient] * grams / 100
        per100 = {k: round(v * 100 / finished, 2 if k != 'kcal' else 1) for k, v in totals.items()}
        if per100['kcal'] > 900 or any(per100[k] > 100 for k in ('protein', 'carbs', 'fat')):
            raise SystemExit(f'{slug}: impossible values {per100}')
        # Energy must agree with the macros (4/4/9), within the spread USDA's own records show.
        atwater = 4 * per100['protein'] + 4 * per100['carbs'] + 9 * per100['fat']
        if abs(atwater - per100['kcal']) > max(25, 0.15 * per100['kcal']):
            raise SystemExit(f'{slug}: {per100["kcal"]} kcal does not match its macros ({atwater:.0f})')
        made_with = []
        for key, grams in sorted(recipe.items(), key=lambda item: -item[1]):
            word = READABLE.get(key, key.replace('_', ' '))
            if key not in SILENT and word not in made_with:
                made_with.append(word)
        foods.append({
            'id': 'regional:' + slug, 'sourceID': slug, 'name': name, 'brand': None, 'basis': 'g',
            'source': 'regional', 'sourceDate': '2026-11', 'dataset': cuisine, **per100,
            'searchNames': names,
            'summary': 'Made with ' + ', '.join(made_with[:8]) + '. ' + method,
            'recipe': [{'usda': I[key][0], 'name': I[key][1], 'grams': grams} for key, grams in recipe.items()],
            'finishedWeightG': finished,
        })
    foods.sort(key=lambda f: f['name'])
    OUTPUT.write_text(json.dumps({
        'release': 'Nourlo regional dishes, November 2026',
        'method': 'Each value is calculated from a typical recipe: the sum of its ingredients\' USDA values '
                  '(smartmarket/Resources/NutritionCatalog.json) divided by the weight of the finished dish. '
                  'Recipes are Nourlo\'s own; home and restaurant versions vary.',
        'foods': foods,
    }, ensure_ascii=False, indent=1) + '\n')
    return foods


if __name__ == '__main__':
    built = build()
    print(f'Wrote {len(built)} dishes to {OUTPUT.relative_to(ROOT)}')
    for food in built:
        print(f"  {food['kcal']:6.1f} kcal  P{food['protein']:5.1f} C{food['carbs']:5.1f} F{food['fat']:5.1f}  {food['name']}")
