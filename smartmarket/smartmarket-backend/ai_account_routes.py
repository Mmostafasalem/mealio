"""HTTP boundary: never accept a caller-selected account id for an allowance."""
import json
import logging
import hmac
import collections
import threading
from ai_accounts import digest
from flask import g, jsonify, request, make_response
from ai_accounts import AccountError, AccountService, AI_PATHS
import ai_usage


def register_ai_accounts(app):
    try:
        service = AccountService.from_env()
    except Exception:
        # Do not log environment values, signing keys, grants or JWTs.
        logging.error('AI account configuration is unavailable; online AI is disabled')
        service = None
    app.config['AI_ACCOUNTS'] = service
    # Transient response replay only; no health/chat bodies are written to disk.
    replays = collections.OrderedDict()
    replay_lock = threading.RLock()

    def replay_key(person, key): return (person.account_id, digest(key))

    def cached_response(person, key, fingerprint):
        with replay_lock:
            now=accounts().clock()
            for old in list(replays):
                if replays[old][0] <= now: del replays[old]
            value=replays.get(replay_key(person,key))
            if value is None or not hmac.compare_digest(value[4],fingerprint): return None
            replays.move_to_end(replay_key(person,key))
            response=make_response(value[1],value[2])
            response.headers['Content-Type']=value[3]
            response.headers['X-AI-Result']='replayed-online' if value[5] in {'online','cached-online'} else 'replayed'
            return response

    def drop_replays(account):
        with replay_lock:
            for key in list(replays):
                if key[0] == account: del replays[key]


    def accounts():
        active = app.config.get('AI_ACCOUNTS')
        if active is None:
            raise AccountError('Online AI sign-in is currently unavailable. Local features still work.',503,'ai_unavailable')
        return active

    def user():
        if not hasattr(g,'ai_user'):
            g.ai_user = accounts().authenticate(request.headers.get('Authorization',''))
        return g.ai_user

    @app.errorhandler(AccountError)
    def account_error(error):
        response = jsonify({'error':error.message,'code':error.code})
        response.status_code = error.status
        response.headers['X-AI-Error'] = error.code
        if error.code == 'ai_request_repeated': response.headers['Retry-After'] = '2'
        if error.status in (429,503):
            response.headers['Retry-After'] = '60'
        return response

    @app.get('/api/auth/config')
    def account_config():
        return jsonify({'enabled':app.config.get('AI_ACCOUNTS') is not None})

    @app.get('/api/auth/apple/challenge')
    def challenge(): return jsonify(accounts().challenge())

    @app.post('/api/auth/apple')
    def apple_login():
        data=request.get_json(silent=True)
        if not isinstance(data,dict):
            raise AccountError('Invalid sign-in request.',400,'invalid_request')
        return jsonify(accounts().login(data.get('identityToken'),data.get('authorizationCode'),data.get('challengeID')))

    @app.get('/api/ai/usage')
    def usage(): return jsonify(accounts().usage(user()))

    @app.post('/api/auth/logout')
    def logout():
        accounts().logout(user())
        return ('',204)

    @app.delete('/api/auth/account')
    def delete_account():
        person=user()
        accounts().delete_account(person)
        drop_replays(person.account_id)
        return ('',204)

    @app.post('/api/auth/apple/notifications')
    def apple_notification():
        data=request.get_json(silent=True)
        signed=data.get('payload') if isinstance(data,dict) else None
        # Verify the Apple signature, issuer, audience and notification freshness.
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
            if not isinstance(event_time,(int,float)) or event_time>accounts().clock()+30:
                raise AccountError('Invalid notification.',400,'invalid_request')
            account=accounts()._subject(subject)
            accounts().purge(account,event_time)
            drop_replays(account)
        return ('',204)

    @app.before_request
    def ai_allowance():
        if request.method != 'POST' or request.path not in AI_PATHS: return None
        ai_usage.attempted.set(False);ai_usage.succeeded.set(False);ai_usage.verified_cache.set(False)
        person=user()
        key=request.headers.get('Idempotency-Key')
        fingerprint=accounts().request_fingerprint(request.path,request.get_data(cache=True)) if key is not None else None
        try:
            g.ai_reservation=accounts().reserve(person,request.path,request_key=key,fingerprint=fingerprint)
            g.ai_request_key=key
            g.ai_request_fingerprint=fingerprint
        except AccountError as error:
            if error.code == 'ai_request_repeated':
                replay=cached_response(person,key,fingerprint)
                if replay is not None: return replay
            raise

    @app.after_request
    def ai_allowance_result(response):
        # Clear before any database work so error handling cannot finalize twice.
        reservation = getattr(g, 'ai_reservation', None)
        g.ai_reservation = None
        try:
            if reservation:
                # Publish under the same replay lock used by deletion. A deleted,
                # expired or replaced reservation can never publish a late body.
                with replay_lock:
                    valid=accounts().finish(reservation,
                        succeeded=response.status_code < 400 and ai_usage.succeeded.get(),
                        attempted=ai_usage.attempted.get())
                    if not valid:
                        response=jsonify({'error':'This request is no longer available. No extra credits were used.',
                                          'code':'ai_request_invalidated'})
                        response.status_code=409
                        response.headers['X-AI-Error']='ai_request_invalidated'
                    else:
                        response.headers['X-AI-Result'] = 'online' if ai_usage.succeeded.get() else ('fallback' if ai_usage.attempted.get() else ('cached-online' if ai_usage.verified_cache.get() else 'cached'))
                        key=getattr(g,'ai_request_key',None)
                        body=response.get_data()
                        if key is not None and response.status_code < 500 and len(body)<=128*1024:
                            replays[replay_key(g.ai_user,key)]=(accounts().clock()+180,body,response.status_code,response.content_type,g.ai_request_fingerprint,response.headers['X-AI-Result'])
                            replays.move_to_end(replay_key(g.ai_user,key))
                            while len(replays)>128: replays.popitem(last=False)
            person = getattr(g, 'ai_user', None)
            if person and request.path in AI_PATHS:
                status = accounts().usage(person)
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
