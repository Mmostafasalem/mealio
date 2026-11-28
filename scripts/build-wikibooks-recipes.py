"""Builds smartmarket/Resources/Recipes.json.zlib from the Wikibooks Cookbook.

Recipes: Wikibooks Cookbook (https://en.wikibooks.org/wiki/Cookbook:Recipes),
CC BY-SA 4.0. The adapted recipes in the output stay CC BY-SA 4.0; each keeps
its page link and the app shows the credit under every recipe.

No nutrition value is typed in by hand. Each ingredient line is read into
grams of one USDA food from the bundled catalogue (scripts/recipes/ingredients.py
holds the page -> USDA name table and kitchen weights), and a recipe's values
are the sum divided by its servings. A recipe is kept only when every line
that matters is understood; seasonings "to taste" count as nothing.

1. Download the pages (cached; run again to resume):
     python3 scripts/build-wikibooks-recipes.py --download
2. Build:
     python3 scripts/build-wikibooks-recipes.py
   --report prints the ingredients that most often stopped a recipe.
"""
import collections
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts/recipes"))
import ingredients as ING  # noqa: E402
import wikiparse as W  # noqa: E402

CATALOG = ROOT / "smartmarket/Resources/NutritionCatalog.json"
OUTPUT = ROOT / "smartmarket/Resources/Recipes.json.zlib"
CACHE = Path(os.path.expanduser("~/Library/Caches/nourlo-wikibooks"))
API = "https://en.wikibooks.org/w/api.php"
UA = {"User-Agent": "NourloRecipeImport/1.0 (offline recipe import)"}

CREDIT = ("Recipes from the Wikibooks Cookbook (en.wikibooks.org), CC BY-SA 4.0. "
          "Adapted by Nourlo: amounts read into grams and nutrition estimated from USDA data.")

# --------------------------------------------------------------------------- download


def api(params):
    data = urllib.parse.urlencode({**params, "format": "json", "formatversion": "2"}).encode()
    for attempt in range(6):
        try:
            req = urllib.request.Request(API, data=data, headers=UA)
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except Exception:
            time.sleep(2 ** attempt)
    raise RuntimeError("Wikibooks API keeps failing")


def download():
    CACHE.mkdir(parents=True, exist_ok=True)
    pages_file = CACHE / "pages.json"
    pages = json.loads(pages_file.read_text()) if pages_file.exists() else {}
    titles, cont = [], {}
    while True:
        r = api({"action": "query", "list": "categorymembers", "cmtitle": "Category:Recipes",
                 "cmlimit": "500", "cmnamespace": "102", **cont})
        titles += [m["title"] for m in r["query"]["categorymembers"]]
        if "continue" not in r:
            break
        cont = r["continue"]
    todo = [t for t in titles if t not in pages]
    print(f"{len(titles)} recipes, {len(todo)} to fetch")
    for i in range(0, len(todo), 20):
        batch = todo[i:i + 20]
        r = api({"action": "query", "prop": "revisions|categories", "rvprop": "content|timestamp",
                 "rvslots": "main", "cllimit": "max", "titles": "|".join(batch)})
        for pg in r["query"]["pages"]:
            if "revisions" not in pg:
                continue
            rev = pg["revisions"][0]
            pages[pg["title"]] = {"text": rev["slots"]["main"]["content"], "timestamp": rev["timestamp"],
                                  "categories": [c["title"] for c in pg.get("categories", [])]}
        if (i // 20) % 20 == 0:
            pages_file.write_text(json.dumps(pages))
        time.sleep(0.5)
    pages_file.write_text(json.dumps(pages))
    print(f"saved {len(pages)} pages")

# --------------------------------------------------------------------------- reading lines


SEASONING = {"salt", "sea salt", "kosher salt", "pepper", "black pepper", "white pepper", "peppercorn", "water",
             "cayenne pepper", "cayenne", "red pepper flakes", "paprika", "cumin", "cinnamon", "nutmeg", "oregano",
             "thyme", "rosemary", "basil", "parsley", "cilantro", "dill", "mint", "bay leaf", "garlic powder",
             "chili powder", "onion powder", "coriander", "turmeric", "allspice", "cloves", "cardamom", "sage",
             "vanilla", "vanilla extract", "curry leaf", "saffron", "hot sauce", "lemon juice", "lime juice",
             "chives", "ground ginger", "garam masala", "curry powder", "baking soda", "baking powder",
             "worcestershire sauce", "fish sauce", "soy sauce", "vinegar", "mustard", "fennel seed", "mustard seed"}
# Lines like these never count against a recipe.
OPTIONAL = re.compile(r"\b(to taste|optional|for garnish|for serving|to serve|as needed|as required|for frying|"
                      r"for deep frying|for greasing|for dusting|garnish|for the pan|if desired|cooking spray)\b", re.I)
HEADER = re.compile(r"^(for the |the )?[a-z ]{0,30}:$", re.I)

# What one counted piece weighs when the line names the piece ("24 wingettes", "12 cabbage leaves").
PIECES = [("wingette", 35), ("drumette", 40), ("wing", 60), ("drumstick", 110), ("thigh", 110), ("breast", 200),
          ("leaf", 25), ("leave", 25), ("slice", 25), ("strip", 20), ("rasher", 15), ("fillet", 150), ("chop", 180),
          ("cutlet", 120), ("floret", 20), ("wedge", 40), ("segment", 15), ("cube", 5), ("sprig", 1), ("stalk", 40),
          ("rib", 60), ("spear", 16), ("ear", 100), ("link", 60), ("patty", 110), ("patties", 110)]

MEAS = {"g": 1, "kg": 1000, "oz": 28.35, "lb": 453.6}
VOL_CUPS = {"cup": 1, "tbsp": 1 / 16, "tsp": 1 / 48, "ml": 1 / 240, "l": 1000 / 240, "dl": 100 / 240,
            "floz": 1 / 8, "cl": 10 / 240, "pint": 2, "quart": 4}
SIZE = {"large": 1.3, "medium": 1.0, "small": 0.7, "piece": 1.0, None: 1.0}


COOKED = {"rice": "cooked rice", "basmati rice": "cooked rice", "brown rice": "cooked rice", "pasta": "cooked pasta",
          "spaghetti": "cooked pasta", "macaroni": "cooked pasta", "noodles": "cooked pasta", "lentil": "cooked lentils",
          "lentils": "cooked lentils", "dal": "cooked lentils", "quinoa": "cooked quinoa", "chicken": "cooked chicken",
          "potato": "cooked potato"}


def key_for(line):
    key = _key_for(line)
    if key in COOKED and re.search(r"\b(cooked|leftover|boiled)\b", line["raw"], re.I):
        return COOKED[key]
    return key


def plain_key(raw):
    name = " " + re.sub(r"[^a-zà-ÿ#' ]", " ", raw.lower()) + " "
    best = None
    for k in list(ING.PLAIN) + list(ING.TABLE):
        if f" {k} " in name and (best is None or len(k) > len(best)):
            best = k
    return best


def _key_for(line):
    """The TABLE key for an ingredient line: its linked page, else the longest known name in its text.
    A longer name in the text wins over a link it contains ("chicken breasts" over "Chicken")."""
    lower = line["raw"].lower()
    for target in line["linkText"] + [lower]:
        k = target.strip().lower().replace("_", " ")
        if k in ING.TRACE or any(re.search(r"\b" + re.escape(t) + r"\b", k) for t in ING.TRACE) and len(k) < 60 and not any(f" {f} " in f" {k} " for f in ("chicken", "beef", "flour", "rice", "potato", "fish", "milk", "sugar", "butter")):
            return "_trace"
        if target is lower:
            break
        if k in ING.NOT_FOOD:
            continue
        found = k if k in ING.TABLE else k.rstrip("s") if k.rstrip("s") in ING.TABLE else ING.PLAIN.get(k)
        if found:
            longer = plain_key(line["raw"])
            if longer and len(longer) > len(k) and k.rstrip("s") in longer:
                return ING.PLAIN.get(longer, longer)
            return found
    best = plain_key(line["raw"])
    if best is None:
        return None
    return ING.PLAIN.get(best, best)


def grams(line, key):
    """Grams of food in the line, 0 for a pinch, None when it can't be told."""
    if key == "_trace":
        return 0.0
    usda, per_cup, each = ING.TABLE[key]
    q, unit = line["qty"], line["unit"]
    def metric(amount, u):
        if u in MEAS:
            return amount * MEAS[u]
        cups = amount * VOL_CUPS[u]
        return cups * (per_cup or 240)
    if line["given"]:
        return metric(*line["given"])
    if line["size"]:
        return metric(*line["size"]) * (q or 1)
    raw = line["raw"].lower()
    if re.match(r"^(the )?zest of", raw) or (" zest" in raw and key in ("lemon", "lime", "orange")):
        return 0.0
    if re.match(r"^(the )?juice of", raw) and key in ("lemon", "lime", "orange"):
        usda, per_cup, each = ING.TABLE[key + " juice"]
        key = key + " juice"
        return (q or 1) * {"lemon juice": 45, "lime juice": 30, "orange juice": 85}[key]
    if q is None:
        return None
    if unit == "ball":
        return 125 * q
    if unit in MEAS:
        return q * MEAS[unit]
    if unit in VOL_CUPS:
        if per_cup is None:
            return None
        if unit in ("ml", "l", "dl", "cl") and per_cup >= 200:
            return q * VOL_CUPS[unit] * 240 * per_cup / 240
        return q * VOL_CUPS[unit] * per_cup
    if unit == "pinch":
        return 0.4 * q
    if unit == "clove":
        return 3 * q
    if unit == "can":
        return 400 * q
    if unit == "package":
        return 250 * q
    if unit == "stick":
        return 113 * q
    if unit == "slice":
        return (each or 20) * q if key in ("bread", "ham", "bacon") else 20 * q
    if unit == "bunch":
        return 50 * q
    if unit == "sprig":
        return 1 * q
    if unit == "handful":
        return 30 * q
    if unit == "head":
        return (40 if key == "garlic" else each or 400) * q
    if unit == "stalk":
        return 40 * q
    if unit in SIZE:
        piece = each
        for word, g in PIECES:
            if re.search(r"\b" + word + r"s?\b", raw):
                piece = g
                break
        else:
            # "24 chicken" isn't 24 whole birds: a count this large with a whole-item weight is a misread.
            if piece and piece >= 400 and q > 3:
                return None
        if piece:
            return q * piece * SIZE[unit]
    return None


def number_in(text):
    m = re.search(r"\d+(?:\.\d+)?", text or "")
    return float(m.group(0)) if m else None


def minutes(text):
    if not text:
        return None
    t = text.lower()
    total, found = 0.0, False
    for v, u in re.findall(r"(\d+(?:\.\d+)?)\s*(hours?|hrs?|h\b|minutes?|mins?|m\b)", t):
        total += float(v) * (60 if u.startswith("h") else 1)
        found = True
    if not found:
        return None
    return int(total) if 0 < total <= 24 * 60 else None


COURSES = [  # first match wins
    ("drink", ["beverage", "drink", "cocktail", "smoothie", "tea recipes", "coffee recipes"]),
    ("dessert", ["dessert", "cake", "cookie", "pastries", "pastry", "pie recipes", "candy", "confection", "pudding", "ice cream"]),
    ("sauce", ["sauces and condiments", "sauce", "condiment", "dressing", "spice mix", "chutney", "dip"]),
    ("breakfast", ["breakfast", "pancake"]),
    ("soup", ["soup", "stew"]),
    ("salad", ["salad"]),
    ("bread", ["bread", "baking recipes"]),
    ("side", ["side dish", "appetizer", "snack"]),
    ("main", ["main course", "main dish", "dinner", "lunch"]),
]


COMPONENT = re.compile(r"\b(icing|frosting|glaze|marinade|rub|dressing|syrup|stock|broth|seasoning|spice mix|paste|"
                       r"vinaigrette|gravy|dough|crust|batter|wash|filling|topping|ganache|custard sauce|pesto|salsa|chutney|jam|jelly)\b", re.I)
SWEET = re.compile(r"\b(cake|cookies?|muffins?|brownies?|pudding|fudge|biscuits?|cupcakes?|scones?|"
                   r"doughnuts?|donuts?|candy|toffee|truffles?|macaroons?|shortbread|cheesecake|sorbet|ice cream|halwa|halva)\b", re.I)


def course(categories, summary, title=""):
    if COMPONENT.search(title):
        return "sauce"
    if SWEET.search(title):
        return "dessert"
    text = " ".join(categories + [summary.get("category", "")]).lower()
    for name, words in COURSES:
        if any(w in text for w in words):
            return name
    return "main"


MEAT = {"chicken", "chicken#breast", "chicken breast", "chicken thigh", "beef", "ground beef", "beef#loin", "pork",
        "lamb", "meat", "bacon", "ham", "sausage", "turkey", "lard", "beef broth", "chicken broth", "chicken stock",
        "stock", "broth", "dehydrated broth", "bouillon cube"}
FISH = {"fish", "salmon", "tuna", "shrimp", "dryfish", "ground crayfish", "fish sauce"}
ANIMAL = {"egg", "eggs", "egg yolk", "egg white", "hard boiled eggs", "milk", "buttermilk", "cream", "heavy cream",
          "whipping cream", "sour cream", "yogurt", "yoghurt", "cream cheese", "cheese", "cheddar cheese",
          "parmesan cheese", "mozzarella cheese", "feta cheese", "ricotta cheese", "cottage cheese", "swiss cheese",
          "condensed milk", "evaporated milk", "ice cream", "butter", "unsalted butter", "ghee", "honey",
          "worcestershire sauce", "mayonnaise"}
GLUTEN = {"flour", "all-purpose flour", "self-rising flour", "whole wheat flour", "bread flour", "semolina", "pasta",
          "spaghetti", "macaroni", "noodles", "couscous", "bulgur", "barley", "bread", "bread crumb", "breadcrumbs",
          "tortilla", "pita", "puff pastry", "soy sauce", "beer", "oats", "rolled oats", "worcestershire sauce"}
PORK = {"pork", "bacon", "ham", "sausage", "lard"}
NUTS = {"almond", "almonds", "walnut", "walnuts", "pecan", "cashew", "peanut", "peanuts", "peanut butter",
        "pine nuts", "pistachio", "hazelnut", "peanut oil"}
DAIRY = ANIMAL - {"egg", "eggs", "egg yolk", "egg white", "hard boiled eggs", "honey", "worcestershire sauce", "mayonnaise"}
ALCOHOL = {"wine", "red wine", "white wine", "rum", "brandy", "beer"}


# Words that settle a diet tag wherever they appear in any ingredient line (linked or not),
# so "pork chops", "chicken wings" or "a splash of sherry" can't slip past the key sets.
MEAT_WORDS = ["chicken", "beef", "pork", "lamb", "mutton", "veal", "turkey", "duck", "goose", "ham", "bacon", "sausage",
              "salami", "chorizo", "pepperoni", "prosciutto", "pancetta", "meat", "steak", "mince", "ribs", "liver",
              "gelatin", "gelatine", "lard", "suet", "broth", "stock", "bouillon", "oxtail", "venison", "rabbit", "goat"]
FISH_WORDS = ["fish", "salmon", "tuna", "cod", "anchovy", "anchovies", "sardine", "shrimp", "prawn", "crab", "lobster",
              "mussel", "clam", "oyster", "scallop", "squid", "crayfish", "mackerel", "herring", "trout", "tilapia"]
PORK_WORDS = ["pork", "bacon", "ham", "sausage", "salami", "chorizo", "pepperoni", "prosciutto", "pancetta", "lard",
              "gelatin", "gelatine"]
ALCOHOL_WORDS = ["wine", "sherry", "vodka", "bourbon", "whiskey", "whisky", "rum", "brandy", "beer", "ale", "lager", "liqueur",
                 "cognac", "tequila", "gin", "vermouth", "marsala", "port", "sake", "mirin", "champagne", "kirsch", "amaretto",
                 "kahlua", "stout", "cider"]
DAIRY_WORDS = ["milk", "butter", "cream", "cheese", "yogurt", "yoghurt", "ghee", "whey", "custard", "buttermilk", "paneer",
               "mascarpone", "ricotta", "parmesan", "mozzarella", "cheddar", "feta"]
EGG_WORDS = ["egg", "eggs", "mayonnaise", "honey"]
GLUTEN_WORDS = ["flour", "bread", "breadcrumbs", "pasta", "spaghetti", "macaroni", "noodle", "noodles", "couscous", "bulgur",
                "barley", "semolina", "wheat", "rye", "tortilla", "pita", "pastry", "cracker", "crackers", "biscuit", "biscuits",
                "cake", "beer", "seitan", "soy", "oats", "oatmeal", "phyllo", "filo", "vermicelli", "lasagna", "lasagne", "penne"]
NUT_WORDS = ["almond", "almonds", "walnut", "walnuts", "pecan", "pecans", "cashew", "cashews", "peanut", "peanuts", "pistachio",
             "pistachios", "hazelnut", "hazelnuts", "nut", "nuts", "macadamia", "marzipan", "praline", "nutella"]
# Plant foods whose names contain an animal word.
PLANT_PHRASES = ["coconut milk", "almond milk", "soy milk", "oat milk", "rice milk", "coconut cream", "peanut butter", "almond butter",
                 "cocoa butter", "nut butter", "apple butter", "cream of tartar", "vegetable stock", "vegetable broth",
                 "vegetable bouillon", "butternut", "butter beans", "butter bean", "eggplant", "ginger ale", "rice wine vinegar",
                 "wine vinegar", "cider vinegar", "root beer", "coconut", "nutmeg", "soy sauce"]


def words_of(lines):
    text = " " + " ".join(l.lower() for l in lines) + " "
    for phrase in PLANT_PHRASES:
        keep = {"coconut": " coconut ", "nutmeg": " nutmeg ", "soy sauce": " soy sauce "}.get(phrase)
        text = text.replace(phrase, keep or " ")
    return set(re.findall(r"[a-z]+", text)), text


def tags(keys, lines=()):
    """Diet tags from the ingredient keys and every word of every line."""
    w, text = words_of(lines)
    def has(words): return any(x in w or (x + "s") in w for x in words)
    meat = bool(keys & MEAT) or has(MEAT_WORDS)
    fish = bool(keys & FISH) or has(FISH_WORDS)
    animal = bool(keys & ANIMAL) or has(DAIRY_WORDS) or has(EGG_WORDS)
    gluten = bool(keys & GLUTEN) or has(GLUTEN_WORDS) or " soy sauce " in text
    dairy = bool(keys & DAIRY) or has(DAIRY_WORDS)
    nuts = bool(keys & NUTS) or has(NUT_WORDS)
    pork = bool(keys & PORK) or has(PORK_WORDS)
    alcohol = bool(keys & ALCOHOL) or has(ALCOHOL_WORDS)
    out = []
    if not meat and not fish:
        out.append("vegetarian")
        if not animal:
            out.append("vegan")
    if not gluten:
        out.append("glutenFree")
    if not dairy:
        out.append("dairyFree")
    if not nuts:
        out.append("nutFree")
    if not pork:
        out.append("noPork")
        if not alcohol:
            out.append("halal" if not meat else "noPorkNoAlcohol")
    return out

# --------------------------------------------------------------------------- build


FRYING_FATS = {"oil", "vegetable oil", "canola oil", "sunflower oil", "peanut oil", "palm oil", "olive oil", "lard", "shortening", "coconut oil", "ghee"}


# What every kitchen is assumed to have: never asked for, never "missing", shown in the
# app as a kitchen basic. Only true basics: salt, pepper, everyday oils, water, sugar,
# flour, raising agents, vinegar, stock (cubes), and common dried spices and herbs.
# Everything else (lemon juice, sauces, vanilla, cream, rose water ...) is a real
# ingredient even when the amount is small.
BASIC_KEYS = {"salt", "sea salt", "kosher salt", "pepper", "black pepper", "white pepper", "peppercorn", "water",
              "cayenne pepper", "cayenne", "red pepper flakes", "paprika", "cumin", "cinnamon", "nutmeg",
              "allspice", "cloves", "cardamom", "turmeric", "garlic powder", "onion powder", "chili powder",
              "ground ginger", "garam masala", "curry powder", "fennel seed", "mustard seed", "bay leaf",
              "oil", "vegetable oil", "canola oil", "sunflower oil", "olive oil", "peanut oil",
              "sugar", "granulated sugar", "white sugar", "flour", "all-purpose flour", "baking soda", "baking powder",
              "vinegar", "stock", "broth", "chicken broth", "chicken stock", "beef broth", "vegetable broth",
              "dehydrated broth", "bouillon cube"}
# Herbs are a basic when dried, not when the line asks for fresh leaves.
HERB_KEYS = {"oregano", "thyme", "rosemary", "basil", "parsley", "cilantro", "dill", "mint", "sage", "coriander", "chives"}
FRESH = re.compile(r"\b(fresh|freshly[- ]chopped|sprigs?|bunch|handful|leaves|chopped|torn|minced|bouquet)\b", re.I)
# Text-only lines (no USDA food) that are still a dried spice or a seasoning blend.
BASIC_TEXT = re.compile(r"\b(salt|seasoning|spice blend|spices?|mixed spice|five spice|marjoram|tarragon|savory|caraway|"
                        r"anise|celery seed|fenugreek seeds?|nigella|asafoetida|hing|cream of tartar|panch puran|"
                        r"herbes de provence|epazote|smoked paprika|poultry shake|cooking spray|fat for deep frying|"
                        r"mixed herbs|herbs to taste|anything else to taste|ice|aniseed|za'atar|mace|bouquet[- ]garni)\b", re.I)
NOT_BASIC_TEXT = re.compile(r"\b(zest|food colou?ring|liquid smoke|pandan|leaves|ice cream|ghormeh)\b", re.I)
# Text-only lines that still name something a stock item can be: the words to look for.
TEXT_MATCH = [(re.compile(r"\blemons? (zest|peel|juice)|\b(zest|peel|juice)\b.*\blemons?\b", re.I), "lemon"),
              (re.compile(r"\blimes? (zest|peel|juice)|\b(zest|peel|juice)\b.*\blimes?\b", re.I), "lime"),
              (re.compile(r"\borange (zest|peel)|zest of (1 |a |one )?orange|citrus peel", re.I), "orange"),
              (re.compile(r"\brose ?water|\brose or orange flower water", re.I), "rose water|orange flower water|orange blossom water"),
              (re.compile(r"\borange (flower|blossom) water", re.I), "orange flower water|orange blossom water"),
              (re.compile(r"\blemongrass", re.I), "lemongrass"),
              (re.compile(r"\bice cream", re.I), "ice cream"),
              (re.compile(r"\bhoisin", re.I), "hoisin")]
# Lines the recipe works without: not counted as missing, shown as optional.
OPTIONAL_ONLY = re.compile(r"\b(optional|for garnish|garnish|for serving|to serve|if desired)\b", re.I)


def is_basic(key, raw):
    if key in BASIC_KEYS:
        return True
    if key in HERB_KEYS:
        return bool(re.search(r"\bdried\b", raw, re.I)) or not FRESH.search(raw)
    if key is None or key == "_trace":
        return bool(BASIC_TEXT.search(raw)) and not NOT_BASIC_TEXT.search(raw)
    return False


def flags(key, raw):
    """The flags the app reads (`CookbookRecipe.Line`): pantry = a kitchen basic,
    optional = the recipe works without it. Every other line is a real ingredient."""
    basic = is_basic(key, raw)
    out = {"pantry": basic}
    if not basic and (key is None or key == "_trace"):
        match = next((m for pattern, m in TEXT_MATCH if pattern.search(raw)), None)
        if match:
            out["match"] = match
    if not basic and OPTIONAL_ONLY.search(raw):
        out["optional"] = True
    return out


# The word a stock item's name must contain to count as this ingredient.
MATCH = {
    "chicken#breast": "chicken", "chicken breast": "chicken", "chicken thigh": "chicken", "chicken wing": "chicken",
    "chicken leg": "chicken", "whole chicken": "chicken", "cooked chicken": "chicken", "beef#loin": "beef",
    "ground beef": "beef", "meat": "beef", "pork chop": "pork", "egg yolk": "egg", "egg white": "egg",
    "eggs": "egg", "hard boiled eggs": "egg", "heavy cream": "cream", "whipping cream": "cream", "yoghurt": "yogurt",
    "cheddar cheese": "cheddar", "parmesan cheese": "parmesan", "mozzarella cheese": "mozzarella",
    "feta cheese": "feta", "ricotta cheese": "ricotta", "cottage cheese": "cottage cheese", "swiss cheese": "swiss",
    "cooked rice": "rice", "basmati rice": "rice", "brown rice": "rice", "cooked pasta": "pasta",
    "spaghetti": "pasta|spaghetti", "macaroni": "pasta|macaroni", "noodles": "noodle|pasta",
    "cooked lentils": "lentil", "lentils": "lentil", "dal": "lentil", "cooked quinoa": "quinoa",
    "cooked potato": "potato", "rolled oats": "oat", "oats": "oat", "red onion": "onion", "green onion": "onion",
    "scallion": "onion", "bell pepper": "sweet pepper|bell pepper", "green pepper": "sweet pepper|bell pepper",
    "chiles": "chili|chile|hot pepper", "chili pepper": "chili|chile|hot pepper", "jalapeño": "jalapeno",
    "habanero": "chili|hot pepper", "chipotle pepper": "chili|chipotle", "kidney bean": "kidney bean|bean",
    "beans": "bean", "black beans": "black bean|bean", "chickpeas": "chickpea", "aubergine": "eggplant",
    "courgette": "zucchini", "peas": "pea", "canned tomatoes": "tomato", "tomato paste": "tomato paste|tomato",
    "tomato sauce": "tomato", "almonds": "almond", "walnuts": "walnut", "peanuts": "peanut", "raisins": "raisin",
    "dates": "date", "strawberries": "strawberry", "blueberries": "blueberry", "olives": "olive",
    "unsalted butter": "butter", "bread crumb": "bread crumb|breadcrumb", "breadcrumbs": "bread crumb|breadcrumb",
    "lemon juice": "lemon", "lime juice": "lime", "orange juice": "orange", "condensed milk": "condensed milk",
    "evaporated milk": "evaporated milk", "buttermilk": "buttermilk", "sour cream": "sour cream",
    "cream cheese": "cream cheese", "coconut milk": "coconut milk", "chocolate chips": "chocolate",
    "cocoa powder": "cocoa", "brown sugar": "brown sugar|sugar", "powdered sugar": "sugar", "icing sugar": "sugar",
    "caster sugar": "sugar", "superfine sugar": "sugar", "self-rising flour": "flour", "whole wheat flour": "flour",
    "bread flour": "flour", "tuna": "tuna", "dryfish": "fish|cod", "ground crayfish": "crayfish|shrimp",
    "turkey": "turkey", "sweet potato": "sweet potato", "ginger": "ginger",
}


def match_for(key):
    return MATCH.get(key, key.replace("#", " "))


def slug(title, taken):
    """A short ASCII id, unique in the file: the food id is "cookbook:" + this."""
    import unicodedata
    plain = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode().lower()
    base = re.sub(r"[^a-z0-9]+", "-", plain).strip("-")[:56].strip("-") or "recipe"
    out, n = base, 2
    while out in taken:
        out, n = f"{base}-{n}", n + 1
    taken.add(out)
    return out


def build(report=False):
    foods = json.loads(CATALOG.read_text())["foods"]
    by_name = {}
    for f in foods:
        by_name.setdefault(f["name"], f)
    for k, (name, _, _) in ING.TABLE.items():
        if name not in by_name:
            raise SystemExit(f"{k}: '{name}' is not in the catalogue")

    pages = json.loads((CACHE / "pages.json").read_text())
    stoppers = collections.Counter()
    reasons = collections.Counter()
    recipes, taken = [], set()
    for title, page in sorted(pages.items()):
        r = W.parse(title, page)
        lines = [l for l in r["ingredients"] if not HEADER.match(l["raw"]) and len(l["raw"]) > 1]
        if len(lines) < 2 or len(r["steps"]) < 2:
            reasons["too short"] += 1
            continue
        if "Recipes for beverages" in r["categories"] or "drink" == course(r["categories"], r["summary"]):
            reasons["drink"] += 1
            continue
        used, out_lines, ok, total = set(), [], True, {"kcal": 0, "protein": 0, "carbs": 0, "fat": 0}
        weight = 0.0
        for l in lines:
            key = key_for(l)
            optional = bool(OPTIONAL.search(l["raw"]))
            g = grams(l, key) if key else None
            if g is None:
                if optional or (key in SEASONING) or (key and l["qty"] is None and key in SEASONING | {"oil", "olive oil", "vegetable oil", "butter", "sugar"}):
                    out_lines.append({"text": l["raw"], **({"food": by_name[ING.TABLE[key][0]]["id"], "match": match_for(key)}
                                                           if key else {}), **flags(key, l["raw"])})
                    if key:
                        used.add(key)
                    continue
                ok = False
                stoppers[(l["linkText"][0].lower() if l["linkText"] else l["name"])[:40]] += 1
                break
            if key == "_trace":
                out_lines.append({"text": l["raw"], **flags(key, l["raw"])})
                continue
            food = by_name[ING.TABLE[key][0]]
            used.add(key)
            if key in FRYING_FATS and re.search(r"\b(for (deep )?frying|deep[- ]fry|deep[- ]frying|to fry|frying)\b", l["raw"], re.I):
                g *= 0.1  # a fried food takes up about a tenth of the oil it is fried in
            for n in total:
                total[n] += (food.get(n) or 0) * g / 100
            weight += g
            out_lines.append({"text": l["raw"], "food": food["id"], "grams": round(g, 1), "match": match_for(key),
                              **flags(key, l["raw"])})
        if not ok:
            reasons["ingredient not understood"] += 1
            continue
        if total["kcal"] < 50:
            reasons["too little food"] += 1
            continue
        servings = number_in(r["summary"].get("servings") or r["summary"].get("yield"))
        estimated_servings = False
        kind = course(r["categories"], r["summary"], r["title"])
        if not servings or servings > 40:
            servings = max(1, min(12, round(total["kcal"] / (300 if kind in ("dessert", "bread", "sauce") else 550))))
            estimated_servings = True
        # "Serves 25" often counts pieces (fritters, cookies): group small pieces into real portions.
        if total["kcal"] / servings < 120 and kind not in ("sauce",):
            servings = max(1, round(total["kcal"] / 300))
            estimated_servings = True
        # A whole batch given as one serving ("Bulk Sausage"): portion it by calories instead.
        if total["kcal"] / servings > 1400 or weight / servings > 1200:
            portion = 300 if kind in ("dessert", "bread", "sauce") else 550
            servings = max(servings, round(total["kcal"] / portion), round(weight / 600))
            estimated_servings = True
        per = {n: round(v / servings, 1) for n, v in total.items()}
        per["kcal"] = round(per["kcal"])
        if per["kcal"] > 1500 or per["kcal"] < 20 or weight > 12000:
            reasons["odd per serving"] += 1
            continue
        name = r["title"]
        recipes.append({
            "id": slug(name, taken),
            "title": name,
            "url": "https://en.wikibooks.org/wiki/" + urllib.parse.quote(title.replace(" ", "_")),
            "course": kind,
            "servings": servings,
            "servingsEstimated": estimated_servings,
            "minutes": minutes(r["summary"].get("time")),
            "difficulty": number_in(r["summary"].get("difficulty")),
            "ingredients": out_lines,
            "steps": r["steps"],
            "perServing": per,
            "gramsPerServing": round(weight / servings),
            "tags": tags(used, [l["raw"] for l in lines]),
        })
    print(f"{len(pages)} pages -> {len(recipes)} recipes kept")
    print(dict(reasons))
    print(collections.Counter(r["course"] for r in recipes))
    if report:
        for k, v in stoppers.most_common(150):
            print(v, k)
    data = json.dumps({"credit": CREDIT, "license": "CC BY-SA 4.0",
                       "source": "https://en.wikibooks.org/wiki/Cookbook:Recipes", "recipes": recipes},
                      ensure_ascii=False, separators=(",", ":")).encode()
    # Raw deflate (no zlib header), which is what Apple's `NSData.decompressed(using: .zlib)` reads.
    packer = zlib.compressobj(9, zlib.DEFLATED, -15)
    OUTPUT.write_bytes(packer.compress(data) + packer.flush())
    print(f"wrote {OUTPUT.relative_to(ROOT)}: {len(data) // 1024} KB raw, {OUTPUT.stat().st_size // 1024} KB packed")


if __name__ == "__main__":
    if "--download" in sys.argv:
        download()
    else:
        build(report="--report" in sys.argv)
