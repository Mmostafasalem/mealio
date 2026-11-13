"""No Apple/Groq credentials or network: exercise actual signatures and transactions."""
import concurrent.futures
import datetime as dt
from types import SimpleNamespace

import jwt
import pytest
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives.asymmetric import rsa

from ai_accounts import AccountError, AccountService, AppleAuthority


@pytest.fixture
def service(tmp_path):
    clock = [dt.datetime(2026, 11, 6, 12, tzinfo=dt.timezone.utc).timestamp()]
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    apple = AppleAuthority.__new__(AppleAuthority)
    apple.audience = 'com.mostafa.mealio'
    apple.keys = SimpleNamespace(get_signing_key_from_jwt=lambda _: SimpleNamespace(key=private.public_key()))
    apple.clock = lambda: clock[0]
    apple.exchange_code = lambda code: {'id_token': code, 'refresh_token': 'test-apple-refresh'}
    apple.refresh = lambda token: None
    apple.revoke = lambda token: None
    s = AccountService(str(tmp_path/'accounts.sqlite'), apple, Fernet(Fernet.generate_key()),
                       b'test-subject-secret-at-least-32-bytes', daily_limit=10, global_limit=1000,
                       clock=lambda: clock[0])
    s.test_clock, s.test_private = clock, private
    return s


def token(s, challenge, subject='person-one', **changes):
    now = s.test_clock[0]
    payload = dict(sub=subject, iss='https://appleid.apple.com', aud='com.mostafa.mealio',
                   iat=int(now), exp=int(now+300), nonce=challenge['nonce'])
    payload.update(changes)
    return jwt.encode(payload, s.test_private, algorithm='RS256', headers={'kid':'test'})


def login(s, subject='person-one'):
    c = s.challenge()
    t = token(s, c, subject)
    result = s.login(t, t, c['id'])
    return result, s.authenticate('Bearer '+result['token'])


def test_same_person_two_devices_share_allowance(service):
    a, user = login(service)
    b, other = login(service)
    assert a['token'] != b['token'] and user.account_id == other.account_id
    reservation = service.reserve(user, '/api/meal-plan')
    service.finish(reservation, succeeded=True, attempted=True)
    assert service.usage(other)['remaining'] == 5
    _, second_person = login(service, 'person-two')
    assert service.usage(second_person)['remaining'] == 10


@pytest.mark.parametrize('changes', [{'aud':'attacker.app'}, {'iss':'https://attacker.invalid'},
                                     {'exp':1}, {'nonce':'wrong'}, {'sub':''}])
def test_identity_claims_fail_closed(service, changes):
    c = service.challenge(); t = token(service, c, **changes)
    with pytest.raises(AccountError): service.login(t, t, c['id'])


def test_forged_signature_rejected(service):
    c = service.challenge()
    t = jwt.encode({'sub':'person-one','nonce':c['nonce']}, 'not-an-apple-key-and-at-least-32-bytes', algorithm='HS256')
    with pytest.raises(AccountError): service.login(t, t, c['id'])


def test_challenge_cannot_be_replayed_or_expired(service):
    c = service.challenge(); t = token(service,c)
    service.login(t,t,c['id'])
    with pytest.raises(AccountError): service.login(t,t,c['id'])
    c = service.challenge(); t = token(service,c)
    service.test_clock[0] += 301
    with pytest.raises(AccountError): service.login(t,t,c['id'])


def test_parallel_requests_cannot_overspend(service):
    _, user = login(service)
    def attempt(_):
        try: return service.reserve(user, '/api/agent-chat')
        except AccountError as e:
            assert e.code == 'ai_quota_exceeded'
            return None
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        reservations = list(pool.map(attempt,range(30)))
    assert sum(x is not None for x in reservations) == 10
    assert service.usage(user)['remaining'] == 0


def test_failure_and_cache_refund_once(service):
    _, user = login(service)
    r = service.reserve(user, '/api/meal-plan')
    service.finish(r,succeeded=False,attempted=True)
    service.finish(r,succeeded=False,attempted=True)
    assert service.usage(user)['remaining'] == 10
    r = service.reserve(user,'/api/recipe')
    service.finish(r,succeeded=False,attempted=False)
    assert service.usage(user)['remaining'] == 10


def test_reset_and_old_request_refund_do_not_credit_new_day(service):
    _, user = login(service)
    r = service.reserve(user,'/api/meal-plan')
    service.test_clock[0] = dt.datetime(2026,11,7,0,0,tzinfo=dt.timezone.utc).timestamp()
    assert service.usage(user)['remaining'] == 10
    service.finish(r,succeeded=False,attempted=True)
    assert service.usage(user)['remaining'] == 10


def test_worker_restart_retains_quota_and_session(service):
    signed,user = login(service)
    r = service.reserve(user,'/api/recipe'); service.finish(r,succeeded=True,attempted=True)
    other = AccountService(service.path,service.apple,service.cipher,service.subject_secret,
                           daily_limit=10,global_limit=1000,clock=service.clock)
    assert other.usage(other.authenticate('Bearer '+signed['token']))['remaining'] == 9


def test_abandoned_request_is_refunded_after_lease(service):
    _,user = login(service)
    service.reserve(user,'/api/meal-plan'); service.test_clock[0] += 181
    assert service.usage(user)['remaining'] == 10


def test_global_ceiling_is_not_a_user_quota(service):
    service.global_limit = 1
    _,user = login(service)
    r=service.reserve(user,'/api/recipe');service.finish(r,succeeded=False,attempted=True)
    with pytest.raises(AccountError) as e: service.reserve(user,'/api/agent-chat')
    assert e.value.code == 'ai_shared_capacity' and service.usage(user)['remaining'] == 10


def test_logout_and_delete_revoke_access(service):
    first,user = login(service); second,other=login(service)
    service.logout(user)
    with pytest.raises(AccountError): service.authenticate('Bearer '+first['token'])
    assert service.usage(other)['remaining'] == 10
    revoked=[];service.apple.revoke=lambda t:revoked.append(t)
    service.delete_account(other)
    assert revoked == ['test-apple-refresh']
    with pytest.raises(AccountError): service.authenticate('Bearer '+second['token'])


def test_failed_apple_revocation_does_not_claim_deletion(service):
    signed,user=login(service)
    def fail(_): raise AccountError('Apple unavailable',503,'ai_unavailable')
    service.apple.revoke=fail
    with pytest.raises(AccountError): service.delete_account(user)
    assert service.authenticate('Bearer '+signed['token']).account_id == user.account_id


@pytest.fixture
def http_app(service, monkeypatch):
    from flask import Flask, jsonify
    from ai_account_routes import register_ai_accounts
    import ai_usage
    app = Flask(__name__)
    monkeypatch.setattr(AccountService, 'from_env', classmethod(lambda cls: service))
    register_ai_accounts(app)

    @app.post('/api/agent-chat')
    def chat():
        from flask import request
        mode = request.get_json()['mode']
        ai_usage.attempted.set(mode != 'cached')
        ai_usage.responded.set(mode in ('online', 'unusable'))
        ai_usage.succeeded.set(mode == 'online')
        return jsonify({'reply': mode}), (400 if mode == 'invalid' else 200)

    return app


def test_http_identity_required_and_quota_headers(http_app, service):
    client = http_app.test_client()
    response = client.post('/api/agent-chat', json={'mode': 'online', 'accountID': 'person-one'})
    assert response.status_code == 401
    assert response.headers['X-AI-Error'] == 'ai_sign_in_required'
    c = client.get('/api/auth/apple/challenge').get_json()
    t = token(service, c)
    signed = client.post('/api/auth/apple', json={
        'identityToken': t, 'authorizationCode': t, 'challengeID': c['id']}).get_json()
    headers = {'Authorization': 'Bearer '+signed['token']}
    for remaining in range(9, -1, -1):
        response = client.post('/api/agent-chat', headers=headers, json={'mode': 'online'})
        assert response.status_code == 200
        assert int(response.headers['X-AI-Remaining']) == remaining
    response = client.post('/api/agent-chat', headers=headers, json={'mode': 'online'})
    assert response.status_code == 429 and response.headers['X-AI-Error'] == 'ai_quota_exceeded'
    assert int(response.headers['Retry-After']) == 43200
    assert client.get('/api/ai/usage', headers=headers).get_json()['remaining'] == 0


@pytest.mark.parametrize('mode', ['fallback', 'cached', 'invalid'])
def test_http_failures_do_not_spend_personal_credits(http_app, service, mode):
    signed, user = login(service)
    response = http_app.test_client().post('/api/agent-chat',
        headers={'Authorization': 'Bearer '+signed['token']}, json={'mode': mode})
    assert int(response.headers['X-AI-Remaining']) == 10
    assert service.usage(user)['remaining'] == 10
    assert response.headers['Cache-Control'] == 'no-store'


def test_disabled_account_service_fails_closed(http_app):
    http_app.config['AI_ACCOUNTS'] = None
    client = http_app.test_client()
    assert client.get('/api/auth/config').get_json() == {'enabled': False, 'guestEnabled': False, 'appleEnabled': False}
    response = client.post('/api/agent-chat', json={'mode': 'online'})
    assert response.status_code == 503 and response.headers['X-AI-Error'] == 'ai_unavailable'


def test_signed_apple_deletion_notification_and_stale_replay(http_app, service):
    signed, user = login(service)
    event_time = service.clock()
    payload = dict(iss='https://appleid.apple.com', aud='com.mostafa.mealio',
                   iat=int(event_time), jti='test-event',
                   events={'type':'account-deleted','sub':'person-one','event_time':event_time})
    notification = jwt.encode(payload, service.test_private, algorithm='RS256')
    client = http_app.test_client()
    assert client.post('/api/auth/apple/notifications', json={'payload': notification}).status_code == 204
    with pytest.raises(AccountError): service.authenticate('Bearer '+signed['token'])
    service.test_clock[0] += 10
    recreated, _ = login(service)
    assert client.post('/api/auth/apple/notifications', json={'payload': notification}).status_code == 204
    assert service.authenticate('Bearer '+recreated['token']).account_id == user.account_id
    assert client.post('/api/auth/apple/notifications', json={'payload':'forged'}).status_code == 401


def test_daily_apple_refresh_revocation_invalidates_every_session(service):
    first, _ = login(service)
    second, _ = login(service)
    service.test_clock[0] += 86401
    def revoked(_): raise AccountError('Sign in with Apple again.')
    service.apple.refresh = revoked
    with pytest.raises(AccountError): service.authenticate('Bearer '+first['token'])
    with pytest.raises(AccountError): service.authenticate('Bearer '+second['token'])


def test_apple_refresh_verifies_returned_identity(service):
    signed, user = login(service)
    service.test_clock[0] += 86401
    service.apple.refresh = lambda _: {'id_token': token(service, {'nonce':'unused'})}
    assert service.authenticate('Bearer '+signed['token']).account_id == user.account_id


def test_missing_persistent_storage_cannot_enable_accounts(monkeypatch):
    monkeypatch.setenv('AI_ACCOUNTS_ENABLED', '1')
    monkeypatch.setenv('AI_STATE_DB', '/tmp/ephemeral-accounts.sqlite')
    monkeypatch.delenv('AI_STATE_PERSISTENT', raising=False)
    with pytest.raises(ValueError): AccountService.from_env()


def test_delete_and_recreate_keeps_same_day_spending(service):
    _, user = login(service)
    for _ in range(2):
        r = service.reserve(user, '/api/meal-plan')
        service.finish(r, succeeded=True, attempted=True)
    service.delete_account(user)
    _, recreated = login(service)
    assert service.usage(recreated)['remaining'] == 0
    with pytest.raises(AccountError): service.reserve(recreated, '/api/recipe')
    service.test_clock[0] += 86400
    assert service.usage(recreated)['remaining'] == 10


@pytest.mark.parametrize('path,handler,body', [
    ('/api/meal-plan','handle_meal_plan',{}),
    ('/api/recipe','handle_recipe',{'mealName':'Unique invalid JSON recipe'}),
    ('/api/gap-fillers','handle_gap_fillers',{}),
    ('/api/shopping-advice','handle_shopping_advice',{}),
    ('/api/workout','handle_workout',{'kind':'gym','minutes':30}),
])
def test_unusable_json_keeps_only_minimal_charge_on_actual_endpoint(http_app, service, monkeypatch, path, handler, body):
    monkeypatch.setenv("GROQ_API_KEY", "test-not-a-real-key")
    import app as business
    from flask import jsonify, request
    monkeypatch.setattr(business, 'nutrition_for', lambda **kwargs: None)
    monkeypatch.setattr(business, 'groq_client', SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(
        create=lambda **kwargs: SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content='{}'))])))))
    http_app.add_url_rule(path, 'real-handler', lambda: jsonify(getattr(business, handler)(request.get_json())), methods=['POST'])
    signed, user = login(service)
    response = http_app.test_client().post(path, json=body, headers={'Authorization':'Bearer '+signed['token']})
    assert response.status_code == 200
    assert response.headers['X-AI-Result'] == 'fallback'
    # The provider answered with unusable output: one non-refundable credit,
    # even for the 5-credit meal plan.
    assert service.usage(user)['remaining'] == 9


@pytest.mark.parametrize('path,handler,body,cost', [
    ('/api/meal-plan','handle_meal_plan',{},5),
    ('/api/recipe','handle_recipe',{'mealName':'Valid unique online recipe'},1),
    ('/api/gap-fillers','handle_gap_fillers',{},1),
    ('/api/shopping-advice','handle_shopping_advice',{},1),
    ('/api/workout','handle_workout',{'kind':'gym','minutes':30},1),
])
def test_usable_json_charges_actual_endpoint(http_app, service, monkeypatch, path, handler, body, cost):
    import json
    monkeypatch.setenv('GROQ_API_KEY', 'test-not-a-real-key')
    import app as business
    from flask import jsonify, request
    samples = {
        'handle_meal_plan': business._fallback_meal_plan(2000),
        'handle_recipe': {'prepTime':10,'cookTime':20,'servings':2,'ingredients':[{'name':'rice','amount':'100g'}],'steps':['Cook rice.'],'tip':'Serve warm.'},
        'handle_workout': {'title':'Gym session','summary':'s','warmup':'w','cooldown':'c','exercises':[{'name':'Squat','sets':3,'reps':'8','minutes':0,'restSeconds':60,'note':''}]},
        'handle_gap_fillers': [{'name':'Rice','calories':100,'protein':2,'carbs':20,'fat':1,'reason':'Energy'}],
        'handle_shopping_advice':[{'produktas':'Rice','priezastis':'Affordable'}],
    }
    monkeypatch.setattr(business, 'nutrition_for', lambda **kwargs: None)
    monkeypatch.setattr(business, 'groq_client', SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(
        create=lambda **kwargs: SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content=json.dumps(samples[handler])))])))))
    http_app.add_url_rule(path, 'real-handler', lambda: jsonify(getattr(business, handler)(request.get_json())), methods=['POST'])
    signed,user=login(service)
    response=http_app.test_client().post(path,json=body,headers={'Authorization':'Bearer '+signed['token']})
    assert response.status_code == 200
    assert response.headers['X-AI-Result'] == 'online'
    assert service.usage(user)['remaining'] == 10-cost


def test_idempotent_http_replay_does_not_call_or_charge_twice(http_app, service):
    calls = []
    original = http_app.view_functions['chat']
    def counted():
        calls.append(True)
        return original()
    http_app.view_functions['chat'] = counted
    signed,user=login(service)
    headers={'Authorization':'Bearer '+signed['token'],'Idempotency-Key':'request-unique-12345'}
    client=http_app.test_client()
    first=client.post('/api/agent-chat',headers=headers,json={'mode':'online'})
    second=client.post('/api/agent-chat',headers=headers,json={'mode':'online'})
    assert first.status_code == second.status_code == 200
    assert second.get_json() == first.get_json()
    assert second.headers['X-AI-Result'] == 'replayed-online'
    assert len(calls) == 1
    assert service.usage(user)['remaining'] == 9
    conflict=client.post('/api/agent-chat',headers=headers,json={'mode':'cached'})
    assert conflict.status_code == 409
    assert service.usage(user)['remaining'] == 9


def test_idempotency_is_per_person_and_parallel_duplicates_are_bounded(http_app, service):
    calls=[]
    original=http_app.view_functions['chat']
    def counted():
        calls.append(True)
        return original()
    http_app.view_functions['chat']=counted
    signed,user=login(service)
    def post(_):
        return http_app.test_client().post('/api/agent-chat',json={'mode':'online'},headers={
            'Authorization':'Bearer '+signed['token'],'Idempotency-Key':'parallel-unique-12345'}).status_code
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        statuses=list(pool.map(post,range(8)))
    assert all(x in (200,409) for x in statuses)
    assert len(calls) == 1 and service.usage(user)['remaining'] == 9
    second,other=login(service,'person-two')
    response=http_app.test_client().post('/api/agent-chat',json={'mode':'online'},headers={
        'Authorization':'Bearer '+second['token'],'Idempotency-Key':'parallel-unique-12345'})
    assert response.status_code == 200
    assert service.usage(other)['remaining'] == 9


def test_idempotency_claim_survives_service_restart(service):
    signed,user=login(service)
    key='durable-unique-12345'
    r=service.reserve(user,'/api/agent-chat',request_key=key,fingerprint='body-hash')
    service.finish(r,succeeded=True,attempted=True)
    restarted=AccountService(service.path,service.apple,service.cipher,service.subject_secret,
                             daily_limit=10,global_limit=1000,clock=service.clock)
    with pytest.raises(AccountError) as error:
        restarted.reserve(restarted.authenticate('Bearer '+signed['token']),'/api/agent-chat',
                          request_key=key,fingerprint='body-hash')
    assert error.value.code == 'ai_request_repeated'
    assert restarted.usage(user)['remaining'] == 9


def test_expired_response_replay_never_reruns_provider(http_app, service):
    signed,user=login(service)
    headers={'Authorization':'Bearer '+signed['token'],'Idempotency-Key':'expire-replay-12345'}
    first=http_app.test_client().post('/api/agent-chat',json={'mode':'online'},headers=headers)
    assert first.status_code == 200
    service.test_clock[0] += 181
    repeated=http_app.test_client().post('/api/agent-chat',json={'mode':'online'},headers=headers)
    assert repeated.status_code == 409
    assert repeated.get_json()['code'] == 'ai_request_repeated'
    assert service.usage(user)['remaining'] == 9


def test_replay_cache_is_bounded_without_storing_content_on_disk(http_app, service):
    signed,user=login(service)
    headers={'Authorization':'Bearer '+signed['token']}
    client=http_app.test_client()
    for number in range(129):
        response=client.post('/api/agent-chat',json={'mode':'cached'},headers={
            **headers,'Idempotency-Key':f'bounded-replay-{number:05d}'})
        assert response.status_code == 200
    repeated=client.post('/api/agent-chat',json={'mode':'cached'},headers={
        **headers,'Idempotency-Key':'bounded-replay-00000'})
    assert repeated.status_code == 409  # evicted response, durable no-rerun claim
    assert service.usage(user)['remaining'] == 10
    with service.transaction() as db:
        assert {r['name'] for r in db.execute('PRAGMA table_info(ai_requests)')} == {'account','key','fingerprint','created'}


def test_late_ai_completion_cannot_restore_deleted_response_or_overwrite_recreated_account(http_app, service):
    import threading
    from flask import jsonify, request
    import ai_usage
    started,release=threading.Event(),threading.Event()
    def reply():
        mode=request.get_json()['mode']
        if mode == 'old private reply':
            started.set()
            assert release.wait(timeout=5)
        ai_usage.attempted.set(True);ai_usage.succeeded.set(True)
        return jsonify({'reply':mode})
    http_app.view_functions['chat']=reply
    signed,user=login(service)
    old_headers={'Authorization':'Bearer '+signed['token'],'Idempotency-Key':'delete-race-key-123'}
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        old=pool.submit(lambda: http_app.test_client().post('/api/agent-chat',json={'mode':'old private reply'},headers=old_headers))
        assert started.wait(timeout=5)
        try:
            deleted=http_app.test_client().delete('/api/auth/account',headers=old_headers)
            assert deleted.status_code == 204
            recreated,_=login(service)
            headers={'Authorization':'Bearer '+recreated['token'],'Idempotency-Key':'delete-race-key-123'}
            new=http_app.test_client().post('/api/agent-chat',json={'mode':'new private reply'},headers=headers)
            assert new.status_code == 200
        finally: release.set()
        late=old.result(timeout=5)
    assert late.status_code != 200
    replay=http_app.test_client().post('/api/agent-chat',json={'mode':'new private reply'},headers=headers)
    assert replay.status_code == 200
    assert replay.get_json() == {'reply':'new private reply'}
    assert service.usage(user)['remaining'] == 9  # cancelled/deleted reservation refunded


@pytest.fixture
def recipe_http(http_app, service, monkeypatch):
    import collections
    import json
    import app as business
    from flask import jsonify, request
    recipe = {'prepTime':1,'cookTime':2,'servings':1,
              'ingredients':[{'name':'rice','amount':'100g'}],'steps':['Cook rice.'],'tip':'Serve warm.'}
    calls = []
    def complete(**kwargs):
        calls.append(True)
        return SimpleNamespace(choices=[SimpleNamespace(finish_reason='stop',
            message=SimpleNamespace(content=json.dumps(recipe)))])
    monkeypatch.setattr(business, '_recipe_cache', collections.OrderedDict())
    monkeypatch.setattr(business, '_active_deals', lambda: [])
    monkeypatch.setattr(business, 'groq_client', SimpleNamespace(chat=SimpleNamespace(
        completions=SimpleNamespace(create=complete))))
    http_app.add_url_rule('/api/recipe', 'recipe', lambda: jsonify(business.handle_recipe(request.get_json())), methods=['POST'])
    signed, user = login(service)
    return SimpleNamespace(client=http_app.test_client(), business=business, calls=calls, user=user,
                           headers={'Authorization':'Bearer '+signed['token']})


def test_verified_recipe_cache_is_online_provenance_without_provider_or_credit_charge(recipe_http, service):
    import ai_usage
    case = recipe_http
    first = case.client.post('/api/recipe', json={'mealName':'Rice'}, headers=case.headers)
    cached = case.client.post('/api/recipe', json={'mealName':'Rice'}, headers=case.headers)
    assert first.headers['X-AI-Result'] == 'online'
    assert cached.headers['X-AI-Result'] == 'cached-online'
    assert cached.get_json() == first.get_json() and len(case.calls) == 1
    assert service.usage(case.user)['remaining'] == 9
    assert ai_usage.attempted.get() is False and ai_usage.succeeded.get() is False
    assert ai_usage.verified_cache.get() is True
    with service.transaction() as db:
        assert db.execute('SELECT used FROM global_quota').fetchone()['used'] == 1
    # A later request must not inherit the preceding verified-cache flag.
    unknown = case.client.post('/api/agent-chat', json={'mode':'cached'}, headers=case.headers)
    assert unknown.headers['X-AI-Result'] == 'cached'
    assert service.usage(case.user)['remaining'] == 9


def test_failed_recipe_is_not_cached_and_retry_reaches_provider(recipe_http, monkeypatch):
    case = recipe_http
    original = case.business.groq_client.chat.completions.create
    replies = iter(['{}', None])
    def complete(**kwargs):
        if next(replies) == '{}':
            return SimpleNamespace(choices=[SimpleNamespace(finish_reason='stop',message=SimpleNamespace(content='{}'))])
        return original(**kwargs)
    monkeypatch.setattr(case.business.groq_client.chat.completions, 'create', complete)
    failed = case.client.post('/api/recipe', json={'mealName':'Rice'}, headers=case.headers)
    assert failed.headers['X-AI-Result'] == 'fallback'
    assert 'rice' not in case.business._recipe_cache
    retried = case.client.post('/api/recipe', json={'mealName':'Rice'}, headers=case.headers)
    assert retried.headers['X-AI-Result'] == 'online' and len(case.calls) == 1


def test_verified_recipe_replay_retains_source_and_does_not_charge(recipe_http, service):
    case = recipe_http
    body = {'mealName':'Rice'}
    case.client.post('/api/recipe', json=body, headers=case.headers)
    headers = {**case.headers, 'Idempotency-Key':'verified-cache-replay-123'}
    cached = case.client.post('/api/recipe', json=body, headers=headers)
    replayed = case.client.post('/api/recipe', json=body, headers=headers)
    assert cached.headers['X-AI-Result'] == 'cached-online'
    assert replayed.headers['X-AI-Result'] == 'replayed-online'
    assert replayed.get_json() == cached.get_json()
    assert len(case.calls) == 1 and service.usage(case.user)['remaining'] == 9


@pytest.mark.parametrize('mode', ['cached'])
def test_unverified_replay_never_gains_online_provenance(http_app, service, mode):
    signed, user = login(service)
    headers = {'Authorization':'Bearer '+signed['token'], 'Idempotency-Key':'unverified-replay-123'}
    client = http_app.test_client()
    first = client.post('/api/agent-chat', json={'mode':mode}, headers=headers)
    repeated = client.post('/api/agent-chat', json={'mode':mode}, headers=headers)
    assert repeated.headers['X-AI-Result'] == 'replayed'
    assert repeated.get_json() == first.get_json()
    assert repeated.status_code == first.status_code
    assert service.usage(user)['remaining'] == 10


def test_unknown_recipe_cache_entry_does_not_gain_verified_provenance(recipe_http, service):
    case = recipe_http
    unknown = {'mealName':'Rice', 'steps':['Unverified local content']}
    case.business._recipe_cache['rice'] = unknown
    response = case.client.post('/api/recipe', json={'mealName':'Rice'}, headers=case.headers)
    assert response.headers['X-AI-Result'] == 'cached'
    assert response.get_json() == unknown
    assert not case.calls and service.usage(case.user)['remaining'] == 10


def test_guest_recovery_and_quotas_do_not_require_apple(service):
    service.guest_enabled=True
    service.apple=None
    secret='a'*43
    first=service.guest_login(secret,'192.0.2.1')
    user=service.authenticate('Bearer '+first['token'])
    reservation=service.reserve(user,'/api/meal-plan')
    service.finish(reservation,succeeded=True,attempted=True)
    service.logout(user)
    second=service.guest_login(secret,'192.0.2.2')
    assert first['accountID']==second['accountID'] and first['token']!=second['token']
    assert second['usage']['remaining']==5
    service.test_clock[0]+=86401
    user=service.authenticate('Bearer '+second['token'])
    assert service.usage(user)['remaining']==10
    with service.transaction() as db:
        stored=str([tuple(row) for row in db.execute('SELECT * FROM accounts')])
        assert secret not in stored
    service.delete_account(user)
    with pytest.raises(AccountError): service.authenticate('Bearer '+second['token'])


def test_guest_setup_is_opt_in_and_network_bounded(service):
    with pytest.raises(AccountError): service.guest_login('a'*43,'network')
    service.guest_enabled=True
    for bad in [None,'short','a'*129,'a'*42+' ',True]:
        with pytest.raises(AccountError): service.guest_login(bad,'network')
    for index in range(5): service.guest_login(str(index)*43,'network')
    with pytest.raises(AccountError) as error: service.guest_login('x'*43,'network')
    assert error.value.status==429
    assert service.guest_login('0'*43,'network')['usage']['remaining']==10
    service.test_clock[0]+=86401
    assert service.guest_login('x'*43,'network')['usage']['remaining']==10


def test_guest_delete_and_recreate_with_same_device_key_does_not_reset_today(service):
    service.guest_enabled=True
    signed=service.guest_login('a'*43,'network')
    user=service.authenticate('Bearer '+signed['token'])
    reservation=service.reserve(user,'/api/meal-plan')
    service.finish(reservation,succeeded=True,attempted=True)
    service.delete_account(user)
    assert service.guest_login('a'*43,'network')['usage']['remaining']==5


def test_public_guest_bootstrap_does_not_open_protected_routes(service,monkeypatch):
    import server
    service.guest_enabled=True
    monkeypatch.setitem(server.app.config,'AI_ACCOUNTS',service)
    monkeypatch.setattr(server,'APP_API_KEY','s'*64)
    monkeypatch.setattr(server,'_is_rate_limited',lambda ip:False)
    client=server.app.test_client()
    assert client.get('/api/auth/config').get_json()['guestEnabled'] is True
    assert client.get('/api/products').status_code==401
    assert client.post('/api/agent-chat',json={}).status_code==401
    signed=client.post('/api/auth/guest',json={'deviceSecret':'a'*43})
    assert signed.status_code==200
    credentials=signed.get_json()
    headers={'Authorization':'Bearer '+credentials['token']}
    assert client.get('/api/ai/usage',headers=headers).status_code==200
    assert client.get('/api/ai/usage',headers={'Authorization':'Bearer '+'b'*64}).status_code==401
    assert client.delete('/api/auth/account',headers=headers).status_code==204
    assert client.get('/api/ai/usage',headers=headers).status_code==401


def test_unusable_output_keeps_one_credit_and_shared_attempt(service):
    _, user = login(service)
    r = service.reserve(user, '/api/meal-plan')
    assert service.finish(r, succeeded=False, attempted=True, responded=True)
    assert service.usage(user)['remaining'] == 9
    r = service.reserve(user, '/api/agent-chat')
    assert service.finish(r, succeeded=False, attempted=True, responded=True)
    assert service.usage(user)['remaining'] == 8
    # Transport/provider error (no response): full personal refund.
    r = service.reserve(user, '/api/meal-plan')
    assert service.finish(r, succeeded=False, attempted=True, responded=False)
    assert service.usage(user)['remaining'] == 8
    with service.transaction() as db:
        assert db.execute('SELECT used FROM global_quota').fetchone()['used'] == 3


def test_http_unusable_output_cannot_drain_shared_ceiling_for_free(http_app, service):
    signed, user = login(service)
    client = http_app.test_client()
    headers = {'Authorization': 'Bearer '+signed['token']}
    statuses = [client.post('/api/agent-chat', headers=headers, json={'mode': 'unusable'}).status_code
                for _ in range(12)]
    assert statuses.count(200) == 10 and statuses[-1] == 429
    assert service.usage(user)['remaining'] == 0
    with service.transaction() as db:
        assert db.execute('SELECT used FROM global_quota').fetchone()['used'] == 10


@pytest.mark.parametrize('mode', ['fallback', 'unusable', 'invalid'])
def test_failed_request_releases_idempotency_key_for_retry(http_app, service, mode):
    calls = []
    original = http_app.view_functions['chat']
    def counted():
        calls.append(True)
        return original()
    http_app.view_functions['chat'] = counted
    signed, user = login(service)
    headers = {'Authorization': 'Bearer '+signed['token'], 'Idempotency-Key': 'retry-after-failure-123'}
    client = http_app.test_client()
    failed = client.post('/api/agent-chat', json={'mode': mode}, headers=headers)
    assert failed.headers['X-AI-Result'] == 'fallback'
    retried = client.post('/api/agent-chat', json={'mode': mode}, headers=headers)
    assert retried.headers['X-AI-Result'] == 'fallback' and len(calls) == 2
    # The released key can then complete successfully, and is claimed again.
    done = client.post('/api/agent-chat', json={'mode': mode}, headers=headers)
    assert done.status_code == failed.status_code and len(calls) == 3
    http_app.view_functions['chat'] = original
    online_headers = {**headers, 'Idempotency-Key': 'retry-after-failure-456'}
    first = client.post('/api/agent-chat', json={'mode': 'fallback'}, headers=online_headers)
    second = client.post('/api/agent-chat', json={'mode': 'online'}, headers=online_headers)
    assert first.headers['X-AI-Result'] == 'fallback'
    assert second.status_code == 200 and second.headers['X-AI-Result'] == 'online'
    third = client.post('/api/agent-chat', json={'mode': 'online'}, headers=online_headers)
    assert third.headers['X-AI-Result'] == 'replayed-online'


def test_apple_notification_accepts_millisecond_event_time(http_app, service):
    signed, user = login(service)
    event_ms = int(service.clock()*1000)
    payload = dict(iss='https://appleid.apple.com', aud='com.mostafa.mealio',
                   iat=int(service.clock()), jti='test-event-ms',
                   events={'type':'consent-revoked','sub':'person-one','event_time':event_ms})
    notification = jwt.encode(payload, service.test_private, algorithm='RS256')
    client = http_app.test_client()
    assert client.post('/api/auth/apple/notifications', json={'payload': notification}).status_code == 204
    with pytest.raises(AccountError): service.authenticate('Bearer '+signed['token'])
    # A millisecond time in the future is still rejected after normalization.
    payload['events'] = {'type':'consent-revoked','sub':'person-one','event_time':event_ms+120_000}
    payload['jti'] = 'test-event-ms-future'
    future = jwt.encode(payload, service.test_private, algorithm='RS256')
    assert client.post('/api/auth/apple/notifications', json={'payload': future}).status_code == 400


def test_cleanup_is_throttled_but_expiry_is_still_enforced(service, monkeypatch):
    runs = []
    original = service._cleanup
    monkeypatch.setattr(service, '_cleanup', lambda db: (runs.append(1), original(db)))
    signed, user = login(service)
    for _ in range(5): service.usage(user)
    assert len(runs) == 1
    service.test_clock[0] += 61
    service.usage(user)
    assert len(runs) == 2
    # A session past its expiry is rejected even before housekeeping runs again.
    service.test_clock[0] += 30*86400
    service._last_cleanup = service.test_clock[0]
    with pytest.raises(AccountError): service.authenticate('Bearer '+signed['token'])
