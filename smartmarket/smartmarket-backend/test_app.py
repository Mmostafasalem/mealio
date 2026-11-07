"""
Backend tests for the Mealio API. Run: `pytest -q`

Self-contained — sets the required env vars before importing the app, and stubs
out Groq / Open Food Facts so no network or API keys are needed.
"""
import os

os.environ.setdefault("GROQ_API_KEY", "test")
os.environ.setdefault("APP_API_KEY", "testkey")

import pytest

import app

try:
    import server
    HAS_FLASK = True
except Exception:
    HAS_FLASK = False


@pytest.fixture(autouse=True)
def _stub_ai(monkeypatch):
    monkeypatch.setattr(app, "nutrition_for", lambda name=None, barcode=None: None)
    monkeypatch.setattr(app, "groq_json", lambda messages, fallback=None, **kw: fallback)
    monkeypatch.setattr(app, "groq_text", lambda messages: "ok")


# ---------------------------------------------------------------------------
# Business logic
# ---------------------------------------------------------------------------

def test_bmr_valid():
    r = app.handle_bmr({"weight": 80, "height": 180, "age": 30,
                        "gender": "male", "activityLevel": "moderate"})
    assert r["bmr"] > 0
    assert r["loseCalories"] < r["maintainCalories"] < r["gainCalories"]


@pytest.mark.parametrize("body", [
    {"weight": 5, "height": 180, "age": 30},     # too light
    {"weight": 80, "height": 50, "age": 30},     # too short
    {"weight": 80, "height": 180, "age": 5},     # too young
])
def test_bmr_rejects_out_of_range(body):
    with pytest.raises(app.RequestError):
        app.handle_bmr(body)


def test_catalog_and_deals():
    cat = app.get_product_catalog()
    assert len(cat) >= 10
    deals = app.handle_deals({})
    assert deals and all(d["isOnSale"] for d in deals)
    # iOS Deal.id is a non-optional Int — every deal id must be an int.
    assert all(isinstance(d["id"], int) for d in deals)


def test_meal_plan_has_all_seven_days():
    mp = app.handle_meal_plan({"user": {}, "bmrData": {"maintainCalories": 2000},
                               "goal": "maintain"})
    for day in app.CANONICAL_DAYS:
        assert day in mp


def test_meal_plan_includes_grocery_list_in_prompt(monkeypatch):
    """Regression: the cart / grocery items the client sends must reach the ONLINE
    meal-plan prompt, so the AI plan is built around what the user is actually
    buying (previously only the offline fallback used the cart). The iOS client
    threads ShoppingCartService.planDeals() into MealPlanRequest.groceryList and
    the backend must surface those names to the model."""
    captured = {}

    def _capture(messages, fallback=None, **kw):
        captured["messages"] = messages
        return fallback

    monkeypatch.setattr(app, "groq_json", _capture)
    app.handle_meal_plan({
        "user": {}, "bmrData": {"maintainCalories": 2000}, "goal": "maintain",
        "groceryList": [
            {"name": "Zucchini Noodles"},
            {"name": "Tempeh Strips"},
        ],
    })
    user_prompt = captured["messages"][-1]["content"]
    assert "Zucchini Noodles" in user_prompt
    assert "Tempeh Strips" in user_prompt


# ---------------------------------------------------------------------------
# Security / input hardening
# ---------------------------------------------------------------------------

def test_ai_catalog_summary_has_estimates_without_fabricated_savings():
    rows = app.deals_summary([{'name':'Milk','store':'Rimi','discountedPrice':1.5,
                              'discount':75,'category':'dairy'}])
    assert rows[0]['estimated_price'] == 1.5
    assert not {'d','discount','discountPercent','originalPrice'} & rows[0].keys()

def test_agent_chat_clamps_input(monkeypatch):
    captured = {}
    monkeypatch.setattr(app, "groq_text", lambda messages: captured.setdefault("m", messages) or "ok")
    app.handle_agent_chat({
        "message": "x" * 9000,
        "history": [{"role": "user", "content": "y" * 9000}] * 50,
    })
    assert len(captured["m"][-1]["content"]) <= 2000      # message clamped
    assert len(captured["m"]) - 2 <= 6                    # history clamped


def test_rate_limiter_triggers():
    ip = "203.0.113.5"
    hits = [app._is_rate_limited(ip) for _ in range(app._RATE_MAX + 5)]
    assert hits[-1] is True


def test_handlers_tolerate_wrong_types():
    # Malformed field types must degrade gracefully, never raise (would be a 500).
    app.handle_bmr({"gender": 123, "weight": 80, "height": 180, "age": 30})
    app.handle_meal_plan({"user": "not-a-dict",
                          "bmrData": {"maintainCalories": "abc", "macros": "x"},
                          "goal": "lose"})


@pytest.mark.skipif(not HAS_FLASK, reason="flask not installed")
def test_server_security():
    c = server.app.test_client()
    H = {"X-API-Key": "testkey", "Content-Type": "application/json"}
    assert c.get("/api/health").status_code == 401                 # no key
    assert c.get("/api/health", headers={"X-API-Key": "bad"}).status_code == 401
    ok = c.get("/api/health", headers=H)
    assert ok.status_code == 200
    assert ok.headers.get("X-Content-Type-Options") == "nosniff"
    assert c.post("/api/bmr", data=b"x" * 300_000, headers=H).status_code == 413
    assert c.get("/api/nope", headers=H).status_code == 404


@pytest.mark.skipif(not HAS_FLASK, reason="flask not installed")
def test_malformed_json_is_rejected():
    c = server.app.test_client()
    H = {"X-API-Key": "testkey", "Content-Type": "application/json"}
    assert c.post("/api/bmr", data=b"garbage", headers=H).status_code == 400
    assert c.post("/api/bmr", data=b'"a-string"', headers=H).status_code == 400
    # Malformed types reach the handler and must NOT 500.
    assert c.post("/api/bmr", data=b'{"gender":123,"weight":80,"height":180,"age":30}',
                  headers=H).status_code == 200


@pytest.mark.skipif(not HAS_FLASK, reason="flask not installed")
def test_spoofed_forwarded_for_cannot_bypass_rate_limit():
    """An attacker rotating the client-controlled left part of X-Forwarded-For
    must still be rate-limited: the real (rightmost, proxy-appended) IP is used."""
    c = server.app.test_client()
    H = {"X-API-Key": "testkey"}
    app._rate_buckets.clear()
    codes = [
        c.get("/api/health",
              headers={**H, "X-Forwarded-For": f"9.9.9.{i}, 203.0.113.99"}).status_code
        for i in range(app._RATE_MAX + 10)
    ]
    assert 429 in codes
    app._rate_buckets.clear()
