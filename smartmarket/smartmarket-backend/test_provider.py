"""Production provider contract; no real keys or network calls."""
import os
from types import SimpleNamespace
os.environ.setdefault('GROQ_API_KEY','test-not-a-real-key')
import app
import ai_usage


def fake_completion(content, finish='stop'):
    return SimpleNamespace(choices=[SimpleNamespace(finish_reason=finish,
        message=SimpleNamespace(content=content,reasoning='must not reach user'))])


def test_gpt_oss_uses_supported_completion_options(monkeypatch):
    calls=[]
    monkeypatch.setattr(app,'GROQ_MODEL','openai/gpt-oss-120b')
    def create(**kwargs):
        calls.append(kwargs)
        return fake_completion('{"answer":"ok"}')
    monkeypatch.setattr(app,'groq_client',SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=create))))
    assert app.groq_json([{'role':'user','content':'JSON please'}],{},json_object=True) == {'answer':'ok'}
    assert calls[0].get('include_reasoning') is False
    assert calls[0].get('reasoning_effort') == 'low'
    assert 'max_completion_tokens' in calls[0] and 'max_tokens' not in calls[0]
    assert calls[0]['max_completion_tokens'] <= 8192
    assert 'reasoning_format' not in calls[0]


def test_truncated_completion_is_not_billed_as_success(monkeypatch):
    monkeypatch.setattr(app,'groq_client',SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(
        create=lambda **kwargs: fake_completion('{"answer":"incomplete"}','length')))))
    ai_usage.succeeded.set(False)
    assert app.groq_json([],{'fallback':True}) == {'fallback':True}
    assert ai_usage.succeeded.get() is False


def test_chat_only_returns_final_content(monkeypatch):
    calls=[]
    monkeypatch.setattr(app,'GROQ_MODEL','openai/gpt-oss-120b')
    def create(**kwargs): calls.append(kwargs);return fake_completion('Final answer')
    monkeypatch.setattr(app,'groq_client',SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=create))))
    assert app.groq_text([]) == 'Final answer'
    assert calls[0].get('include_reasoning') is False
