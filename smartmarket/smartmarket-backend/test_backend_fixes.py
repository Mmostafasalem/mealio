"""Regression tests for the backend audit fixes (auth compare, JSON parsing,
target clamps, BMR floors, cache thread safety, atomic Open Food Facts cache)."""
import concurrent.futures
import json
import os
import types

os.environ.setdefault("GROQ_API_KEY", "test")
os.environ.setdefault("APP_API_KEY", "testkey")

import pytest

import ai_usage
import app
import openfoodfacts
import server

DEEP = b"[" * 100_000 + b"]" * 100_000   # 200 KB: under the body cap, past the recursion limit
JSON_HEADERS = {"X-API-Key": "testkey", "Content-Type": "application/json"}


@pytest.fixture(autouse=True)
def _stub_ai(monkeypatch):
    monkeypatch.setattr(app, "nutrition_for", lambda name=None, barcode=None: None)
    monkeypatch.setattr(app, "groq_json", lambda messages, fallback=None, **kw: fallback)
    monkeypatch.setattr(app, "groq_text", lambda messages: "ok")
    app._rate_buckets.clear()
    yield
    app._rate_buckets.clear()


# --- X-API-Key -----------------------------------------------------------------

@pytest.mark.parametrize("key", ["ключ", "testkeyé", "ÿ" * 7, "testkey "])
def test_non_ascii_api_key_is_401_not_500(key):
    c = server.app.test_client()
    # Werkzeug sends header values as latin-1; encode so any code point fits.
    raw = key.encode("utf-8").decode("latin-1")
    response = c.get("/api/health", headers={"X-API-Key": raw})
    assert response.status_code == 401
    assert response.get_json() == {"error": "Unauthorized"}


def test_correct_api_key_still_accepted():
    assert server.app.test_client().get("/api/health", headers={"X-API-Key": "testkey"}).status_code == 200


# --- JSON parsing --------------------------------------------------------------

def test_deep_json_really_overflows_the_parser():
    with pytest.raises(RecursionError):
        json.loads(DEEP)


def test_deeply_nested_json_is_400_over_http():
    response = server.app.test_client().post("/api/bmr", data=DEEP, headers=JSON_HEADERS)
    assert response.status_code == 400
    assert response.get_json() == {"error": "Invalid JSON body"}


def test_body_helper_rejects_deep_json_for_every_route():
    # Every POST handler reads its body through _body(); AI routes are covered
    # end to end with a signed-in session in test_ai_accounts.
    with server.app.test_request_context("/api/meal-plan", method="POST", data=DEEP,
                                         content_type="application/json"):
        with pytest.raises(app.RequestError) as error:
            server._body()
    assert error.value.status == 400


@pytest.mark.parametrize("body", [b"\xff\xfe{", b'{"a":', b"null"])
def test_bad_bodies_are_400(body):
    response = server.app.test_client().post("/api/bmr", data=body, headers=JSON_HEADERS)
    assert response.status_code == 400


def test_empty_body_still_uses_defaults():
    assert server.app.test_client().post("/api/bmr", headers=JSON_HEADERS).status_code == 200


@pytest.mark.parametrize("path", ["/api/auth/guest", "/api/auth/apple"])
def test_deeply_nested_json_is_400_on_sign_in(path):
    response = server.app.test_client().post(path, data=DEEP, headers={"Content-Type": "application/json"})
    assert response.status_code == 400
    assert response.get_json()["code"] == "invalid_request"


def test_deeply_nested_apple_notification_is_not_500():
    response = server.app.test_client().post("/api/auth/apple/notifications", data=DEEP,
                                             headers={"Content-Type": "application/json"})
    assert response.status_code != 500


def test_parse_json_body_helper():
    from ai_account_routes import _INVALID_JSON, parse_json_body
    assert parse_json_body(b'{"a": 1}') == {"a": 1}
    assert parse_json_body(DEEP) is _INVALID_JSON
    assert parse_json_body(b"\xff") is _INVALID_JSON
    assert parse_json_body(b"not json") is _INVALID_JSON


# --- Meal-plan and chat targets -----------------------------------------------

def _captured_plan(monkeypatch, body):
    captured = {}
    def fake(messages, fallback=None, **kw):
        captured.update(messages=messages, fallback=fallback, validator=kw.get("validator"))
        return fallback
    monkeypatch.setattr(app, "groq_json", fake)
    result = app.handle_meal_plan(body)
    return captured, result


@pytest.mark.parametrize("value,expected", [(-5000, 1200), (0, 1200), (1000, 1200), (99_999_999, 6000),
                                            ("1e400", 2000), (2400, 2400)])
def test_meal_plan_target_is_clamped(monkeypatch, value, expected):
    captured, result = _captured_plan(monkeypatch, {"bmrData": {"maintainCalories": value}, "goal": "maintain"})
    assert f"Daily target: {expected} kcal" in captured["messages"][-1]["content"]
    for day in app.CANONICAL_DAYS:
        assert all(meal["kcal"] > 0 for meal in result[day].values() if isinstance(meal, dict))


@pytest.mark.parametrize("goal,field", [("lose", "loseCalories"), ("gain", "gainCalories")])
def test_goal_targets_are_clamped(monkeypatch, goal, field):
    captured, _ = _captured_plan(monkeypatch, {"bmrData": {"maintainCalories": 2000, field: -300}, "goal": goal})
    assert "Daily target: 1200 kcal" in captured["messages"][-1]["content"]
    captured, _ = _captured_plan(monkeypatch, {"bmrData": {"maintainCalories": 2000, field: 10**9}, "goal": goal})
    assert "Daily target: 6000 kcal" in captured["messages"][-1]["content"]


@pytest.mark.parametrize("gender,expected", [("male", 1500), ("MALE", 1500), ("female", 1200),
                                             ("other", 1200), (None, 1200), (42, 1200)])
def test_loss_target_never_goes_under_the_gender_floor(monkeypatch, gender, expected):
    user = {} if gender is None else {"gender": gender}
    captured, _ = _captured_plan(monkeypatch, {"user": user, "goal": "lose",
                                               "bmrData": {"maintainCalories": 2200, "loseCalories": 900}})
    assert f"Daily target: {expected} kcal" in captured["messages"][-1]["content"]


def test_loss_floor_never_forces_a_surplus(monkeypatch):
    # A man whose maintenance is under 1500 is not planned above maintenance.
    captured, _ = _captured_plan(monkeypatch, {"user": {"gender": "male"}, "goal": "lose",
                                               "bmrData": {"maintainCalories": 1400, "loseCalories": 900}})
    assert "Daily target: 1400 kcal" in captured["messages"][-1]["content"]
    # A sensible deficit above the floor is kept as sent.
    captured, _ = _captured_plan(monkeypatch, {"user": {"gender": "male"}, "goal": "lose",
                                               "bmrData": {"maintainCalories": 2600, "loseCalories": 2100}})
    assert "Daily target: 2100 kcal" in captured["messages"][-1]["content"]
    # Missing loseCalories: maintenance minus 500, still floored.
    captured, _ = _captured_plan(monkeypatch, {"user": {"gender": "male"}, "goal": "lose",
                                               "bmrData": {"maintainCalories": 1800}})
    assert "Daily target: 1500 kcal" in captured["messages"][-1]["content"]


def test_huge_target_cannot_disable_plan_validation(monkeypatch):
    captured, _ = _captured_plan(monkeypatch, {"bmrData": {"maintainCalories": 99_999_999}})
    tiny_week = {day: {k: {"pavadinimas": "x", "kcal": n} for k, n in
                       zip(("pusryciai", "pietūs", "vakariene", "uzkandziai"), (100, 120, 90, 40))}
                 for day in app.CANONICAL_DAYS}
    assert not captured["validator"](tiny_week)


def test_macros_are_clamped(monkeypatch):
    captured, _ = _captured_plan(monkeypatch, {"bmrData": {"maintainCalories": 2000, "macros": {
        "protein": -50, "carbs": 10**8, "fat": 10**8}}})
    prompt = captured["messages"][-1]["content"]
    assert "Protein 0g | Carbs 900g | Fat 700g" in prompt


def test_chat_targets_are_clamped(monkeypatch):
    captured = {}
    monkeypatch.setattr(app, "groq_text", lambda messages: captured.setdefault("m", messages) and "ok")
    app.handle_agent_chat({"message": "hi", "userContext": {"targetCalories": -10, "caloriesConsumed": 10**9}})
    system = captured["m"][0]["content"]
    assert "1200 kcal/day, 20000 consumed today" in system


# --- /api/bmr -------------------------------------------------------------------

# Burns more than every floor, but a 500 kcal deficit would go below it.
BASE = {"weight": 60, "height": 160, "age": 50, "activityLevel": "sedentary"}


@pytest.mark.parametrize("gender,floor", [("male", 1500), ("female", 1200), ("other", 1200), ("unknown", 1200)])
def test_bmr_lose_target_has_safety_floor(gender, floor):
    r = app.handle_bmr({**BASE, "gender": gender})
    assert r["loseCalories"] == floor
    assert r["maintainCalories"] == r["tdee"]           # floor applies to weight loss only
    assert r["gainCalories"] == r["tdee"] + 500


def test_bmr_floor_does_not_raise_a_target_already_above_it():
    r = app.handle_bmr({"weight": 90, "height": 185, "age": 30, "gender": "male", "activityLevel": "very_active"})
    assert r["loseCalories"] == r["tdee"] - 500 > 1500


def test_bmr_gender_constants():
    body = {"weight": 70, "height": 175, "age": 30, "activityLevel": "sedentary"}
    base = 10 * 70 + 6.25 * 175 - 5 * 30
    assert app.handle_bmr({**body, "gender": "male"})["bmr"] == round(base + 5)
    assert app.handle_bmr({**body, "gender": "FEMALE"})["bmr"] == round(base - 161)
    assert app.handle_bmr({**body, "gender": "other"})["bmr"] == round(base - 78)
    assert app.handle_bmr({**body, "gender": "nonbinary"})["bmr"] == round(base - 78)
    assert app.handle_bmr(body)["bmr"] == round(base + 5)     # missing keeps the legacy male default


# --- Thread safety ------------------------------------------------------------

def test_recipe_cache_survives_concurrent_eviction(monkeypatch):
    def online(messages, fallback=None, **kw):
        ai_usage.succeeded.set(True)
        return dict(fallback)
    monkeypatch.setattr(app, "groq_json", online)
    monkeypatch.setattr(app, "_RECIPE_CACHE_MAX", 3)
    monkeypatch.setattr(app, "_recipe_cache", type(app._recipe_cache)())

    def hit(n):
        ai_usage.account.set("account-under-test")   # recipes are cached per account
        for i in range(200):
            result = app.handle_recipe({"mealName": f"dish {(n + i) % 7}"})
            assert result["mealName"].startswith("dish")
        return True

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        assert all(pool.map(hit, range(8)))
    assert 0 < len(app._recipe_cache) <= 3


def test_recipe_cache_is_per_account_and_off_without_one(monkeypatch):
    calls = []
    def online(messages, fallback=None, **kw):
        calls.append(True)
        ai_usage.succeeded.set(True)
        return dict(fallback)
    monkeypatch.setattr(app, "groq_json", online)
    monkeypatch.setattr(app, "_recipe_cache", type(app._recipe_cache)())
    body = {"mealName": "Grandma's secret soup"}
    ai_usage.account.set("account-a")
    app.handle_recipe(body); app.handle_recipe(body)
    assert len(calls) == 1                      # the same account reuses its own recipe
    ai_usage.account.set("account-b")
    app.handle_recipe(body)
    assert len(calls) == 2                      # another account never gets account A's entry
    ai_usage.account.set(None)
    app.handle_recipe(body); app.handle_recipe(body)
    assert len(calls) == 4 and len(app._recipe_cache) == 2   # unknown account: no caching


def test_curated_catalog_never_searches_open_food_facts_by_name(monkeypatch):
    lookups = []
    monkeypatch.setattr(app, "nutrition_for", lambda **kw: lookups.append(kw))
    monkeypatch.setattr(app, "_CATALOG_CACHE", {"data": None, "ts": 0.0})
    catalog = {p["name"]: p for p in app.get_product_catalog()}
    assert lookups == []                        # every curated item carries its own nutrition
    assert all(p["nutritionSource"] == "curated" for p in catalog.values())
    assert (catalog["Banana"]["kcalPer100g"], catalog["Banana"]["carbsPer100g"]) == (89, 22.8)
    assert (catalog["Chicken breast"]["kcalPer100g"], catalog["Chicken breast"]["proteinPer100g"]) == (120, 22.5)
    assert (catalog["Oats"]["kcalPer100g"], catalog["Oats"]["fatPer100g"]) == (379, 6.5)
    # An item with neither nutrition nor barcode gets the category average, not a name search.
    assert app._resolve_nutrition({"name": "Banana", "category": "fruit"})[-1] == "estimated"
    assert not hasattr(openfoodfacts, "_by_name")


def test_rate_limit_counts_an_ipv6_network_not_one_address():
    assert app.network_key("2001:db8:1:2:aaaa::1") == app.network_key("2001:db8:1:2:bbbb::2") == "2001:db8:1:2::/64"
    assert app.network_key("2001:db8:1:3::1") != app.network_key("2001:db8:1:2::1")
    assert app.network_key("198.51.100.7") == "198.51.100.7"
    assert app.network_key("::ffff:198.51.100.7") == "198.51.100.7"
    assert app.network_key("not an address") == "not an address"
    limited = [app._is_rate_limited(f"2001:db8:77:1::{n:x}") for n in range(app._RATE_MAX + 5)]
    assert limited.count(False) == app._RATE_MAX


def test_rate_limiter_is_exact_under_threads():
    ip = "198.51.100.77"
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        limited = list(pool.map(lambda _: app._is_rate_limited(ip), range(app._RATE_MAX * 2)))
    assert limited.count(False) == app._RATE_MAX


# --- Open Food Facts cache ------------------------------------------------------

@pytest.fixture
def off_cache(tmp_path, monkeypatch):
    path = tmp_path / "off_cache.json"
    monkeypatch.setattr(openfoodfacts, "_CACHE_PATH", str(path))
    monkeypatch.setattr(openfoodfacts, "_cache", {})
    monkeypatch.setattr(openfoodfacts, "_loaded", True)
    monkeypatch.setattr(openfoodfacts, "_unsaved", 0)
    return path


def test_off_cache_write_is_atomic(off_cache, monkeypatch):
    openfoodfacts._cache["b:milk"] = {"kcal": 60}
    openfoodfacts._save_cache()
    assert json.loads(off_cache.read_text()) == {"b:milk": {"kcal": 60}}

    # A write that fails half-way leaves the old file intact and no temp files.
    openfoodfacts._cache["b:bread"] = {"kcal": 250}
    def broken_dump(obj, f):
        f.write('{"b:milk": {"kc')
        raise OSError("disk full")
    monkeypatch.setattr(openfoodfacts.json, "dump", broken_dump)
    openfoodfacts._save_cache()
    assert json.loads(off_cache.read_text()) == {"b:milk": {"kcal": 60}}
    assert [p.name for p in off_cache.parent.iterdir()] == ["off_cache.json"]


def test_off_cache_concurrent_lookups_keep_a_valid_file(off_cache, monkeypatch):
    monkeypatch.setattr(openfoodfacts, "_by_barcode", lambda barcode: {"kcal": len(barcode), "protein": 1.0,
                                                                  "carbs": 0.0, "fat": 0.0})
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lambda n: openfoodfacts.nutrition_for(barcode=f"food {n}"), range(210)))
    openfoodfacts.flush()
    stored = json.loads(off_cache.read_text())
    assert len(stored) == 210
    assert [p.name for p in off_cache.parent.iterdir()] == ["off_cache.json"]


def test_off_cache_is_saved_in_batches(off_cache, monkeypatch):
    monkeypatch.setattr(openfoodfacts, "_by_barcode", lambda barcode: {"kcal": 1, "protein": 1.0,
                                                                  "carbs": 0.0, "fat": 0.0})
    writes = []
    real_write = openfoodfacts._write_file
    monkeypatch.setattr(openfoodfacts, "_write_file", lambda snap: writes.append(len(snap)) or real_write(snap))
    every = openfoodfacts._SAVE_EVERY
    for n in range(every * 2 + 3):
        openfoodfacts.nutrition_for(barcode=f"food {n}")
    assert writes == [every, every * 2], "one write per batch, not per lookup"
    assert len(json.loads(off_cache.read_text())) == every * 2
    # A repeat lookup is served from memory and adds nothing to save.
    openfoodfacts.nutrition_for(barcode="food 0")
    openfoodfacts.flush()
    assert writes[-1] == every * 2 + 3
    assert len(json.loads(off_cache.read_text())) == every * 2 + 3
    openfoodfacts.flush()  # nothing pending: no write
    assert len(writes) == 3


def test_off_cache_saves_a_stale_batch_early(off_cache, monkeypatch):
    monkeypatch.setattr(openfoodfacts, "_by_barcode", lambda barcode: {"kcal": 1, "protein": 1.0,
                                                                  "carbs": 0.0, "fat": 0.0})
    clock = [1000.0]
    monkeypatch.setattr(openfoodfacts, "time", types.SimpleNamespace(monotonic=lambda: clock[0]))
    openfoodfacts.nutrition_for(barcode="first")
    assert not off_cache.exists()
    clock[0] += openfoodfacts._SAVE_AFTER_SECONDS + 1
    openfoodfacts.nutrition_for(barcode="second")
    assert set(json.loads(off_cache.read_text())) == {"b:first", "b:second"}


def test_off_cache_failed_write_is_retried(off_cache, monkeypatch):
    monkeypatch.setattr(openfoodfacts, "_by_barcode", lambda barcode: {"kcal": 1, "protein": 1.0,
                                                                  "carbs": 0.0, "fat": 0.0})
    real_write = openfoodfacts._write_file
    monkeypatch.setattr(openfoodfacts, "_write_file", lambda snap: False)
    openfoodfacts.nutrition_for(barcode="kept")
    openfoodfacts.flush()
    assert not off_cache.exists()
    monkeypatch.setattr(openfoodfacts, "_write_file", real_write)
    openfoodfacts.flush()
    assert set(json.loads(off_cache.read_text())) == {"b:kept"}


def test_unread_off_cache_is_never_written(off_cache, monkeypatch):
    monkeypatch.setattr(openfoodfacts, "_loaded", False)
    off_cache.write_text('{"b:old": {"kcal": 1}}')
    openfoodfacts._save_cache()
    assert json.loads(off_cache.read_text()) == {"b:old": {"kcal": 1}}


def test_bmr_loss_floor_never_exceeds_maintenance():
    from app import handle_bmr
    # A very small, older, sedentary person burns less than the 1200 kcal floor.
    out = handle_bmr({"weight": 38, "height": 140, "age": 80, "gender": "female", "activityLevel": "sedentary"})
    body = out[0] if isinstance(out, tuple) else out
    assert body["loseCalories"] <= body["tdee"] + 1
