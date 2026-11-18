import pytest

from release_config import production_errors


def configured():
    return {'MEALIO_ENV':'production','APP_API_KEY':'a'*64,'GROQ_API_KEY':'gsk_'+'b'*40,
            'GROQ_MODEL':'openai/gpt-oss-120b','AI_ACCOUNTS_ENABLED':'0','TRUSTED_PROXY_COUNT':'1'}


def test_core_production_requires_real_shared_key_and_explicit_ai_choice():
    assert production_errors(configured()) == []
    config=configured();config['APP_API_KEY']='your_random_secret_here'
    assert 'APP_API_KEY' in production_errors(config)
    config=configured();del config['AI_ACCOUNTS_ENABLED']
    assert 'AI_ACCOUNTS_ENABLED' in production_errors(config)


def test_enabled_ai_cannot_silently_run_without_durable_accounts():
    config=configured();config['AI_ACCOUNTS_ENABLED']='1'
    assert 'AI_ACCOUNTS_READY' in production_errors(config,accounts_ready=False)
    assert production_errors(config,accounts_ready=True) == []


def test_retired_model_or_missing_provider_is_rejected():
    config=configured();config['GROQ_MODEL']='llama-3.3-70b-versatile'
    assert 'GROQ_MODEL' in production_errors(config)
    config=configured();config['AI_ACCOUNTS_ENABLED']='1';config['GROQ_API_KEY']='test'
    assert 'GROQ_API_KEY' in production_errors(config)


def test_error_report_never_contains_secret_values():
    config=configured();config['APP_API_KEY']='short-secret'
    assert 'short-secret' not in str(production_errors(config))


def test_catalog_only_production_does_not_require_a_provider_key():
    config=configured();config.pop('GROQ_API_KEY')
    assert production_errors(config) == []


def test_render_liveness_does_not_open_protected_api(monkeypatch):
    import os
    os.environ.setdefault('GROQ_API_KEY','test-not-real')
    import server
    monkeypatch.setattr(server,'APP_API_KEY','s'*64)
    client=server.app.test_client()
    live=client.get('/healthz')
    assert live.status_code == 200 and live.get_json() == {'status':'ok'}
    assert client.get('/api/health').status_code == 401
    assert client.get('/api/readiness').status_code == 401


def test_catalog_readiness_is_not_an_ai_inference_claim(monkeypatch):
    import os
    os.environ.setdefault('GROQ_API_KEY','test-not-real')
    import server
    monkeypatch.setattr(server,'APP_API_KEY','s'*64)
    monkeypatch.setenv('APP_API_KEY','s'*64)
    monkeypatch.setenv('AI_ACCOUNTS_ENABLED','0')
    monkeypatch.setenv('TRUSTED_PROXY_COUNT','1')
    response=server.app.test_client().get('/api/readiness',headers={'X-API-Key':'s'*64})
    assert response.status_code == 200
    assert response.get_json() == {'ready':True,'onlineAIEnabled':False}


def test_production_requires_an_explicit_proxy_count():
    for bad in (None,'','0','-1','two','11',1):
        config=configured()
        if bad is None: del config['TRUSTED_PROXY_COUNT']
        else: config['TRUSTED_PROXY_COUNT']=bad
        assert production_errors(config) == ['TRUSTED_PROXY_COUNT']
    config=configured();config['TRUSTED_PROXY_COUNT']='2'
    assert production_errors(config) == []


def test_health_and_readiness_reveal_no_model_or_setting_names(monkeypatch):
    import os
    os.environ.setdefault('GROQ_API_KEY','test-not-real')
    import server
    monkeypatch.setattr(server,'APP_API_KEY','s'*64)
    monkeypatch.setattr(server,'_is_rate_limited',lambda ip:False)
    monkeypatch.setenv('APP_API_KEY','short')
    monkeypatch.delenv('TRUSTED_PROXY_COUNT',raising=False)
    client=server.app.test_client()
    health=client.get('/api/health',headers={'X-API-Key':'s'*64})
    assert health.status_code == 200 and 'model' not in health.get_json()
    assert isinstance(health.get_json()['aiConfigured'],bool)
    readiness=client.get('/api/readiness',headers={'X-API-Key':'s'*64})
    assert readiness.status_code == 503
    assert set(readiness.get_json()) == {'ready','onlineAIEnabled'}
    assert readiness.get_json()['ready'] is False
    assert 'APP_API_KEY' not in readiness.get_data(as_text=True)


def test_no_cors_headers_and_options_is_rate_limited(monkeypatch):
    import os
    os.environ.setdefault('GROQ_API_KEY','test-not-real')
    import server
    monkeypatch.setattr(server,'APP_API_KEY','s'*64)
    seen=[]
    monkeypatch.setattr(server,'_is_rate_limited',lambda ip:seen.append(ip) or len(seen)>1)
    client=server.app.test_client()
    first=client.options('/api/products')
    assert first.status_code == 204 and len(seen) == 1
    assert not [h for h in first.headers.keys() if h.lower().startswith('access-control-')]
    assert first.headers['X-Content-Type-Options'] == 'nosniff'
    assert client.options('/api/products').status_code == 429


@pytest.mark.parametrize('path',['/api/meal-plan','/api/gap-fillers','/api/shopping-advice','/api/workout'])
def test_retired_ai_routes_are_gone_unless_switched_on(monkeypatch,path):
    import os
    os.environ.setdefault('GROQ_API_KEY','test-not-real')
    import server
    monkeypatch.setattr(server,'_is_rate_limited',lambda ip:False)
    monkeypatch.delenv('LEGACY_AI_ROUTES',raising=False)
    client=server.app.test_client()
    gone=client.post(path,json={})
    assert gone.status_code == 410 and gone.get_json()['code'] == 'gone'
    assert 'X-AI-Remaining' not in gone.headers
    # Switched back on, the route is an AI route again: it asks for a session.
    monkeypatch.setenv('LEGACY_AI_ROUTES','1')
    assert client.post(path,json={}).status_code in (401,503)
    # The routes the app does call are untouched by the switch.
    monkeypatch.delenv('LEGACY_AI_ROUTES')
    assert client.post('/api/agent-chat',json={}).status_code in (401,503)
    assert client.post('/api/recipe',json={}).status_code in (401,503)
