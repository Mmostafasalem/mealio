"""HTTP boundary: never accept a caller-selected account id for an allowance."""
import json
import logging
from flask import g, jsonify, request
from ai_accounts import AccountError, AccountService, AI_PATHS
import ai_usage


_INVALID_JSON = object()


def parse_json_body(raw):
    """Parse a request body; return _INVALID_JSON instead of raising.

    Flask's get_json(silent=True) only swallows ValueError, so a deeply nested
    body (RecursionError) or a non-UTF-8 one would become a 500.
    """
    if isinstance(raw, (bytes, bytearray)):
        try: raw = raw.decode('utf-8')
        except UnicodeDecodeError: return _INVALID_JSON
    try: return json.loads(raw)
    except (ValueError, RecursionError, TypeError): return _INVALID_JSON


def request_json():
    """The request's JSON object, or None when it is missing or not valid JSON."""
    data = parse_json_body(request.get_data(cache=True))
    return None if data is _INVALID_JSON else data


def register_ai_accounts(app, client_ip=None):
    try:
        service = AccountService.from_env()
    except Exception:
        # Do not log environment values, signing keys, grants or JWTs.
        logging.error('AI account configuration is unavailable; online AI is disabled')
        service = None
    app.config['AI_ACCOUNTS'] = service

    def caller_address():
        return client_ip() if client_ip else (request.remote_addr or "unknown")

    def accounts():
        active = app.config.get('AI_ACCOUNTS')
        if active is None:
            raise AccountError('Online AI sign-in is currently unavailable. Local features still work.',503,'ai_unavailable')
        return active

    def user():
        if not hasattr(g,'ai_user'):
            g.ai_user = accounts().authenticate(request.headers.get('Authorization',''))
        return g.ai_user

    def session_owner():
        # Signing out and deleting one's own account need only a valid session:
        # they must keep working when Apple is unreachable or Apple sign-in is off.
        return accounts().authenticate(request.headers.get('Authorization',''),verify_apple=False)

    @app.errorhandler(AccountError)
    def account_error(error):
        response = jsonify({'error':error.message,'code':error.code})
        response.status_code = error.status
        response.headers['X-AI-Error'] = error.code
        if error.status in (429,503):
            response.headers['Retry-After'] = '60'
        return response

    @app.get('/api/auth/config')
    def account_config():
        service=app.config.get('AI_ACCOUNTS')
        return jsonify({'enabled':service is not None, 'guestEnabled':bool(service and service.guest_enabled),
                        'appleEnabled':bool(service and service.apple is not None)})

    @app.post('/api/auth/guest')
    def guest_login():
        data=request_json()
        if not isinstance(data,dict): raise AccountError('Invalid sign-in request.',400,'invalid_request')
        return jsonify(accounts().guest_login(data.get('deviceSecret'),caller_address()))

    @app.get('/api/auth/apple/challenge')
    def challenge(): return jsonify(accounts().challenge(caller_address()))

    @app.post('/api/auth/apple')
    def apple_login():
        data=request_json()
        if not isinstance(data,dict):
            raise AccountError('Invalid sign-in request.',400,'invalid_request')
        return jsonify(accounts().login(data.get('identityToken'),data.get('authorizationCode'),data.get('challengeID')))

    @app.get('/api/ai/usage')
    def usage(): return jsonify(accounts().usage(user()))

    @app.post('/api/auth/logout')
    def logout():
        accounts().logout(session_owner())
        return ('',204)

    @app.delete('/api/auth/account')
    def delete_account():
        accounts().delete_account(session_owner())
        return ('',204)

    @app.post('/api/auth/apple/notifications')
    def apple_notification():
        data=request_json()
        signed=data.get('payload') if isinstance(data,dict) else None
        # Verify the Apple signature, issuer, audience and notification freshness.
        if accounts().apple is None: raise AccountError('Apple sign-in unavailable.',503,'ai_unavailable')
        claims=accounts().apple.verify_notification(signed)
        try: event=json.loads(claims['events']) if isinstance(claims['events'],str) else claims['events']
        except (KeyError,TypeError,ValueError):
            raise AccountError('Invalid notification.',400,'invalid_request') from None
        if not isinstance(event,dict): raise AccountError('Invalid notification.',400,'invalid_request')
        if event.get('type') in {'consent-revoked','account-deleted'}:
            subject=event.get('sub')
            if not isinstance(subject,str) or not subject:
                raise AccountError('Invalid notification.',400,'invalid_request')
            # An old revocation must not erase an account recreated afterwards.
            event_time=event.get('event_time')
            # Apple sends event_time in milliseconds; seconds stay accepted.
            if isinstance(event_time,(int,float)) and not isinstance(event_time,bool) and event_time>1e11:
                event_time=event_time/1000
            if isinstance(event_time,bool) or not isinstance(event_time,(int,float)) or event_time>accounts().clock()+30:
                raise AccountError('Invalid notification.',400,'invalid_request')
            account=accounts()._subject(subject)
            accounts().purge(account,event_time)
        return ('',204)

    @app.before_request
    def ai_allowance():
        if request.method != 'POST' or request.path not in AI_PATHS: return None
        ai_usage.attempted.set(False);ai_usage.succeeded.set(False);ai_usage.verified_cache.set(False)
        ai_usage.responded.set(False);ai_usage.account.set(None)
        person=user()
        ai_usage.account.set(person.account_id)
        key=request.headers.get('Idempotency-Key')
        fingerprint=accounts().request_fingerprint(request.path,request.get_data(cache=True)) if key is not None else None
        # A repeated Idempotency-Key is refused here (409 ai_request_repeated):
        # responses are never stored, so there is nothing to replay.
        g.ai_reservation=accounts().reserve(person,request.path,request_key=key,fingerprint=fingerprint)
        g.ai_request_key=key
        g.ai_request_fingerprint=fingerprint

    @app.after_request
    def ai_allowance_result(response):
        # Clear before any database work so error handling cannot finalize twice.
        reservation = getattr(g, 'ai_reservation', None)
        g.ai_reservation = None
        try:
            status = None
            if reservation:
                succeeded=response.status_code < 400 and ai_usage.succeeded.get()
                key=getattr(g,'ai_request_key',None)
                # A failed request (provider attempted without a usable result,
                # or an error status) releases its idempotency key so the client
                # can retry with it. Local/cached results keep the no-rerun claim.
                released=key is not None and not succeeded and (
                    ai_usage.attempted.get() or response.status_code >= 400)
                result='online' if ai_usage.succeeded.get() else ('fallback' if ai_usage.attempted.get() else ('cached-online' if ai_usage.verified_cache.get() else 'cached'))
                # Settling also returns the account's usage, so the headers below
                # need no second transaction. A deleted, expired or replaced
                # reservation settles nothing and its late answer is not delivered.
                status=accounts().finish_with_usage(reservation,
                    succeeded=succeeded,
                    attempted=ai_usage.attempted.get(),
                    responded=response.status_code < 500 and ai_usage.responded.get(),
                    release_request_key=key if released else None)
                if status is None:
                    response=jsonify({'error':'This request is no longer available. No extra credits were used.',
                                      'code':'ai_request_invalidated'})
                    response.status_code=409
                    response.headers['X-AI-Error']='ai_request_invalidated'
                else:
                    response.headers['X-AI-Result'] = result
                    if result == 'fallback':
                        # Why it fell back: 'unusable-output' (the provider answered but
                        # its output failed validation, so 1 credit is kept) or
                        # 'provider-error' (nothing kept). See SECURITY.md.
                        response.headers['X-AI-Fallback'] = (
                            'unusable-output' if response.status_code < 500 and ai_usage.responded.get()
                            else 'provider-error')
                    if released:
                        # The Idempotency-Key was released: retrying with it is a new
                        # request that calls the provider (and is charged) again.
                        response.headers['X-AI-Request-Key'] = 'released'
            person = getattr(g, 'ai_user', None)
            if person and request.path in AI_PATHS:
                if status is None: status = accounts().usage(person)
                response.headers['X-AI-Account'] = person.account_id
                response.headers['X-AI-Limit'] = str(status['limit'])
                response.headers['X-AI-Remaining'] = str(status['remaining'])
                response.headers['X-AI-Reset'] = status['resetsAt']
                if response.status_code == 429:
                    from datetime import datetime
                    reset = datetime.fromisoformat(status['resetsAt'].replace('Z', '+00:00')).timestamp()
                    response.headers['Retry-After'] = str(max(1, int(reset-accounts().clock())))
        except Exception:
            # No exception details: credentials/database values must never reach logs.
            logging.error('AI allowance storage unavailable')
            response = jsonify({'error':'Online AI is temporarily unavailable.','code':'ai_unavailable'})
            response.status_code = 503
            response.headers['X-AI-Error'] = 'ai_unavailable'
        response.headers['Cache-Control'] = 'no-store'
        return response
