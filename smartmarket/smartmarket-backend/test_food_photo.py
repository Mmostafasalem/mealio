import json
from types import SimpleNamespace

import app as business
from ai_accounts import PATH_COSTS

PHOTO = "/9j/" + "A" * 200


def fake_provider(monkeypatch, content, calls):
    def create(**kwargs):
        calls.append(kwargs)
        return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=content), finish_reason="stop")])
    monkeypatch.setattr(business, "groq_client", SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=create))))


def test_photo_returns_clean_names_and_grams_from_the_vision_model(monkeypatch):
    calls = []
    raw = {"foods": [{"name": "  Banana ", "grams": 120}, {"name": "Rice", "grams": 99999},
                     {"name": "", "grams": 10}, {"name": "Egg", "grams": "two"}] + [{"name": f"F{i}", "grams": 5} for i in range(20)]}
    fake_provider(monkeypatch, json.dumps(raw), calls)
    out = business.handle_food_photo({"image": PHOTO})
    assert calls[0]["model"] == business.GROQ_VISION_MODEL
    assert calls[0]["messages"][0]["content"][1]["image_url"]["url"].startswith("data:image/jpeg;base64,")
    assert out["foods"][0] == {"name": "Banana", "grams": 120}
    assert out["foods"][1] == {"name": "Rice", "grams": 1500}
    assert {"name": "Egg", "grams": 1} in out["foods"]
    assert len(out["foods"]) <= 8
    assert all(set(f) == {"name", "grams"} for f in out["foods"])


def test_photo_rejects_what_is_not_a_jpeg_without_calling_the_provider(monkeypatch):
    calls = []
    fake_provider(monkeypatch, "{}", calls)
    for body in [{}, {"image": 5}, {"image": "short"}, {"image": "iVBOR" + "A" * 200}, {"image": "!!!" * 100},
                 {"image": "/9j/" + "A" * 200_000}]:
        assert business.handle_food_photo(body)["foods"] == []
    assert calls == []


def test_a_photo_costs_two_credits():
    assert PATH_COSTS["/api/food-photo"] == 2
