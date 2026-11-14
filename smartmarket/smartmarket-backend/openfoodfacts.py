"""
Open Food Facts nutrition lookup.

Provides real per-100g nutrition (kcal, protein, carbs, fat) for a product by
barcode (preferred, exact) or by name search (fuzzy). Results — including
"not found" — are cached on disk so repeated/cold starts stay fast.

All failures degrade gracefully to None so the caller can fall back to its own
category-average estimates. Open Food Facts is free, open data (ODbL).
"""

import json
import os
import time
import urllib.parse
import urllib.request

_OFF_BASE = "https://world.openfoodfacts.org"
# OFF asks every caller to identify itself with a descriptive User-Agent.
_USER_AGENT = "Nourlo/1.0 (nutrition lookup; https://github.com/Mmostafasalem/mealio)"
_TIMEOUT = 4  # seconds — keep cold-start catalog builds bounded

_CACHE_PATH = os.path.join(os.path.dirname(__file__), "off_cache.json")
_cache: dict = {}
_loaded = False


def _load_cache() -> None:
    global _loaded, _cache
    if _loaded:
        return
    try:
        with open(_CACHE_PATH, encoding="utf-8") as f:
            _cache = json.load(f)
    except (FileNotFoundError, ValueError):
        _cache = {}
    _loaded = True


def _save_cache() -> None:
    try:
        with open(_CACHE_PATH, "w", encoding="utf-8") as f:
            json.dump(_cache, f)
    except OSError as exc:
        print(f"[OFF] cache write failed: {exc}")


def _http_json(url: str):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            return json.loads(resp.read().decode("utf-8", errors="replace"))
    except Exception as exc:
        print(f"[OFF] {url} -> {exc}")
        return None


def _num(value):
    try:
        return float(value)
    except (TypeError, ValueError, OverflowError):
        return None


def _extract(nutriments: dict):
    """Pull the four macros (per 100g) from an OFF nutriments object."""
    if not isinstance(nutriments, dict):
        return None

    kcal = _num(nutriments.get("energy-kcal_100g"))
    if kcal is None:
        kj = _num(nutriments.get("energy_100g"))  # OFF sometimes stores only kJ
        kcal = round(kj / 4.184) if kj is not None else None

    protein = _num(nutriments.get("proteins_100g"))
    carbs = _num(nutriments.get("carbohydrates_100g"))
    fat = _num(nutriments.get("fat_100g"))

    # Require at least energy + protein to consider the record usable.
    if kcal is None or protein is None:
        return None
    return {"kcal": kcal, "protein": protein, "carbs": carbs or 0.0, "fat": fat or 0.0}


def _by_barcode(barcode: str):
    url = f"{_OFF_BASE}/api/v2/product/{urllib.parse.quote(str(barcode))}.json?fields=nutriments"
    data = _http_json(url)
    if isinstance(data, dict) and data.get("status") == 1:
        return _extract((data.get("product") or {}).get("nutriments", {}))
    return None


def _by_name(name: str):
    params = urllib.parse.urlencode({
        "search_terms": name,
        "search_simple": 1,
        "action": "process",
        "json": 1,
        "page_size": 1,
        "fields": "nutriments",
    })
    data = _http_json(f"{_OFF_BASE}/cgi/search.pl?{params}")
    if isinstance(data, dict):
        products = data.get("products") or []
        if products:
            return _extract(products[0].get("nutriments", {}))
    return None


def nutrition_for(name: str | None = None, barcode: str | None = None):
    """
    Return {kcal, protein, carbs, fat} per 100g, or None if unavailable.
    Looks up by barcode first (exact), then by name. Cached (incl. misses).
    """
    key = f"b:{barcode}" if barcode else f"n:{(name or '').strip().lower()}"
    if key in ("b:", "n:"):
        return None

    _load_cache()
    if key in _cache:
        return _cache[key]

    result = None
    if barcode:
        result = _by_barcode(barcode)
    if result is None and name:
        result = _by_name(name)

    # Only cache successful lookups. A None here may be a transient OFF outage
    # (e.g. a 503), so we don't poison the cache — it'll be retried next time.
    # Bound the cache so the on-disk file can't grow without limit.
    if result is not None and len(_cache) < 5000:
        _cache[key] = result
        _save_cache()
    return result
