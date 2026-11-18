"""Apple-authenticated daily allowances. No health data is stored here.

SQLite requires one shared, durable volume. Do not put this database on Render's
free ephemeral filesystem or scale independent copies of this service.
"""
import base64
import contextlib
import hashlib
import hmac
import ipaddress
import json
import os
import secrets
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import ai_usage
from account_storage import AccountStorage
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta

AI_PATHS = frozenset({'/api/meal-plan','/api/agent-chat','/api/recipe',
                      '/api/gap-fillers','/api/shopping-advice','/api/workout'})

# Credits kept when the provider answered but its output failed validation. The
# provider call was paid for, so a full refund would let one account drain the
# shared daily attempt ceiling for free.
UNUSABLE_OUTPUT_COST = 1

# Expired-row housekeeping runs at most this often per process (seconds). Every
# read that depends on expiry also checks it directly, so a delay is harmless.
CLEANUP_INTERVAL = 60

# Apple sign-in challenges one client address may hold at a time. A newer one
# replaces that address's oldest, so one address cannot fill the shared table.
CHALLENGES_PER_CLIENT = 10
CHALLENGES_TOTAL = 10000

# An Apple account is re-checked with Apple once a day. When Apple cannot be
# reached (transport error or 5xx), a session stays usable until this long after
# its last successful check; a revoked grant still ends it at the next check
# that gets an answer.
APPLE_RECHECK_AFTER = 86400
APPLE_OUTAGE_GRACE = 72 * 3600
# After a check Apple could not answer, wait this long before asking again for
# accounts that are still inside the grace period.
APPLE_RETRY_PAUSE = 300


class AccountError(Exception):
    def __init__(self, message, status=401, code='ai_sign_in_required'):
        super().__init__(message)
        self.message, self.status, self.code = message, status, code


class AppleGrantRevoked(AccountError):
    """Apple answered invalid_grant: the code or refresh grant is no longer valid."""
    def __init__(self):
        super().__init__('Sign in with Apple again.')


def network_key(address):
    """The network an address is counted under: the address itself for IPv4, the
    /64 for IPv6 (one home or phone usually owns a whole /64, so per-address
    limits would be trivial to step around)."""
    text = str(address or 'unknown').strip()[:64]
    try:
        ip = ipaddress.ip_address(text.split('%', 1)[0])
    except ValueError:
        return text
    if ip.version == 6:
        if ip.ipv4_mapped is not None: return str(ip.ipv4_mapped)
        return str(ipaddress.IPv6Network((int(ip) >> 64 << 64, 64)))
    return str(ip)


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
            # Only invalid_grant means the person's code or grant is no longer valid.
            # Any other 400 (invalid_client, invalid_request ...) is this service's
            # configuration or request, so the account must not be treated as revoked.
            reason = None
            if e.code == 400:
                try:
                    detail = json.loads(e.read(65536))
                    reason = detail.get('error') if isinstance(detail, dict) else None
                except Exception:
                    reason = None
            if reason == 'invalid_grant':
                raise AppleGrantRevoked() from None
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


def default_guest_pool(global_limit):
    """Guests get a quarter of the shared daily ceiling unless configured."""
    return max(1, global_limit // 4)


class AccountService:
    def __init__(self,path,apple,cipher,subject_secret,daily_limit=30,global_limit=900,clock=time.time,guest_enabled=False,
                 guest_global_limit=None):
        if len(subject_secret) < 32:
            raise ValueError('AI subject secret must contain at least 32 bytes')
        self.path,self.apple,self.cipher,self.subject_secret = path,apple,cipher,subject_secret
        self.daily_limit,self.global_limit,self.clock = daily_limit,global_limit,clock
        self.guest_enabled = guest_enabled
        # Guests share a smaller daily pool inside the shared ceiling, so guest
        # traffic alone can never use up the capacity signed-in people rely on.
        self.guest_global_limit = default_guest_pool(global_limit) if guest_global_limit is None else guest_global_limit
        self._apple_retry_at = 0.0
        self._cleanup_lock = threading.Lock()
        self._last_cleanup = None
        self.storage = AccountStorage(path)
        with self.transaction() as db:
            db.executescript('''
              CREATE TABLE IF NOT EXISTS accounts(id TEXT PRIMARY KEY, refresh BLOB NOT NULL, verified REAL NOT NULL, created REAL NOT NULL, kind TEXT NOT NULL DEFAULT 'apple');
              CREATE TABLE IF NOT EXISTS sessions(hash TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, expires REAL NOT NULL);
              CREATE TABLE IF NOT EXISTS challenges(id TEXT PRIMARY KEY, nonce TEXT NOT NULL, expires REAL NOT NULL, client TEXT);
              CREATE TABLE IF NOT EXISTS quota(account TEXT NOT NULL, day TEXT NOT NULL, used INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(account,day));
              CREATE TABLE IF NOT EXISTS global_quota(day TEXT PRIMARY KEY, used INTEGER NOT NULL DEFAULT 0);
              CREATE TABLE IF NOT EXISTS guest_global_quota(day TEXT PRIMARY KEY, used INTEGER NOT NULL DEFAULT 0);
              CREATE TABLE IF NOT EXISTS reservations(id TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, day TEXT NOT NULL, cost INTEGER NOT NULL, expires REAL NOT NULL);
              CREATE INDEX IF NOT EXISTS session_account ON sessions(account);
              CREATE TABLE IF NOT EXISTS guest_registrations(network TEXT NOT NULL, day TEXT NOT NULL, used INTEGER NOT NULL, PRIMARY KEY(network,day));
              CREATE TABLE IF NOT EXISTS ai_requests(account TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, key TEXT NOT NULL, fingerprint TEXT NOT NULL, created REAL NOT NULL, reservation TEXT, response BLOB, status INTEGER, content_type TEXT, result TEXT, PRIMARY KEY(account,key));
            ''')
            # reservation: set while the request is in flight, NULL once finished.
            # response/status/content_type/result are left over from a version that
            # kept response bodies for replay. Nothing writes them now; they stay in
            # the table only so older databases keep working, and are emptied below.
            replay_columns = (('reservation','TEXT'),('response','BLOB'),('status','INTEGER'),
                              ('content_type','TEXT'),('result','TEXT'))
            if self.storage.postgres:
                for name, kind in replay_columns:
                    db.execute(f'ALTER TABLE ai_requests ADD COLUMN IF NOT EXISTS {name} {kind}')
                db.execute('ALTER TABLE challenges ADD COLUMN IF NOT EXISTS client TEXT')
            else:
                existing = {r['name'] for r in db.execute('PRAGMA table_info(ai_requests)')}
                for name, kind in replay_columns:
                    if name not in existing: db.execute(f'ALTER TABLE ai_requests ADD COLUMN {name} {kind}')
                if 'client' not in {r['name'] for r in db.execute('PRAGMA table_info(challenges)')}:
                    db.execute('ALTER TABLE challenges ADD COLUMN client TEXT')
            # AI responses are never kept: erase any body an older version stored.
            db.execute('UPDATE ai_requests SET response=NULL,status=NULL,content_type=NULL,result=NULL '
                       'WHERE response IS NOT NULL')
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
        guest_pool = os.environ.get('AI_GUEST_GLOBAL_DAILY_ATTEMPTS','').strip()
        guest_pool = int(guest_pool) if guest_pool else default_guest_pool(global_limit)
        if not 1 <= guest_pool <= global_limit:
            raise ValueError('Invalid AI allowance configuration')
        guest_enabled = os.environ.get('AI_GUEST_ENABLED') == '1'
        apple_enabled = os.environ.get('AI_APPLE_ENABLED','1') == '1'
        if not guest_enabled and not apple_enabled: raise ValueError('Enable an AI sign-in method')
        apple = (AppleAuthority(os.environ.get('APPLE_APP_ID','com.mostafa.mealio'),
                               os.environ['APPLE_TEAM_ID'],os.environ['APPLE_KEY_ID'],
                               os.environ['APPLE_PRIVATE_KEY']) if apple_enabled else None)
        return cls(path,apple,Fernet(os.environ['AI_TOKEN_ENCRYPTION_KEY'].encode()),
                   os.environ['AI_SUBJECT_SECRET'].encode(),limit,global_limit,guest_enabled=guest_enabled,
                   guest_global_limit=guest_pool)

    @contextlib.contextmanager
    def transaction(self):
        with self.storage.transaction() as connection:
            yield connection

    def _day(self): return datetime.fromtimestamp(self.clock(),timezone.utc).date().isoformat()

    def _cleanup_if_due(self):
        """Run housekeeping in its own transaction, at most once per interval."""
        now=self.clock()
        with self._cleanup_lock:
            last=self._last_cleanup
            # A clock that moved backwards (tests, NTP) also triggers a run.
            if last is not None and 0 <= now-last < CLEANUP_INTERVAL: return
            self._last_cleanup=now
        try:
            with self.transaction() as db: self._cleanup(db)
        except Exception:
            with self._cleanup_lock: self._last_cleanup=last
            raise

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
        db.execute('DELETE FROM guest_global_quota WHERE day<?',(cutoff,))

    def _subject(self,sub): return hmac.new(self.subject_secret,sub.encode(),hashlib.sha256).hexdigest()

    def challenge(self,client=None):
        if self.apple is None: raise AccountError('Apple sign-in is unavailable. Use guest access.',503,'ai_unavailable')
        value={'id':secrets.token_urlsafe(32),'nonce':digest(secrets.token_urlsafe(32))}
        # A keyed hash of the caller's network, never the address itself.
        owner=self._subject('challenge-client:'+network_key(client))
        self._cleanup_if_due()
        with self.transaction() as db:
            now=self.clock()
            # One address keeps at most CHALLENGES_PER_CLIENT live challenges: its
            # oldest make room, so it cannot fill the table and block everyone's sign-in.
            db.execute('DELETE FROM challenges WHERE client=? AND id NOT IN '
                       '(SELECT id FROM challenges WHERE client=? AND expires>? ORDER BY expires DESC, id DESC LIMIT ?)',
                       (owner,owner,now,CHALLENGES_PER_CLIENT-1))
            # Bound unauthenticated challenge storage overall; the IP rate limiter applies too.
            if db.execute('SELECT COUNT(*) FROM challenges WHERE expires>?',(now,)).fetchone()[0] >= CHALLENGES_TOTAL:
                raise AccountError('Sign-in is busy. Please retry shortly.',503,'ai_unavailable')
            db.execute('INSERT INTO challenges(id,nonce,expires,client) VALUES(?,?,?,?)',
                       (value['id'],value['nonce'],now+300,owner))
        return {**value,'expiresAt':iso(self.clock()+300)}

    def login(self,identity_token,code,challenge_id):
        if self.apple is None: raise AccountError('Apple sign-in is unavailable. Use guest access.',503,'ai_unavailable')
        if not isinstance(challenge_id,str): raise AccountError('Sign in with Apple again.')
        self._cleanup_if_due()
        with self.transaction() as db:
            row=db.execute('SELECT * FROM challenges WHERE id=? AND expires>?',(challenge_id,self.clock())).fetchone()
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
        # IPv6 is counted per /64, so one connection cannot mint guests without limit.
        network_id=self._subject('guest-network:'+self._day()+':'+network_key(network))
        token=secrets.token_urlsafe(48); expires=self.clock()+30*86400
        self._cleanup_if_due()
        with self.transaction() as db:
            existing=db.execute('SELECT kind FROM accounts WHERE id=?',(account,)).fetchone()
            if existing is None:
                row=db.execute('SELECT used FROM guest_registrations WHERE network=? AND day=?',(network_id,self._day())).fetchone()
                if row is not None and row['used'] >= 5:
                    raise AccountError('Guest setup limit reached for this network. Try again tomorrow.',429,'guest_setup_limited')
                db.execute('INSERT INTO guest_registrations VALUES(?,?,1) ON CONFLICT(network,day) DO UPDATE SET used=guest_registrations.used+1',(network_id,self._day()))
                db.execute("INSERT INTO accounts(id,refresh,verified,created,kind) VALUES(?,?,?,?,'guest')",
                           (account,self.cipher.encrypt(b''),self.clock(),self.clock()))
            elif existing['kind'] != 'guest': raise AccountError('Invalid guest sign-in.',400,'invalid_request')
            db.execute('INSERT INTO sessions VALUES(?,?,?)',(digest(token),account,expires))
            db.execute('DELETE FROM sessions WHERE account=? AND hash NOT IN (SELECT hash FROM sessions WHERE account=? ORDER BY expires DESC LIMIT 20)',(account,account))
        return {'token':token,'accountID':account,'expiresAt':iso(expires),'usage':self.usage(Session(account,digest(token)))}

    def authenticate(self,authorization,verify_apple=True):
        """Resolve a Bearer session. verify_apple=False skips the daily Apple
        re-check: used only for signing out and deleting one's own account, which
        must keep working when Apple is unreachable or Apple sign-in is off."""
        if not authorization.startswith('Bearer ') or not 32 <= len(authorization[7:]) <= 256:
            raise AccountError('Sign in or continue as a guest to use online AI.')
        hashed=digest(authorization[7:])
        self._cleanup_if_due()
        with self.transaction() as db:
            row=db.execute('SELECT a.*,s.hash FROM sessions s JOIN accounts a ON a.id=s.account WHERE s.hash=? AND s.expires>?',(hashed,self.clock())).fetchone()
            if row is None: raise AccountError('Sign in or continue as a guest to use online AI.')
            user=Session(row['id'],hashed)
        age=self.clock()-row['verified']
        if verify_apple and row['kind'] == 'apple' and age >= APPLE_RECHECK_AFTER:
            in_grace=age < APPLE_OUTAGE_GRACE
            if self.apple is None:
                # Apple sign-in was switched off after this account was made.
                raise AccountError('Apple sign-in is switched off on this service right now. '
                                   'Please try again later.',503,'ai_unavailable')
            if in_grace and self.clock() < self._apple_retry_at:
                return user  # Apple was unreachable moments ago: do not ask again yet
            try:
                result=self.apple.refresh(self.cipher.decrypt(row['refresh']).decode())
                if not isinstance(result,dict): raise AccountError('Sign in with Apple again.')
                claims=self.apple.verify_identity(result.get('id_token'))
                if self._subject(claims['sub']) != user.account_id: raise AccountError('Sign in with Apple again.')
            except AppleGrantRevoked:
                # Apple says the grant is gone: the account and its sessions go too.
                self.purge(user.account_id)
                raise
            except AccountError as e:
                # Nothing else deletes an account. When Apple could not be reached,
                # the session keeps working for a limited time since its last check.
                if e.status == 503:
                    self._apple_retry_at=self.clock()+APPLE_RETRY_PAUSE
                    if in_grace: return user
                raise
            self._apple_retry_at=0.0
            with self.transaction() as db:
                if not db.execute('UPDATE accounts SET verified=? WHERE id=?',(self.clock(),user.account_id)).rowcount:
                    raise AccountError('Sign in with Apple again.')
        return user

    def usage(self,user):
        self._cleanup_if_due()
        with self.transaction() as db:
            row=db.execute('SELECT used FROM quota WHERE account=? AND day=?',(user.account_id,self._day())).fetchone()
            used=row['used'] if row else 0
        return self._usage_view(used)

    def _usage_view(self,used):
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
        self._cleanup_if_due()
        with self.transaction() as db:
            owner=db.execute('SELECT a.kind FROM sessions s JOIN accounts a ON a.id=s.account '
                             'WHERE s.hash=? AND s.account=? AND s.expires>?',
                             (user.session_hash,user.account_id,self.clock())).fetchone()
            if owner is None: raise AccountError('Sign in with Apple again.')
            guest=owner['kind'] == 'guest'
            if request_key is not None:
                previous=db.execute('SELECT * FROM ai_requests WHERE account=? AND key=?',(user.account_id,request_key)).fetchone()
                if previous is not None:
                    if not hmac.compare_digest(previous['fingerprint'],fingerprint):
                        raise AccountError('This request key was already used for different input.',409,'ai_request_conflict')
                    if previous['reservation'] is not None and self._release_abandoned(db,user.account_id,request_key,previous['reservation']):
                        previous=None  # its worker died: the claim is gone and the client may run it again
                if previous is not None:
                    # Responses are not kept, so a repeated key is never replayed
                    # or rerun: the caller is told what happened to the first one.
                    raise AccountError(('This request is still being processed. No additional credits were used.'
                                        if previous['reservation'] is not None else
                                        'This request was already processed. No additional credits were used. '
                                        'Send it again as a new request if you still need an answer.'),
                                       409,'ai_request_repeated')
                if db.execute('SELECT COUNT(*) FROM ai_requests WHERE account=?',(user.account_id,)).fetchone()[0]>=2048:
                    raise AccountError('Too many recent requests. Please try again later.',503,'ai_unavailable')
            db.execute('INSERT OR IGNORE INTO quota(account,day) VALUES(?,?)',(user.account_id,day))
            db.execute('INSERT OR IGNORE INTO global_quota(day) VALUES(?)',(day,))
            used=db.execute('SELECT used FROM quota WHERE account=? AND day=?',(user.account_id,day)).fetchone()[0]
            if used+cost>self.daily_limit:
                raise AccountError('Your daily AI allowance is used up. Local features remain available.',429,'ai_quota_exceeded')
            if db.execute('SELECT used FROM global_quota WHERE day=?',(day,)).fetchone()[0]>=self.global_limit:
                raise AccountError('Online AI is at shared capacity. Your personal allowance is unchanged.',503,'ai_shared_capacity')
            if guest:
                db.execute('INSERT OR IGNORE INTO guest_global_quota(day) VALUES(?)',(day,))
                if db.execute('SELECT used FROM guest_global_quota WHERE day=?',(day,)).fetchone()[0]>=self.guest_global_limit:
                    raise AccountError('Guest AI is at shared capacity for today. Your personal allowance is unchanged. '
                                       'Sign in with Apple or try again tomorrow.',503,'ai_shared_capacity')
                db.execute('UPDATE guest_global_quota SET used=used+1 WHERE day=?',(day,))
            db.execute('UPDATE quota SET used=used+? WHERE account=? AND day=?',(cost,user.account_id,day))
            db.execute('UPDATE global_quota SET used=used+1 WHERE day=?',(day,))
            db.execute('INSERT INTO reservations VALUES(?,?,?,?,?)',(reservation,user.account_id,day,cost,self.clock()+180))
            if request_key is not None:
                db.execute('INSERT INTO ai_requests(account,key,fingerprint,created,reservation) VALUES(?,?,?,?,?)',
                           (user.account_id,request_key,fingerprint,self.clock(),reservation))
        return reservation

    def _release_abandoned(self,db,account,request_key,reservation):
        """Drop a claim whose request never finished (worker killed or restarted).

        Runs inside the caller's write transaction, so it cannot race the
        original request's finish(): either finish() already settled the claim
        (reservation is NULL) or the reservation has expired and finish() will
        find nothing to settle. An expired reservation is refunded here exactly
        as cleanup would, so the retry is the only charge.
        """
        pending=db.execute('SELECT * FROM reservations WHERE id=?',(reservation,)).fetchone()
        if pending is not None and pending['expires']>self.clock(): return False  # still running
        if pending is not None:
            db.execute('UPDATE quota SET used=MAX(0,used-?) WHERE account=? AND day=?',
                       (pending['cost'],pending['account'],pending['day']))
            db.execute('DELETE FROM reservations WHERE id=?',(reservation,))
        db.execute('DELETE FROM ai_requests WHERE account=? AND key=? AND reservation=?',(account,request_key,reservation))
        return True

    def finish(self,reservation,succeeded,attempted,responded=False,release_request_key=None):
        """Settle a reservation. True when it was still there to settle."""
        return self.finish_with_usage(reservation,succeeded,attempted,responded,release_request_key) is not None

    def finish_with_usage(self,reservation,succeeded,attempted,responded=False,release_request_key=None):
        """Settle a reservation and return the account's usage (as usage() does),
        or None when the reservation is gone (expired, replaced or deleted).

        succeeded: keep the full cost. responded (provider answered, output
        unusable): keep UNUSABLE_OUTPUT_COST. Otherwise (transport/provider
        error, cache, invalid input): full refund. The shared attempt ceilings
        are refunded only when the provider was never attempted.
        release_request_key (unsuccessful requests only) deletes that
        idempotency claim so a retry with the same key runs instead of being
        rejected as a repeat. Otherwise the reservation's claim (if any) is
        marked finished and stays for 24 h as a no-rerun marker: a repeat of
        that key is refused, not run or charged again. The response itself is
        never stored.
        """
        with self.transaction() as db:
            row=db.execute('SELECT * FROM reservations WHERE id=?',(reservation,)).fetchone()
            if row is None: return None
            released=not succeeded and release_request_key is not None
            if not succeeded:
                kept=min(row['cost'],UNUSABLE_OUTPUT_COST) if attempted and responded else 0
                db.execute('UPDATE quota SET used=MAX(0,used-?) WHERE account=? AND day=?',
                           (row['cost']-kept,row['account'],row['day']))
            if released:
                db.execute('DELETE FROM ai_requests WHERE account=? AND reservation=?',(row['account'],reservation))
            else:
                db.execute('UPDATE ai_requests SET reservation=NULL WHERE account=? AND reservation=?',
                           (row['account'],reservation))
            if not attempted:
                db.execute('UPDATE global_quota SET used=MAX(0,used-1) WHERE day=?',(row['day'],))
                owner=db.execute('SELECT kind FROM accounts WHERE id=?',(row['account'],)).fetchone()
                if owner is not None and owner['kind'] == 'guest':
                    db.execute('UPDATE guest_global_quota SET used=MAX(0,used-1) WHERE day=?',(row['day'],))
            db.execute('DELETE FROM reservations WHERE id=?',(reservation,))
            today=db.execute('SELECT used FROM quota WHERE account=? AND day=?',(row['account'],self._day())).fetchone()
            return self._usage_view(today['used'] if today else 0)

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
        for forget in list(ai_usage.on_account_deleted):
            try: forget(account)
            except Exception: pass  # a cache that fails to clear must not undo a deletion

    def delete_account(self,user):
        with self.transaction() as db:
            row=db.execute('SELECT refresh,kind FROM accounts WHERE id=?',(user.account_id,)).fetchone()
        if row is None: raise AccountError('Sign in with Apple again.')
        # With Apple sign-in switched off there is nothing to revoke with: the
        # account is still deleted here (the person can remove the app's access
        # in their Apple account settings).
        if row['kind'] == 'apple' and self.apple is not None:
            try: self.apple.revoke(self.cipher.decrypt(row['refresh']).decode())
            except AppleGrantRevoked: pass  # already revoked at Apple: nothing left to revoke
        self.purge(user.account_id)
