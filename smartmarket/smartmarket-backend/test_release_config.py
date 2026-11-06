from release_config import production_errors


def configured():
    return {'MEALIO_ENV':'production','APP_API_KEY':'a'*64,'GROQ_API_KEY':'gsk_'+'b'*40,
            'GROQ_MODEL':'openai/gpt-oss-120b','AI_ACCOUNTS_ENABLED':'0'}


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
    response=server.app.test_client().get('/api/readiness',headers={'X-API-Key':'s'*64})
    assert response.status_code == 200
    assert response.get_json()['onlineAIEnabled'] is False
