"""Apple-authenticated daily allowances. No health data is stored here.

SQLite requires one shared, durable volume. Do not put this database on Render's
free ephemeral filesystem or scale independent copies of this service.
"""
import base64
import contextlib
import hashlib
import hmac
import json
import os
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request
from account_storage import AccountStorage
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta

AI_PATHS = frozenset({'/api/meal-plan','/api/agent-chat','/api/recipe',
                      '/api/gap-fillers','/api/shopping-advice'})


class AccountError(Exception):
    def __init__(self, message, status=401, code='ai_sign_in_required'):
        super().__init__(message)
        self.message, self.status, self.code = message, status, code


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def iso(timestamp):
    return datetime.fromtimestamp(timestamp, timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


@dataclass(frozen=True)
class Session:
    account_id: str
    session_hash: str


class AppleAuthority:
    def __init__(self, audience, team_id, key_id, private_key, clock=time.time):
        import jwt
        from cryptography.hazmat.primitives.serialization import load_pem_private_key
        self.audience, self.team_id, self.key_id = audience, team_id, key_id
        self.private_key = load_pem_private_key(private_key.replace('\\n','\n').encode(),password=None)
        from cryptography.hazmat.primitives.asymmetric import ec
        if not isinstance(self.private_key, ec.EllipticCurvePrivateKey) or not isinstance(self.private_key.curve, ec.SECP256R1):
            raise ValueError('Apple signing key must be an ES256 private key')
        self.clock = clock
        self.keys = jwt.PyJWKClient('https://appleid.apple.com/auth/keys', timeout=5,
                                   cache_jwk_set=True, lifespan=3600)

    def verify_identity(self, token, nonce=None):
        return self._verify(token, nonce, notification=False)

    def verify_notification(self, token):
        return self._verify(token, None, notification=True)

    def _verify(self, token, nonce, notification):
        import jwt
        if not isinstance(token,str) or not 20 <= len(token) <= 16384:
            raise AccountError('Sign in with Apple again.')
        try:
            key = self.keys.get_signing_key_from_jwt(token).key
            # The algorithm and issuer are fixed by the server, never by a client URL.
            claims = jwt.decode(token,key,algorithms=['RS256'],audience=self.audience,
                                issuer='https://appleid.apple.com',
                                options={'require':['iss','aud','iat']+(['events','jti'] if notification else ['sub','exp']),
                                         'verify_exp':False,'verify_iat':False})
            now = self.clock()
            if not notification and (not isinstance(claims['exp'],(int,float)) or claims['exp'] <= now):
                raise ValueError('expired')
            if notification and now-claims['iat'] > 7*86400:
                raise ValueError('old notification')
            if not isinstance(claims['iat'],(int,float)) or claims['iat'] > now+30:
                raise ValueError('future')
            if not notification and (not isinstance(claims['sub'],str) or not 1 <= len(claims['sub']) <= 512):
                raise ValueError('subject')
            if nonce is not None and not hmac.compare_digest(str(claims.get('nonce','')),nonce):
                raise ValueError('nonce')
            return claims
        except AccountError:
            raise
        except jwt.PyJWKClientConnectionError:
            raise AccountError('Apple sign-in is temporarily unavailable.',503,'ai_unavailable') from None
        except Exception:
            raise AccountError('Sign in with Apple again.') from None

    def _post(self, action, fields):
        import jwt
        now = int(self.clock())
        client_secret = jwt.encode({'iss':self.team_id,'iat':now,'exp':now+300,
                                    'aud':'https://appleid.apple.com','sub':self.audience},
                                   self.private_key,algorithm='ES256',headers={'kid':self.key_id})
        fields = {**fields,'client_id':self.audience,'client_secret':client_secret}
        request = urllib.request.Request('https://appleid.apple.com/auth/'+action,
                    data=urllib.parse.urlencode(fields).encode(),
                    headers={'Content-Type':'application/x-www-form-urlencoded'})
        try:
            with urllib.request.urlopen(request,timeout=10) as response:
                raw = response.read(65536)
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            # Do not log Apple's response: it can contain credentials or grant details.
            if e.code == 400:
                raise AccountError('Sign in with Apple again.') from None
            raise AccountError('Apple sign-in is temporarily unavailable.',503,'ai_unavailable') from None
        except Exception:
            raise AccountError('Apple sign-in is temporarily unavailable.',503,'ai_unavailable') from None

    def exchange_code(self, code):
        if not isinstance(code,str) or not 1 <= len(code) <= 8192:
            raise AccountError('Sign in with Apple again.')
        return self._post('token',{'grant_type':'authorization_code','code':code})

    def refresh(self, token):
        return self._post('token',{'grant_type':'refresh_token','refresh_token':token})

    def revoke(self, token):
        self._post('revoke',{'token':token,'token_type_hint':'refresh_token'})


class AccountService:
    def __init__(self,path,apple,cipher,subject_secret,daily_limit=30,global_limit=900,clock=time.time,guest_enabled=False):
        if len(subject_secret) < 32:
            raise ValueError('AI subject secret must contain at least 32 bytes')
        self.path,self.apple,self.cipher,self.subject_secret = path,apple,cipher,subject_secret
        self.daily_limit,self.global_limit,self.clock = daily_limit,global_limit,clock
        self.guest_enabled = guest_enabled
        self.storage = AccountStorage(path)
        with self.transaction() as db:
            db.executescript('''
              CREATE TABLE IF NOT EXISTS accounts(id TEXT PRIMARY KEY, refresh BLOB NOT NULL, verified REAL NOT NULL, created REAL NOT NULL, kind TEXT NOT NULL DEFAULT 'apple');
              CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, expires REAL NOT NULL);
              CREATE TABLE IF NOT EXISTS challenges(id TEXT PRIMARY KEY, nonce TEXT NOT NULL, expires REAL NOT NULL);
              CREATE TABLE IF NOT EXISTS quota(account TEXT NOT NULL, day TEXT NOT NULL, used INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(account,day));
              CREATE TABLE IF NOT EXISTS global_quota(day TEXT PRIMARY KEY, used INTEGER NOT NULL DEFAULT 0);
              CREATE TABLE IF NOT EXISTS reservations(id TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, day TEXT NOT NULL, cost INTEGER NOT NULL, expires REAL NOT NULL);
              CREATE INDEX IF NOT EXISTS session_account ON sessions(account);
              CREATE TABLE IF NOT EXISTS guest_registrations(network TEXT NOT NULL, day TEXT NOT NULL, used INTEGER NOT NULL, PRIMARY KEY(network,day));
              CREATE TABLE IF NOT EXISTS ai_requests(account TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, key TEXT NOT NULL, fingerprint TEXT NOT NULL, created REAL NOT NULL, PRIMARY KEY(account,key));
            ''')
            if not self.storage.postgres:
                if 'created' not in {r['name'] for r in db.execute('PRAGMA table_info(accounts)')}:
                    db.execute('ALTER TABLE accounts ADD COLUMN created REAL NOT NULL DEFAULT 0')
                    db.execute('UPDATE accounts SET created=verified')
                if 'kind' not in {r['name'] for r in db.execute('PRAGMA table_info(accounts)')}:
                    db.execute("ALTER TABLE accounts ADD COLUMN kind TEXT NOT NULL DEFAULT 'apple'")
                # Spending is abuse-prevention metadata independent of account credentials.
                # Keep only today's keyed subject/count so delete/recreate cannot reset it.
                if list(db.execute('PRAGMA foreign_key_list(quota)')):
                    db.execute('ALTER TABLE quota RENAME TO old_quota')
                    db.execute('CREATE TABLE quota(account TEXT NOT NULL, day TEXT NOT NULL, used INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(account,day))')
                    db.execute('INSERT INTO quota SELECT account,day,used FROM old_quota')
                    db.execute('DROP TABLE old_quota')
        if not self.storage.postgres: os.chmod(self.path, 0o600)

    @classmethod
    def from_env(cls):
        if os.environ.get('AI_ACCOUNTS_ENABLED') != '1': return None
        from cryptography.fernet import Fernet
        path = os.environ.get('AI_DATABASE_URL','')
        if path:
            from urllib.parse import urlsplit
            parsed = urlsplit(path)
            if parsed.scheme not in ('postgres', 'postgresql') or not parsed.hostname or not parsed.username or not parsed.password:
                raise ValueError('Invalid AI_DATABASE_URL')
        else:
            path = os.environ.get('AI_STATE_DB','')
            if not os.path.isabs(path) or os.environ.get('AI_STATE_PERSISTENT') != '1':
                raise ValueError('Configure a persistent AI database')
            if not os.path.isdir(os.path.dirname(path)): raise ValueError('AI storage mount is unavailable')
        limit = int(os.environ.get('AI_DAILY_CREDITS','30'))
        global_limit = int(os.environ.get('AI_GLOBAL_DAILY_ATTEMPTS','900'))
        if not 5 <= limit <= 10000 or not 1 <= global_limit <= 100000:
            raise ValueError('Invalid AI allowance configuration')
        guest_enabled = os.environ.get('AI_GUEST_ENABLED') == '1'
        apple_enabled = os.environ.get('AI_APPLE_ENABLED','1') == '1'
        if not guest_enabled and not apple_enabled: raise ValueError('Enable an AI sign-in method')
        apple = (AppleAuthority(os.environ.get('APPLE_APP_ID','com.mostafa.mealio'),
                               os.environ['APPLE_TEAM_ID'],os.environ['APPLE_KEY_ID'],
                               os.environ['APPLE_PRIVATE_KEY']) if apple_enabled else None)
        return cls(path,apple,Fernet(os.environ['AI_TOKEN_ENCRYPTION_KEY'].encode()),
                   os.environ['AI_SUBJECT_SECRET'].encode(),limit,global_limit,guest_enabled=guest_enabled)

    @contextlib.contextmanager
    def transaction(self):
        with self.storage.transaction() as connection:
            yield connection

    def _day(self): return datetime.fromtimestamp(self.clock(),timezone.utc).date().isoformat()

    def _cleanup(self,db):
        now=self.clock()
        for row in db.execute('SELECT * FROM reservations WHERE expires<=?',(now,)).fetchall():
            db.execute('UPDATE quota SET used=MAX(0,used-?) WHERE account=? AND day=?',
                       (row['cost'],row['account'],row['day']))
        db.execute('DELETE FROM reservations WHERE expires<=?',(now,))
        db.execute('DELETE FROM challenges WHERE expires<=?',(now,))
        db.execute('DELETE FROM sessions WHERE expires<=?',(now,))
        db.execute("DELETE FROM accounts WHERE kind='guest' AND verified<=? AND NOT EXISTS (SELECT 1 FROM sessions WHERE sessions.account=accounts.id)",(now-30*86400,))
        db.execute('DELETE FROM ai_requests WHERE created<=?',(now-86400,))
        cutoff=(datetime.fromtimestamp(now,timezone.utc).date()-timedelta(days=2)).isoformat()
        db.execute('DELETE FROM quota WHERE day<?',(self._day(),))
        db.execute('DELETE FROM guest_registrations WHERE day<?',(self._day(),))
        db.execute('DELETE FROM global_quota WHERE day<?',(cutoff,))

    def _subject(self,sub): return hmac.new(self.subject_secret,sub.encode(),hashlib.sha256).hexdigest()

    def challenge(self):
        if self.apple is None: raise AccountError('Apple sign-in is unavailable. Use guest access.',503,'ai_unavailable')
        value={'id':secrets.token_urlsafe(32),'nonce':digest(secrets.token_urlsafe(32))}
        with self.transaction() as db:
            self._cleanup(db)
            # Bound unauthenticated challenge storage; IP rate limiter applies too.
            if db.execute('SELECT COUNT(*) FROM challenges').fetchone()[0] >= 10000:
                raise AccountError('Sign-in is busy. Please retry shortly.',503,'ai_unavailable')
            db.execute('INSERT INTO challenges VALUES(?,?,?)',(value['id'],value['nonce'],self.clock()+300))
        return {**value,'expiresAt':iso(self.clock()+300)}

    def login(self,identity_token,code,challenge_id):
        if self.apple is None: raise AccountError('Apple sign-in is unavailable. Use guest access.',503,'ai_unavailable')
        if not isinstance(challenge_id,str): raise AccountError('Sign in with Apple again.')
        with self.transaction() as db:
            self._cleanup(db)
            row=db.execute('SELECT * FROM challenges WHERE id=?',(challenge_id,)).fetchone()
            if row is None: raise AccountError('Sign-in expired. Please try again.')
            nonce=row['nonce']
        claims=self.apple.verify_identity(identity_token,nonce)
        grant=self.apple.exchange_code(code)
        returned=self.apple.verify_identity(grant.get('id_token'))
        if returned['sub'] != claims['sub'] or not grant.get('refresh_token'):
            raise AccountError('Sign in with Apple again.')
        account=self._subject(claims['sub']); token=secrets.token_urlsafe(48); expires=self.clock()+30*86400
        with self.transaction() as db:
            # One Apple authorization challenge creates at most one app session.
            consumed=db.execute('DELETE FROM challenges WHERE id=? AND expires>?',
                                (challenge_id,self.clock())).rowcount
            if consumed != 1: raise AccountError('Sign-in expired. Please try again.')
            encrypted=self.cipher.encrypt(grant['refresh_token'].encode())
            db.execute('INSERT INTO accounts(id,refresh,verified,created) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET refresh=excluded.refresh,verified=excluded.verified',
                       (account,encrypted,self.clock(),self.clock()))
            db.execute('INSERT INTO sessions VALUES(?,?,?)',(digest(token),account,expires))
            # Bound sessions per account without touching its daily quota.
            db.execute('DELETE FROM sessions WHERE account=? AND hash NOT IN (SELECT hash FROM sessions WHERE account=? ORDER BY expires DESC LIMIT 20)',(account,account))
        return {'token':token,'accountID':account,'expiresAt':iso(expires),
                'usage':self.usage(Session(account,digest(token)))}

    def guest_login(self, device_secret, network):
        import re
        if not self.guest_enabled: raise AccountError('Guest access is unavailable.',503,'ai_unavailable')
        if not isinstance(device_secret,str) or not re.fullmatch(r'[A-Za-z0-9_-]{43,128}',device_secret):
            raise AccountError('Invalid guest sign-in.',400,'invalid_request')
        account=self._subject('guest:'+device_secret)
        network_key=self._subject('guest-network:'+self._day()+':'+network)
        token=secrets.token_urlsafe(48); expires=self.clock()+30*86400
        with self.transaction() as db:
            self._cleanup(db)
            existing=db.execute('SELECT kind FROM accounts WHERE id=?',(account,)).fetchone()
            if existing is None:
                row=db.execute('SELECT used FROM guest_registrations WHERE network=? AND day=?',(network_key,self._day())).fetchone()
                if row is not None and row['used'] >= 5:
                    raise AccountError('Guest setup limit reached for this network. Try again tomorrow.',429,'guest_setup_limited')
                db.execute('INSERT INTO guest_registrations VALUES(?,?,1) ON CONFLICT(network,day) DO UPDATE SET used=guest_registrations.used+1',(network_key,self._day()))
                db.execute("INSERT INTO accounts(id,refresh,verified,created,kind) VALUES(?,?,?,?,'guest')",
                           (account,self.cipher.encrypt(b''),self.clock(),self.clock()))
            elif existing['kind'] != 'guest': raise AccountError('Invalid guest sign-in.',400,'invalid_request')
            db.execute('INSERT INTO sessions VALUES(?,?,?)',(digest(token),account,expires))
            db.execute('DELETE FROM sessions WHERE account=? AND hash NOT IN (SELECT hash FROM sessions WHERE account=? ORDER BY expires DESC LIMIT 20)',(account,account))
        return {'token':token,'accountID':account,'expiresAt':iso(expires),'usage':self.usage(Session(account,digest(token)))}

    def authenticate(self,authorization):
        if not authorization.startswith('Bearer ') or not 32 <= len(authorization[7:]) <= 256:
            raise AccountError('Sign in or continue as a guest to use online AI.')
        hashed=digest(authorization[7:])
        with self.transaction() as db:
            self._cleanup(db)
            row=db.execute('SELECT a.*,s.hash FROM sessions s JOIN accounts a ON a.id=s.account WHERE s.hash=?',(hashed,)).fetchone()
            if row is None: raise AccountError('Sign in or continue as a guest to use online AI.')
            user=Session(row['id'],hashed)
        if row['kind'] == 'apple' and self.clock()-row['verified'] >= 86400:
            try:
                result=self.apple.refresh(self.cipher.decrypt(row['refresh']).decode())
                if not isinstance(result,dict): raise AccountError('Sign in with Apple again.')
                claims=self.apple.verify_identity(result.get('id_token'))
                if self._subject(claims['sub']) != user.account_id: raise AccountError('Sign in with Apple again.')
            except AccountError as e:
                if e.status == 401: self.purge(user.account_id)
                raise
            with self.transaction() as db:
                if not db.execute('UPDATE accounts SET verified=? WHERE id=?',(self.clock(),user.account_id)).rowcount:
                    raise AccountError('Sign in with Apple again.')
        return user

    def usage(self,user):
        with self.transaction() as db:
            self._cleanup(db)
            row=db.execute('SELECT used FROM quota WHERE account=? AND day=?',(user.account_id,self._day())).fetchone()
            used=row['used'] if row else 0
        reset=datetime.fromtimestamp(self.clock(),timezone.utc).replace(hour=0,minute=0,second=0,microsecond=0)+timedelta(days=1)
        return {'limit':self.daily_limit,'used':used,'remaining':max(0,self.daily_limit-used),
                'resetsAt':iso(reset.timestamp()),'mealPlanCost':5,'shortRequestCost':1}

    def request_fingerprint(self, path, body):
        return hmac.new(self.subject_secret,path.encode()+b'\0'+body,hashlib.sha256).hexdigest()

    def reserve(self,user,path,request_key=None,fingerprint=None):
        cost=5 if path=='/api/meal-plan' else 1; day=self._day(); reservation=secrets.token_urlsafe(32)
        if request_key is not None:
            if not isinstance(request_key,str) or not 8 <= len(request_key) <= 128 or not isinstance(fingerprint,str):
                raise AccountError('Invalid request key.',400,'invalid_request')
            request_key=digest(request_key)
        with self.transaction() as db:
            self._cleanup(db)
            if not db.execute('SELECT 1 FROM sessions WHERE hash=? AND account=?',(user.session_hash,user.account_id)).fetchone():
                raise AccountError('Sign in with Apple again.')
            if request_key is not None:
                previous=db.execute('SELECT fingerprint FROM ai_requests WHERE account=? AND key=?',(user.account_id,request_key)).fetchone()
                if previous is not None:
                    if not hmac.compare_digest(previous['fingerprint'],fingerprint):
                        raise AccountError('This request key was already used for different input.',409,'ai_request_conflict')
                    raise AccountError('This request is already processing or completed. No additional credits were used.',409,'ai_request_repeated')
                if db.execute('SELECT COUNT(*) FROM ai_requests WHERE account=?',(user.account_id,)).fetchone()[0]>=2048:
                    raise AccountError('Too many recent requests. Please try again later.',503,'ai_unavailable')
            db.execute('INSERT OR IGNORE INTO quota(account,day) VALUES(?,?)',(user.account_id,day))
            db.execute('INSERT OR IGNORE INTO global_quota(day) VALUES(?)',(day,))
            used=db.execute('SELECT used FROM quota WHERE account=? AND day=?',(user.account_id,day)).fetchone()[0]
            if used+cost>self.daily_limit:
                raise AccountError('Your daily AI allowance is used up. Local features remain available.',429,'ai_quota_exceeded')
            if db.execute('SELECT used FROM global_quota WHERE day=?',(day,)).fetchone()[0]>=self.global_limit:
                raise AccountError('Online AI is at shared capacity. Your personal allowance is unchanged.',503,'ai_shared_capacity')
            db.execute('UPDATE quota SET used=used+? WHERE account=? AND day=?',(cost,user.account_id,day))
            db.execute('UPDATE global_quota SET used=used+1 WHERE day=?',(day,))
            db.execute('INSERT INTO reservations VALUES(?,?,?,?,?)',(reservation,user.account_id,day,cost,self.clock()+180))
            if request_key is not None:
                db.execute('INSERT INTO ai_requests VALUES(?,?,?,?)',(user.account_id,request_key,fingerprint,self.clock()))
        return reservation

    def finish(self,reservation,succeeded,attempted):
        with self.transaction() as db:
            row=db.execute('SELECT * FROM reservations WHERE id=?',(reservation,)).fetchone()
            if row is None: return False
            if not succeeded:
                db.execute('UPDATE quota SET used=MAX(0,used-?) WHERE account=? AND day=?',
                           (row['cost'],row['account'],row['day']))
            if not attempted:
                db.execute('UPDATE global_quota SET used=MAX(0,used-1) WHERE day=?',(row['day'],))
            db.execute('DELETE FROM reservations WHERE id=?',(reservation,))
            return True

    def logout(self,user):
        with self.transaction() as db: db.execute('DELETE FROM sessions WHERE hash=?',(user.session_hash,))

    def purge(self,account,event_time=None):
        with self.transaction() as db:
            row=db.execute('SELECT created FROM accounts WHERE id=?',(account,)).fetchone()
            if row is None or (event_time is not None and row['created']>event_time): return
            # In-flight requests invalidated by deletion cannot deliver a result.
            for pending in db.execute('SELECT day,cost FROM reservations WHERE account=?',(account,)).fetchall():
                db.execute('UPDATE quota SET used=MAX(0,used-?) WHERE account=? AND day=?',
                           (pending['cost'],account,pending['day']))
            db.execute('DELETE FROM accounts WHERE id=?',(account,))

    def delete_account(self,user):
        with self.transaction() as db:
            row=db.execute('SELECT refresh,kind FROM accounts WHERE id=?',(user.account_id,)).fetchone()
        if row is None: raise AccountError('Sign in with Apple again.')
        if row['kind'] == 'apple': self.apple.revoke(self.cipher.decrypt(row['refresh']).decode())
        self.purge(user.account_id)
