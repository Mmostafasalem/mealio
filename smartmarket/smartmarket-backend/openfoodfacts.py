"""
Open Food Facts nutrition lookup.

Provides real per-100g nutrition (kcal, protein, carbs, fat) for a product by
barcode only (exact). There is no name search: it returned whatever product
ranked first, which is not reliable enough to show as a food's nutrition.
Successful lookups are cached on disk so repeated/cold starts stay fast.

All failures degrade gracefully to None so the caller can fall back to its own
category-average estimates. Open Food Facts is free, open data (ODbL).
"""

import atexit
import json
import os
import tempfile
import threading
import time
import urllib.parse
import urllib.request

_OFF_BASE = "https://world.openfoodfacts.org"
# OFF asks every caller to identify itself with a descriptive User-Agent.
_USER_AGENT = "Nourlo/1.0 (nourlo.app.support@gmail.com)"
_TIMEOUT = 4  # seconds — keep cold-start catalog builds bounded

_CACHE_PATH = os.path.join(os.path.dirname(__file__), "off_cache.json")
_cache: dict = {}
_loaded = False
# Guards _cache and the bookkeeping below: catalog rebuilds can run on several
# threads. Never held while writing the file.
_lock = threading.RLock()
# Serialises writes of the file. A snapshot is taken inside it, so writes land
# in the order their snapshots were taken and an older one never replaces a newer one.
_write_lock = threading.Lock()

# New lookups are written in batches, not one file rewrite per lookup: after
# this many new entries, or at the next new entry once the oldest unsaved one is
# this old. A crash loses at most the unsaved batch (re-fetched next time).
# `flush()` writes whatever is pending; it runs at the end of a catalog build
# and at exit.
_SAVE_EVERY = 25
_SAVE_AFTER_SECONDS = 30.0
_unsaved = 0
_unsaved_since = 0.0


def _load_cache() -> None:
    global _loaded, _cache
    with _lock:
        if _loaded:
            return
        try:
            with open(_CACHE_PATH, encoding="utf-8") as f:
                loaded = json.load(f)
            # Only barcode entries are used; name-search entries from older
            # versions are dropped.
            _cache = ({k: v for k, v in loaded.items() if isinstance(k, str) and k.startswith("b:")}
                      if isinstance(loaded, dict) else {})
        except (OSError, ValueError):
            _cache = {}
        _loaded = True


def _write_file(snapshot: dict) -> bool:
    """Write `snapshot` atomically: a temp file in the same folder, then
    os.replace, so a reader or a crash never sees a truncated file."""
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(prefix=".off_cache.", suffix=".tmp",
                                   dir=os.path.dirname(_CACHE_PATH))
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(snapshot, f)
        os.replace(tmp, _CACHE_PATH)
        tmp = None
        return True
    except OSError as exc:
        print(f"[OFF] cache write failed: {exc}")
        return False
    finally:
        if tmp is not None:
            try:
                os.remove(tmp)
            except OSError:
                pass


def _save_cache() -> None:
    """Write the cache now. The dict is copied under the lock and written
    outside it, so lookups on other threads aren't held up by the disk."""
    global _unsaved
    with _write_lock:
        with _lock:
            if not _loaded:
                return  # never replace the file with a cache that was never read
            snapshot = dict(_cache)
            pending = _unsaved
            _unsaved = 0
        if not _write_file(snapshot):
            with _lock:
                _unsaved += pending  # retried with the next batch or flush


def flush() -> None:
    """Write any lookups not yet saved. Cheap when there are none."""
    with _lock:
        if _unsaved == 0:
            return
    _save_cache()


def _note_new_entry() -> bool:
    """Count a new entry (call with _lock held); True when a batch is due."""
    global _unsaved, _unsaved_since
    if _unsaved == 0:
        _unsaved_since = time.monotonic()
    _unsaved += 1
    return _unsaved >= _SAVE_EVERY or time.monotonic() - _unsaved_since >= _SAVE_AFTER_SECONDS


atexit.register(flush)


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


def nutrition_for(barcode: str | None = None):
    """
    Return {kcal, protein, carbs, fat} per 100g for a barcode, or None if
    unavailable. Successful lookups are cached.
    """
    barcode = str(barcode).strip() if barcode else ""
    if not barcode:
        return None
    key = f"b:{barcode}"

    _load_cache()
    with _lock:
        if key in _cache:
            return _cache[key]

    result = _by_barcode(barcode)

    # Only cache successful lookups. A None here may be a transient OFF outage
    # (e.g. a 503), so we don't poison the cache — it'll be retried next time.
    # Bound the cache so the on-disk file can't grow without limit.
    if result is not None:
        due = False
        with _lock:
            if len(_cache) < 5000 and key not in _cache:
                _cache[key] = result
                due = _note_new_entry()
        if due:
            _save_cache()
    return result
