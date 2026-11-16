"""Optional real-Postgres contracts; only a disposable synthetic schema is changed."""
import concurrent.futures
import os
import secrets
import uuid
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode
import pytest
from cryptography.fernet import Fernet
from ai_accounts import AccountService, AccountError

pytestmark = pytest.mark.skipif(not os.environ.get('NOURLO_TEST_DATABASE_URL'), reason='Real Postgres test connection not configured')


@pytest.fixture(scope='module')
def database():
    import certifi
    import psycopg
    from psycopg import sql
    base = os.environ['NOURLO_TEST_DATABASE_URL']
    schema = 'nourlo_test_' + uuid.uuid4().hex
    with psycopg.connect(base, sslmode='verify-full', sslrootcert=certifi.where(), autocommit=True) as connection:
        connection.execute(sql.SQL('CREATE SCHEMA {}').format(sql.Identifier(schema)))
    parsed = urlsplit(base)
    params = dict(parse_qsl(parsed.query))
    params['options'] = '-csearch_path=' + schema
    location = urlunsplit((parsed.scheme, parsed.netloc, parsed.path, urlencode(params), parsed.fragment))
    cipher, subject = Fernet(Fernet.generate_key()), secrets.token_bytes(32)
    def create(): return AccountService(location, None, cipher, subject, daily_limit=10, global_limit=1000, guest_enabled=True)
    yield create
    with psycopg.connect(base, sslmode='verify-full', sslrootcert=certifi.where(), autocommit=True) as connection:
        connection.execute(sql.SQL('DROP SCHEMA {} CASCADE').format(sql.Identifier(schema)))


def test_postgres_guest_allowance_survives_store_reopen(database):
    service = database()
    signed = service.guest_login(secrets.token_urlsafe(32), 'synthetic-restart')
    user = service.authenticate('Bearer ' + signed['token'])
    reservation = service.reserve(user, '/api/meal-plan')
    assert service.finish(reservation, succeeded=True, attempted=True)
    reopened = database()
    recovered = reopened.authenticate('Bearer ' + signed['token'])
    assert reopened.usage(recovered)['remaining'] == 5
    reopened.delete_account(recovered)
    with pytest.raises(AccountError): reopened.authenticate('Bearer ' + signed['token'])


def test_postgres_refund_and_deleted_inflight_request(database):
    service = database()
    signed = service.guest_login(secrets.token_urlsafe(32), 'synthetic-refund')
    user = service.authenticate('Bearer ' + signed['token'])
    reservation = service.reserve(user, '/api/meal-plan')
    assert service.finish(reservation, succeeded=False, attempted=True)
    assert service.usage(user)['remaining'] == 10
    pending = service.reserve(user, '/api/meal-plan')
    service.delete_account(user)
    assert service.finish(pending, succeeded=True, attempted=True) is False


def test_postgres_parallel_reservations_cannot_overspend(database):
    service = database()
    signed = service.guest_login(secrets.token_urlsafe(32), 'synthetic-concurrency')
    user = service.authenticate('Bearer ' + signed['token'])
    def reserve(_):
        try: return service.reserve(user, '/api/meal-plan')
        except AccountError as error:
            assert error.code == 'ai_quota_exceeded'
            return None
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        reservations = [result for result in pool.map(reserve, range(4)) if result]
    assert len(reservations) == 2
    assert service.usage(user)['remaining'] == 0
    for reservation in reservations: service.finish(reservation, succeeded=True, attempted=True)
    service.delete_account(user)
