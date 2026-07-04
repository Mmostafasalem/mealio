import collections
import json
import math
import os
import re
import time
from groq import Groq

from openfoodfacts import nutrition_for

GROQ_API_KEY = os.environ.get("GROQ_API_KEY")
if not GROQ_API_KEY:
    raise RuntimeError("GROQ_API_KEY environment variable is required. Set it before starting the server.")

APP_API_KEY = os.environ.get("APP_API_KEY")  # Shared secret between iOS app and backend

# Production default: a larger, more reliable model than the 8b "instant" one,
# so meal plans / recipes are higher quality and emit valid JSON consistently.
# Override with the GROQ_MODEL env var (e.g. to swap models without a deploy).
GROQ_MODEL  = os.environ.get("GROQ_MODEL", "llama-3.3-70b-versatile")

# Bounded timeout + one retry so a slow/transient Groq call fails fast (the app
# then uses its on-device fallback) instead of hanging. Kept comfortably under
# the iOS-side request timeouts (30–60s) even if the single retry fires.
groq_client = Groq(api_key=GROQ_API_KEY, timeout=25.0, max_retries=1)

# ---------------------------------------------------------------------------
# Rate limiting — 60 requests per IP per minute
# ---------------------------------------------------------------------------

_rate_buckets: dict = collections.defaultdict(list)
_RATE_WINDOW = 60
_RATE_MAX    = 60
_last_sweep  = 0.0

def _is_rate_limited(ip: str) -> bool:
    now    = time.time()
    cutoff = now - _RATE_WINDOW

    # Periodically evict stale IP buckets so the dict can't grow unbounded.
    global _last_sweep
    if now - _last_sweep > 300:
        _last_sweep = now
        for key in list(_rate_buckets.keys()):
            b = _rate_buckets[key]
            while b and b[0] < cutoff:
                b.pop(0)
            if not b:
                del _rate_buckets[key]

    bucket = _rate_buckets[ip]
    while bucket and bucket[0] < cutoff:
        bucket.pop(0)
    if len(bucket) >= _RATE_MAX:
        return True
    bucket.append(now)
    return False

# ---------------------------------------------------------------------------
# Custom error for returning HTTP error responses from handlers
# ---------------------------------------------------------------------------

class RequestError(Exception):
    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.message = message
        self.status  = status

# ---------------------------------------------------------------------------
# Defensive coercion helpers — request bodies come from clients and may contain
# wrong types. These never raise, so a malformed field degrades to a sensible
# default (HTTP 400/200) instead of crashing a handler with a 500.
# ---------------------------------------------------------------------------

def _as_int(val, default: int) -> int:
    try:
        if isinstance(val, bool) or val is None:
            return default
        return int(round(float(val)))
    except (TypeError, ValueError):
        return default

def _as_dict(val) -> dict:
    return val if isinstance(val, dict) else {}

def _as_str(val, default: str = "") -> str:
    return val if isinstance(val, str) else (default if val is None else str(val))

# ---------------------------------------------------------------------------
# Static store locations
# ---------------------------------------------------------------------------

STORES = {
    "Maxima": {"lat": 54.6872, "lon": 25.2797, "address": "Savanorių pr. 176, Vilnius"},
    "Rimi":   {"lat": 54.6989, "lon": 25.2730, "address": "Konstitucijos pr. 16, Vilnius"},
    "Iki":    {"lat": 54.6750, "lon": 25.2800, "address": "Didlaukio g. 47, Vilnius"},
    "Lidl":   {"lat": 54.6680, "lon": 25.2750, "address": "Laisvės pr. 75, Vilnius"},
    "Norfa":  {"lat": 54.7100, "lon": 25.2600, "address": "Ukmergės g. 369, Vilnius"},
}

# ---------------------------------------------------------------------------
# Static fallback deals (emergency baseline if deals_data.json is missing)
# ---------------------------------------------------------------------------

DEALS = [
    {"id": 101, "name": "Chicken Breast", "brand": "Lietuviška", "store": "Maxima",
     "originalPrice": 5.99, "discountPrice": 3.99, "discountPercent": 33,
     "category": "meat", "quantity": "500g",
     "protein": 31, "carbs": 0, "fat": 3.6, "kcalPer100g": 165,
     "allergens": [], "expiryDays": 3},
    {"id": 102, "name": "Salmon Fillet", "brand": "Rimi Fresh", "store": "Rimi",
     "originalPrice": 9.99, "discountPrice": 6.49, "discountPercent": 35,
     "category": "fish", "quantity": "400g",
     "protein": 25, "carbs": 0, "fat": 13, "kcalPer100g": 208,
     "allergens": ["fish"], "expiryDays": 2},
    {"id": 103, "name": "Greek Yogurt", "brand": "Biopasaka", "store": "Iki",
     "originalPrice": 2.49, "discountPrice": 1.49, "discountPercent": 40,
     "category": "dairy", "quantity": "400g",
     "protein": 10, "carbs": 4, "fat": 0.4, "kcalPer100g": 59,
     "allergens": ["milk"], "expiryDays": 7},
    {"id": 104, "name": "Whole Grain Bread", "brand": "Fazer", "store": "Maxima",
     "originalPrice": 2.29, "discountPrice": 1.59, "discountPercent": 31,
     "category": "bread", "quantity": "700g",
     "protein": 8, "carbs": 41, "fat": 3, "kcalPer100g": 230,
     "allergens": ["gluten"], "expiryDays": 5},
    {"id": 105, "name": "Eggs (12-pack)", "brand": "Vilniaus paukštynas", "store": "Lidl",
     "originalPrice": 3.49, "discountPrice": 2.29, "discountPercent": 34,
     "category": "eggs", "quantity": "12 vnt",
     "protein": 13, "carbs": 1, "fat": 11, "kcalPer100g": 155,
     "allergens": ["eggs"], "expiryDays": 21},
    {"id": 106, "name": "Oats", "brand": "Naminė", "store": "Norfa",
     "originalPrice": 1.99, "discountPrice": 1.19, "discountPercent": 40,
     "category": "grains", "quantity": "1kg",
     "protein": 13, "carbs": 67, "fat": 7, "kcalPer100g": 389,
     "allergens": ["gluten"], "expiryDays": 180},
    {"id": 107, "name": "Cottage Cheese", "brand": "Rokiškio", "store": "Rimi",
     "originalPrice": 2.99, "discountPrice": 1.99, "discountPercent": 33,
     "category": "dairy", "quantity": "500g",
     "protein": 12, "carbs": 3, "fat": 4, "kcalPer100g": 98,
     "allergens": ["milk"], "expiryDays": 10},
    {"id": 108, "name": "Broccoli", "brand": "Lietuviška daržovė", "store": "Iki",
     "originalPrice": 1.49, "discountPrice": 0.99, "discountPercent": 34,
     "category": "vegetables", "quantity": "500g",
     "protein": 2.8, "carbs": 7, "fat": 0.4, "kcalPer100g": 34,
     "allergens": [], "expiryDays": 5},
    {"id": 109, "name": "Tuna (canned)", "brand": "Starkist", "store": "Maxima",
     "originalPrice": 2.19, "discountPrice": 1.39, "discountPercent": 37,
     "category": "fish", "quantity": "185g",
     "protein": 26, "carbs": 0, "fat": 1, "kcalPer100g": 116,
     "allergens": ["fish"], "expiryDays": 730},
    {"id": 110, "name": "Banana", "brand": "Chiquita", "store": "Lidl",
     "originalPrice": 1.29, "discountPrice": 0.79, "discountPercent": 39,
     "category": "fruit", "quantity": "1kg",
     "protein": 1.1, "carbs": 23, "fat": 0.3, "kcalPer100g": 89,
     "allergens": [], "expiryDays": 4},
]

# ---------------------------------------------------------------------------
# Curated catalog + Open Food Facts nutrition enrichment
# (replaces the previous live-scraping data layer)
# ---------------------------------------------------------------------------

CATEGORY_EMOJI = {
    "meat": "🥩", "fish": "🐟", "dairy": "🥛", "bread": "🍞",
    "eggs": "🥚", "fruit": "🍎", "fruits": "🍎", "vegetables": "🥦",
    "snacks": "🍿", "beverages": "🧃", "frozen": "🧊",
    "packaged": "📦", "condiments": "🫙", "grains": "🌾",
    "legumes": "🫘", "oils": "🫒", "spices": "🧂", "other": "🛒",
}

# Per-category nutrition fallback (per 100g):
# (kcal, protein, carbs, fat, allergens, expiry_days)
CATEGORY_NUTRITION = {
    "meat":       (165, 21.0,  0.0,   9.0, [],          3),
    "fish":       (150, 20.0,  0.0,   6.0, ["fish"],    2),
    "dairy":      ( 70,  8.0,  5.0,   4.0, ["milk"],    7),
    "eggs":       (155, 13.0,  1.0,  11.0, ["eggs"],   21),
    "bread":      (250,  8.0, 45.0,   3.0, ["gluten"],  4),
    "fruit":      ( 55,  0.7, 13.0,   0.3, [],          5),
    "fruits":     ( 55,  0.7, 13.0,   0.3, [],          5),
    "vegetables": ( 30,  2.0,  6.0,   0.3, [],          5),
    "grains":     (360,  9.0, 72.0,   2.5, ["gluten"],365),
    "snacks":     (450,  8.0, 45.0,  25.0, [],        180),
    "beverages":  ( 40,  0.5,  9.0,   0.0, [],        365),
    "frozen":     (110,  6.0, 12.0,   4.0, [],        180),
    "oils":       (884,  0.0,  0.0, 100.0, [],        540),
    "condiments": (100,  2.0, 10.0,   5.0, [],        365),
    "other":      (100,  5.0, 15.0,   3.0, [],         14),
}

# Specific emoji overrides by product name
NAME_EMOJI = {
    "Chicken Breast Fillet": "🍗", "Chicken breast": "🍗", "Salmon Fillet": "🐟",
    "Greek Yogurt": "🥛", "Whole Grain Bread": "🍞", "Eggs (12-pack)": "🥚",
    "Bananas": "🍌", "Banana": "🍌",
}

_CATALOG_CACHE: dict = {"data": None, "ts": 0.0}
_CATALOG_TTL = 6 * 3600  # 6 h


def _load_curated() -> list[dict]:
    """Load the curated product feed from deals_data.json (fallback: DEALS)."""
    path = os.path.join(os.path.dirname(__file__), "deals_data.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        products = data.get("products") if isinstance(data, dict) else data
        if isinstance(products, list) and products:
            return products
    except FileNotFoundError:
        print("[Curated] deals_data.json not found — using embedded DEALS fallback")
    except Exception as exc:
        print(f"[Curated] load error: {exc} — using embedded DEALS fallback")
    return _deals_as_curated()


def _deals_as_curated() -> list[dict]:
    """Map the embedded static DEALS list to the curated schema (emergency fallback)."""
    out = []
    for d in DEALS:
        out.append({
            "id": d["id"], "name": d["name"], "brand": d.get("brand", ""),
            "store": d["store"], "category": d.get("category", "other"),
            "originalPrice": d["originalPrice"], "discountPrice": d["discountPrice"],
            "quantity": d.get("quantity", "1 vnt"), "allergens": d.get("allergens", []),
            "expiryDays": d.get("expiryDays", 7),
            "nutrition": {"kcal": d.get("kcalPer100g", 0), "protein": d.get("protein", 0),
                          "carbs": d.get("carbs", 0), "fat": d.get("fat", 0)},
        })
    return out


def _resolve_nutrition(raw: dict):
    """Return (kcal, protein, carbs, fat, allergens, source) for a curated item."""
    cat = raw.get("category", "other")
    fb = CATEGORY_NUTRITION.get(cat, CATEGORY_NUTRITION["other"])
    allergens = raw.get("allergens", fb[4])

    # 1. Explicit override in the curated feed (fastest, deterministic)
    n = raw.get("nutrition")
    if isinstance(n, dict) and n.get("kcal"):
        return (n.get("kcal", fb[0]), n.get("protein", fb[1]),
                n.get("carbs", fb[2]), n.get("fat", fb[3]), allergens, "curated")

    # 2. Open Food Facts (by barcode, then name)
    off = nutrition_for(name=raw.get("name"), barcode=raw.get("barcode"))
    if off:
        return (off["kcal"], off["protein"], off["carbs"], off["fat"],
                allergens, "openfoodfacts")

    # 3. Category average fallback
    return (fb[0], fb[1], fb[2], fb[3], allergens, "estimated")


def _build_product(raw: dict) -> dict:
    """Build an iOS-schema product dict from a curated item, enriching nutrition."""
    store = raw["store"]
    store_info = STORES.get(store, {"lat": 54.6872, "lon": 25.2797})
    orig = float(raw["originalPrice"])
    disc = float(raw.get("discountPrice", orig))
    on_sale = disc < orig and orig > 0
    pct = round((orig - disc) / orig * 100) if on_sale else 0

    kcal, prot, carbs, fat, allergens, source = _resolve_nutrition(raw)
    qty_n, qty_u = _split_quantity(raw.get("quantity"))
    expiry_days = int(raw.get("expiryDays", 7))
    expires_in = "today" if expiry_days <= 1 else f"{expiry_days} days"
    emoji = NAME_EMOJI.get(raw["name"]) or CATEGORY_EMOJI.get(raw.get("category", ""), "🛒")

    return {
        "id":              raw["id"],
        "name":            raw["name"],
        "brand":           raw.get("brand", ""),
        "emoji":           emoji,
        "store":           store,
        "originalPrice":   round(orig, 2),
        "discountedPrice": round(disc if on_sale else orig, 2),
        "discount":        pct,
        "isOnSale":        on_sale,
        "category":        raw.get("category", "other"),
        "imageUrl":        raw.get("imageUrl"),
        "kcalPer100g":     int(round(kcal)),
        "proteinPer100g":  round(float(prot), 1),
        "carbsPer100g":    round(float(carbs), 1),
        "fatPer100g":      round(float(fat), 1),
        "weeklyQty":       qty_n,
        "unit":            qty_u,
        "expiresIn":       expires_in,
        "allergens":       allergens,
        "latitude":        store_info.get("lat", 54.6872),
        "longitude":       store_info.get("lon", 25.2797),
        "nutritionSource": source,
    }


def get_product_catalog() -> list[dict]:
    """Return the full curated product catalog (all stores), cached 6 h."""
    global _CATALOG_CACHE
    now = time.time()
    if _CATALOG_CACHE["data"] and (now - _CATALOG_CACHE["ts"]) < _CATALOG_TTL:
        return _CATALOG_CACHE["data"]

    catalog = []
    seen = set()
    for raw in _load_curated():
        key = f"{raw.get('store')}_{raw.get('id')}"
        if key in seen:
            continue
        seen.add(key)
        try:
            catalog.append(_build_product(raw))
        except Exception as exc:
            print(f"[Catalog] skip item {raw.get('id')}: {exc}")

    _CATALOG_CACHE = {"data": catalog, "ts": now}
    print(f"[Catalog] {len(catalog)} curated products from "
          f"{len(set(p['store'] for p in catalog))} stores")
    return catalog

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def haversine_km(lat1, lon1, lat2, lon2):
    R = 6371
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    a = math.sin(d_lat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(d_lon/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def _split_quantity(qty):
    """'500g' -> (500, 'g'); '12 vnt' -> (12, 'vnt'); '1kg' -> (1, 'kg')."""
    if not qty:
        return 1, "unit"
    m = re.match(r"\s*(\d+(?:\.\d+)?)\s*([a-zA-Zįė]*)", str(qty))
    if not m:
        return 1, str(qty)
    num = float(m.group(1))
    unit = m.group(2) or "unit"
    return (int(num) if num.is_integer() else num), unit

def enrich_deal(deal):
    """Compat shim: build an iOS product dict from a raw DEALS-style record."""
    raw = {
        **deal,
        "discountPrice": deal.get("discountPrice", deal.get("originalPrice")),
        "nutrition": {
            "kcal":    deal.get("kcalPer100g", 0),
            "protein": deal.get("protein", 0),
            "carbs":   deal.get("carbs", 0),
            "fat":     deal.get("fat", 0),
        },
    }
    return _build_product(raw)

def _active_deals():
    """All currently-discounted products from the curated catalog."""
    return [p for p in get_product_catalog() if p.get("isOnSale")]

def deals_summary(deals, max_items=12):
    """Compact list for AI prompts — capped to save tokens."""
    out = []
    for d in deals[:max_items]:
        out.append({
            "n": d["name"][:30],
            "s": d["store"],
            "p": d.get("discountedPrice") if d.get("discountedPrice") is not None else d.get("discountPrice", 0),
            "d": d.get("discount") if d.get("discount") is not None else d.get("discountPercent", 0),
            "c": d.get("category", "")[:12],
        })
    return out

def groq_json(messages, fallback, max_tokens=2048, json_object=False):
    """Call Groq and parse the first JSON object/array from the response.

    Set json_object=True for endpoints that return a single JSON *object* to use
    Groq's guaranteed-JSON mode (not valid for array responses). The prompt must
    mention "JSON" for this mode to be accepted.
    """
    try:
        kwargs = dict(
            model=GROQ_MODEL,
            messages=messages,
            temperature=0.7,
            max_tokens=max_tokens,
        )
        if json_object:
            kwargs["response_format"] = {"type": "json_object"}
        resp = groq_client.chat.completions.create(**kwargs)
        text = resp.choices[0].message.content or ""
        text = re.sub(r"```(?:json)?\s*", "", text).strip().rstrip("```").strip()
        match = re.search(r"(\{[\s\S]*\}|\[[\s\S]*\])", text)
        if match:
            return json.loads(match.group(1))
        return json.loads(text)
    except Exception as e:
        print(f"[Groq JSON error] {e}")
        return fallback

def groq_text(messages):
    """Call Groq and return plain text response."""
    try:
        resp = groq_client.chat.completions.create(
            model=GROQ_MODEL,
            messages=messages,
            temperature=0.7,
            max_tokens=256,
        )
        return resp.choices[0].message.content or ""
    except Exception as e:
        print(f"[Groq text error] {e}")
        return "I'm having trouble connecting right now. Please try again."

# ---------------------------------------------------------------------------
# Meal plan normalisation
# ---------------------------------------------------------------------------

CANONICAL_DAYS = [
    "pirmadienis", "antradienis", "treciadienis", "ketvirtadienis",
    "pentadienis", "sestadienis", "sekmadienis",
]

DAY_KEY_MAP = {
    "pirmadienis": "pirmadienis",
    "antradienis": "antradienis",
    "treciadienis": "treciadienis", "treciaDienis": "treciadienis",
    "ketvirtadienis": "ketvirtadienis", "ketvirtaDienis": "ketvirtadienis",
    "pentadienis": "pentadienis", "pentaDienis": "pentadienis",
    "penktadienis": "pentadienis", "penktaDienis": "pentadienis",
    "sestadienis": "sestadienis", "sestaDienis": "sestadienis", "šeštadienis": "sestadienis",
    "sekmadienis": "sekmadienis", "sekmaDienis": "sekmadienis",
}

MEAL_KEY_MAP = {
    "pusryciai": "pusryciai", "pusryčiai": "pusryciai", "breakfast": "pusryciai",
    "pietus": "pietūs", "pietūs": "pietūs", "lunch": "pietūs",
    "vakariene": "vakariene", "vakarienė": "vakariene", "dinner": "vakariene",
    "uzkandziai": "uzkandziai", "užkandžiai": "uzkandziai",
    "uzkandis": "uzkandziai", "užkandis": "uzkandziai",
    "snack": "uzkandziai", "snacks": "uzkandziai",
}

def _normalize_meal(raw):
    if not isinstance(raw, dict):
        return None
    name = raw.get("pavadinimas") or raw.get("name") or raw.get("title") or "Meal"
    ing  = raw.get("ingredientai") or raw.get("ingredients") or raw.get("sudedamosios") or []
    if isinstance(ing, str):
        ing = [s.strip() for s in ing.split(",") if s.strip()]
    elif not isinstance(ing, list):
        ing = []
    kcal = raw.get("kcal") or raw.get("kalorijų") or raw.get("kalorijos") or raw.get("calories") or 0
    try:
        kcal = int(round(float(kcal)))
    except (TypeError, ValueError):
        kcal = 0
    return {"pavadinimas": str(name), "ingredientai": [str(x) for x in ing], "kcal": kcal}

def _normalize_day(raw):
    if not isinstance(raw, dict):
        return None
    meals = {"pusryciai": None, "pietūs": None, "vakariene": None, "uzkandziai": None}
    for key, val in raw.items():
        canon = MEAL_KEY_MAP.get(key) or MEAL_KEY_MAP.get(str(key).lower())
        if canon and meals.get(canon) is None:
            meals[canon] = _normalize_meal(val)
    total = raw.get("visoKcal") or raw.get("visoKalorijų") or raw.get("totalKcal")
    if total is None:
        total = sum(m["kcal"] for m in meals.values() if m)
    try:
        total = int(round(float(total)))
    except (TypeError, ValueError):
        total = 0
    return {**meals, "visoKcal": total}

def _normalize_meal_plan(result, target_kcal):
    if not isinstance(result, dict):
        result = {}
    agent_message = result.get("agentMessage") or result.get("agent_message")
    remapped = {}
    for key, val in result.items():
        canon = DAY_KEY_MAP.get(key) or DAY_KEY_MAP.get(str(key).lower())
        if canon:
            remapped[canon] = _normalize_day(val)
    fallback = _fallback_meal_plan(target_kcal)
    out = {}
    for day in CANONICAL_DAYS:
        out[day] = remapped.get(day) or _normalize_day(fallback.get(day))
    if agent_message:
        out["agentMessage"] = agent_message
    return out

_FALLBACK_DAYS = [
    ("Oatmeal with banana",      "Chicken breast with rice",   "Salmon with vegetables",    "Greek yogurt"),
    ("Scrambled eggs on toast",  "Tuna salad wrap",            "Beef stir-fry with noodles","Cottage cheese"),
    ("Greek yogurt & berries",   "Lentil soup",                "Baked cod with broccoli",   "Handful of almonds"),
    ("Protein pancakes",         "Turkey & rice bowl",         "Pork tenderloin & potatoes","Banana"),
    ("Avocado toast with eggs",  "Chicken Caesar salad",       "Pasta with tomato sauce",   "Oats with milk"),
    ("Cottage cheese & fruit",   "Salmon rice bowl",           "Beef burger (no bun)",      "Apple & peanut butter"),
    ("Muesli with milk",         "Vegetable omelette",         "Roast chicken & veggies",   "Mixed nuts"),
]

def _fallback_meal_plan(target_kcal):
    b = round(target_kcal * 0.25)
    l = round(target_kcal * 0.35)
    d = round(target_kcal * 0.30)
    s = round(target_kcal * 0.10)
    plan = {}
    for i, day in enumerate(CANONICAL_DAYS):
        bname, lname, dname, sname = _FALLBACK_DAYS[i]
        plan[day] = {
            "pusryčiai": {"pavadinimas": bname, "kalorijų": b, "baltymai": 8,  "angliavandeniai": 45, "riebalai": 5,  "porcija": "300g"},
            "pietūs":    {"pavadinimas": lname, "kalorijų": l, "baltymai": 35, "angliavandeniai": 50, "riebalai": 8,  "porcija": "450g"},
            "vakarienė": {"pavadinimas": dname, "kalorijų": d, "baltymai": 28, "angliavandeniai": 25, "riebalai": 14, "porcija": "400g"},
            "užkandis":  {"pavadinimas": sname, "kalorijų": s, "baltymai": 10, "angliavandeniai": 6,  "riebalai": 1,  "porcija": "200g"},
        }
    plan["agentMessage"] = f"Fallback plan targeting {target_kcal} kcal/day."
    return plan

# ---------------------------------------------------------------------------
# Endpoint handlers
# ---------------------------------------------------------------------------

def handle_health():
    catalog = _CATALOG_CACHE["data"] or []
    return {
        "status":         "ok",
        "model":          GROQ_MODEL,
        "catalogSize":    len(catalog),
        "deals":          sum(1 for p in catalog if p.get("isOnSale")),
        "catalogSources": sorted(set(p["store"] for p in catalog)),
    }

def handle_products(query_params) -> list[dict]:
    """Return the full product catalog (all markets, all products)."""
    catalog = get_product_catalog()
    store_q    = (query_params.get("store",    [None])[0] or "").lower()
    category_q = (query_params.get("category", [None])[0] or "").lower()
    search_q   = (query_params.get("q",        [None])[0] or "").lower()

    results = catalog
    if store_q and store_q != "all":
        results = [p for p in results if p["store"].lower() == store_q]
    if category_q and category_q != "all":
        results = [p for p in results if p["category"].lower() == category_q]
    if search_q:
        results = [p for p in results
                   if search_q in p["name"].lower() or search_q in p["brand"].lower()]

    try:
        lat    = float(query_params.get("lat",    [None])[0])
        lon    = float(query_params.get("lon",    [None])[0])
        radius = float(query_params.get("radius", ["8000"])[0]) / 1000
        results = [p for p in results
                   if haversine_km(lat, lon, p["latitude"], p["longitude"]) <= radius]
    except (TypeError, ValueError):
        pass

    return results


def handle_deals(query_params):
    """Return only discounted (isOnSale) products — used for notifications."""
    # Discounted items from the curated catalog
    source = _active_deals()
    try:
        lat    = float(query_params.get("lat",    [None])[0])
        lon    = float(query_params.get("lon",    [None])[0])
        radius = float(query_params.get("radius", ["5000"])[0]) / 1000
        source = [d for d in source if haversine_km(lat, lon, d["latitude"], d["longitude"]) <= radius]
    except (TypeError, ValueError):
        pass
    return source

def handle_bmr(body):
    try:
        w = float(body.get("weight", 70))
        h = float(body.get("height", 170))
        a = int(body.get("age", 25))
    except (ValueError, TypeError):
        raise RequestError("weight, height and age must be numbers")

    if not (20 <= w <= 300):
        raise RequestError("weight must be between 20 and 300 kg")
    if not (100 <= h <= 250):
        raise RequestError("height must be between 100 and 250 cm")
    if not (13 <= a <= 100):
        raise RequestError("age must be between 13 and 100")

    g  = _as_str(body.get("gender"), "male").lower()
    al = _as_str(body.get("activityLevel"), "moderate").lower()

    bmr = 10*w + 6.25*h - 5*a + (5 if g == "male" else -161)
    multipliers = {"sedentary": 1.2, "light": 1.375, "moderate": 1.55, "active": 1.725, "veryActive": 1.9}
    tdee = bmr * multipliers.get(al, 1.55)

    return {
        "bmr": round(bmr),
        "tdee": round(tdee),
        "loseCalories":     round(tdee - 500),
        "maintainCalories": round(tdee),
        "gainCalories":     round(tdee + 500),
        "macros": {
            "protein": round(w * 2.0),
            "carbs":   round((tdee * 0.45) / 4),
            "fat":     round((tdee * 0.25) / 9),
        }
    }

def handle_meal_plan(body):
    # Bodies are client-controlled — coerce every field to the expected type so a
    # malformed payload degrades gracefully instead of 500-ing a handler.
    user        = _as_dict(body.get("user"))
    bmr_data    = _as_dict(body.get("bmrData"))
    goal        = _as_str(body.get("goal"), "maintain")

    # favoriteFoods is now a list of name strings sent directly from the iOS app.
    # All user-controlled lists are clamped to bound prompt size / token cost.
    fav_names   = (user.get("favoriteFoods") or [])[:50]
    dietary     = ((user.get("dietaryOptions") or []) + (user.get("allergies") or []))[:30]

    # Foods the user has already picked/bought — prioritise these as ingredients.
    grocery     = body.get("groceryList", [])
    grocery     = grocery if isinstance(grocery, list) else []
    in_stock    = [g.get("name") for g in grocery[:100]
                   if isinstance(g, dict) and g.get("name")]
    macros      = _as_dict(bmr_data.get("macros"))
    target_kcal = _as_int(bmr_data.get("maintainCalories"), 2000)
    protein_g   = _as_int(macros.get("protein"), 120)
    carbs_g     = _as_int(macros.get("carbs"), 225)
    fat_g       = _as_int(macros.get("fat"), 56)

    if goal == "lose":
        target_kcal = _as_int(bmr_data.get("loseCalories"), target_kcal - 500)
    elif goal == "gain":
        target_kcal = _as_int(bmr_data.get("gainCalories"), target_kcal + 500)

    active      = _active_deals()
    avail_deals = deals_summary(active)

    system_prompt = """7-day meal plan JSON for Mealio (Vilnius). Keys: pirmadienis-sekmadienis. Each day: pusryčiai,pietūs,vakarienė,užkandis. Each meal: {pavadinimas,kalorijų,baltymai,angliavandeniai,riebalai,porcija}. Add agentMessage (1 sentence). PRIORITISE ingredients the user already bought (their shopping list), then common affordable groceries. Do NOT claim items are on sale or discounted. Hit targets. IMPORTANT: every day MUST have a completely different breakfast, lunch, dinner and snack — no meal name should repeat across days. Return ONLY JSON."""

    seed = int(time.time()) % 10000
    user_prompt = (
        f"Goal: {goal}\n"
        f"Daily target: {target_kcal} kcal | Protein {protein_g}g | Carbs {carbs_g}g | Fat {fat_g}g\n"
        f"Favourite food names: {fav_names}\n"
        f"Already bought (use these first): {in_stock}\n"
        f"Dietary preferences: {dietary}\n"
        f"Available groceries this week: {json.dumps(avail_deals)}\n"
        f"Variation seed: {seed}\n"
        "Generate the full 7-day meal plan JSON now. Make each day's meals unique."
    )

    result = groq_json(
        [{"role": "system", "content": system_prompt},
         {"role": "user",   "content": user_prompt}],
        _fallback_meal_plan(target_kcal),
        max_tokens=4000,        # a full 7-day plan is large — avoid truncation
        json_object=True,       # guaranteed valid JSON object
    )
    result = _normalize_meal_plan(result, target_kcal)
    if not result.get("agentMessage"):
        result["agentMessage"] = f"This week's plan targets {target_kcal} kcal/day using your favourite foods and everyday groceries."
    return result

def handle_gap_fillers(body):
    current_kcal = body.get("currentCalories", 1500)
    target_kcal  = body.get("targetCalories",  2000)
    protein_gap  = body.get("proteinGap",  0)
    carbs_gap    = body.get("carbsGap",    0)
    fat_gap      = body.get("fatGap",      0)

    prompt = (
        f"You are a nutrition assistant. Suggest 3 simple snack or food additions to fill a daily nutrition gap.\n"
        f"Current intake: {current_kcal} kcal. Target: {target_kcal} kcal.\n"
        f"Gaps — Protein: {protein_gap}g, Carbs: {carbs_gap}g, Fat: {fat_gap}g.\n"
        f"Available groceries: {json.dumps(deals_summary(_active_deals()))}\n\n"
        'Return a JSON array of 3 objects, each with: {"name": string, "calories": int, "protein": float, "carbs": float, "fat": float, "reason": string}\n'
        "Return ONLY the JSON array."
    )
    return groq_json(
        [{"role": "user", "content": prompt}],
        [{"name": "Greek Yogurt", "calories": 100, "protein": 10, "carbs": 4, "fat": 0.4, "reason": "High protein gap filler"}]
    )

def _normalize_advice_item(raw):
    if not isinstance(raw, dict):
        return None
    return {
        "produktas":     str(raw.get("produktas") or raw.get("product") or raw.get("name") or "Item"),
        "priezastis":    str(raw.get("priezastis") or raw.get("priežastis") or raw.get("reason") or ""),
        "apytiksleCena": str(raw.get("apytiksleCena") or raw.get("kaina") or raw.get("price") or ""),
        "kurPirkti":     str(raw.get("kurPirkti") or raw.get("parduotuvė") or raw.get("store") or ""),
        "makroNauda":    str(raw.get("makroNauda") or raw.get("macroBenefit") or raw.get("benefit") or ""),
    }

def handle_shopping_advice(body):
    grocery_list = body.get("groceryList", [])
    grocery_list = grocery_list[:100] if isinstance(grocery_list, list) else []
    budget       = body.get("budget", 50)

    prompt = (
        f"You are a smart grocery advisor for a health-focused shopper in Vilnius, Lithuania.\n"
        f"Current grocery list: {json.dumps(grocery_list)}\n"
        f"Weekly budget: €{budget}\n"
        f"Available groceries this week: {json.dumps(deals_summary(_active_deals()))}\n\n"
        'Return a JSON array of up to 5 shopping recommendations, each with EXACTLY these keys:\n'
        '{"produktas": string, "priezastis": string, "apytiksleCena": string (e.g. "3.99 €"), "kurPirkti": string, "makroNauda": string}\n'
        "Sort best-value first. Return ONLY the JSON array, no markdown."
    )
    raw = groq_json(
        [{"role": "user", "content": prompt}],
        [{"produktas": "Chicken Breast", "priezastis": "Best protein value",
          "apytiksleCena": "3.99 €", "kurPirkti": "Rimi", "makroNauda": "20g protein per 100g"}]
    )
    if not isinstance(raw, list):
        raw = []
    return [x for x in (_normalize_advice_item(r) for r in raw) if x]

# Simple in-memory LRU recipe cache — avoids re-generating the same meal while
# staying bounded so a caller sending many distinct mealNames can't grow it without
# limit (memory-exhaustion). Oldest entry is evicted once the cap is reached.
_RECIPE_CACHE_MAX = 500
_recipe_cache: "collections.OrderedDict[str, dict]" = collections.OrderedDict()

def handle_recipe(body):
    meal_name = str(body.get("mealName", "")).strip()[:120]
    if not meal_name:
        return {"error": "mealName required"}

    cache_key = meal_name.lower()
    if cache_key in _recipe_cache:
        _recipe_cache.move_to_end(cache_key)   # mark as most-recently used
        return _recipe_cache[cache_key]

    deals = deals_summary(_active_deals(), max_items=10)

    prompt = (
        f"Write a simple home recipe for: {meal_name}\n"
        f"Available affordable groceries to use as ingredients: {json.dumps(deals)}\n"
        "Return ONLY this JSON:\n"
        '{"prepTime":int,"cookTime":int,"servings":int,'
        '"ingredients":[{"name":str,"amount":str}],'
        '"steps":["step 1...","step 2..."],'
        '"tip":str}'
        "\nMax 5 ingredients, 5 steps. Keep it practical."
    )

    result = groq_json(
        [{"role": "user", "content": prompt}],
        fallback={
            "prepTime": 10, "cookTime": 20, "servings": 2,
            "ingredients": [{"name": meal_name, "amount": "as needed"}],
            "steps": ["Prepare ingredients.", "Cook until done.", "Serve and enjoy."],
            "tip": "Season to taste."
        },
        json_object=True,       # recipe is a single JSON object
    )
    result["mealName"] = meal_name
    _recipe_cache[cache_key] = result
    _recipe_cache.move_to_end(cache_key)
    while len(_recipe_cache) > _RECIPE_CACHE_MAX:
        _recipe_cache.popitem(last=False)      # evict least-recently used
    return result


def handle_agent_chat(body):
    # Clamp all user-controlled inputs to bound prompt size / Groq token cost.
    message  = str(body.get("message", ""))[:2000]
    history  = body.get("history", [])
    history  = history if isinstance(history, list) else []
    user_ctx = body.get("userContext", {})
    user_ctx = user_ctx if isinstance(user_ctx, dict) else {}

    goal        = str(user_ctx.get("goal", "maintain"))[:20]
    target_kcal = user_ctx.get("targetCalories", 2000)
    consumed    = user_ctx.get("caloriesConsumed", 0)
    fav_names   = (user_ctx.get("favoriteFoods") or [])[:30]

    fav_str = ", ".join(fav_names) if fav_names else "not specified"
    system_prompt = (
        "Mealio AI — nutrition & grocery assistant, Vilnius.\n"
        f"User: {goal} goal, {target_kcal} kcal/day, {consumed} consumed today.\n"
        f"Favourite foods: {fav_str}\n"
        f"Popular groceries: {json.dumps(deals_summary(_active_deals(), max_items=8))}\n"
        "Reply in 2-3 short sentences. Suggest affordable groceries when relevant. Do not claim items are on sale or discounted."
    )

    messages = [{"role": "system", "content": system_prompt}]
    for turn in history[-6:]:
        if not isinstance(turn, dict):
            continue
        role = "assistant" if turn.get("role") == "assistant" else "user"
        messages.append({"role": role, "content": str(turn.get("content", ""))[:2000]})
    messages.append({"role": "user", "content": message})

    return {"reply": groq_text(messages)}

# ---------------------------------------------------------------------------
# Local dev entrypoint
# ---------------------------------------------------------------------------
# `python app.py` runs the SAME Flask app that gunicorn serves in production
# (see server.py), so auth / rate limiting / validation live in exactly one
# place and can't drift between dev and prod. The import is deferred to here so
# importing app.py for tests never pulls in Flask.

if __name__ == "__main__":
    from server import app as flask_app

    port = int(os.environ.get("PORT", 5000))
    print(f"Mealio backend (dev) running on port {port} — model: {GROQ_MODEL}")
    flask_app.run(host="0.0.0.0", port=port)
