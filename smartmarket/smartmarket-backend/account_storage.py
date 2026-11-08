"""Transactional account storage; credentials and request bodies are never logged.

A transaction-wide Postgres advisory lock preserves the single-writer semantics
used by SQLite BEGIN IMMEDIATE, including quota reservations across workers.
"""
import contextlib
import sqlite3


class Record(dict):
    def __getitem__(self, key):
        return tuple(self.values())[key] if isinstance(key, int) else super().__getitem__(key)


class Cursor:
    def __init__(self, cursor): self.cursor = cursor
    @property
    def rowcount(self): return self.cursor.rowcount
    def fetchone(self):
        row = self.cursor.fetchone()
        return None if row is None else Record(row)
    def fetchall(self): return [Record(row) for row in self.cursor.fetchall()]
    def __iter__(self): return iter(self.fetchall())


class PostgresConnection:
    def __init__(self, connection): self.connection = connection
    def execute(self, statement, parameters=()):
        # Only application-owned SQL reaches this adapter. Values remain bound.
        statement = statement.replace('?', '%s').replace('BLOB', 'BYTEA').replace('REAL', 'DOUBLE PRECISION')
        statement = statement.replace('MAX(0,', 'GREATEST(0,')
        if statement.startswith('INSERT OR IGNORE INTO '):
            statement = statement.replace('INSERT OR IGNORE INTO ', 'INSERT INTO ', 1) + ' ON CONFLICT DO NOTHING'
        return Cursor(self.connection.execute(statement, parameters))
    def executescript(self, script):
        for statement in script.split(';'):
            if statement.strip(): self.execute(statement.strip())


class AccountStorage:
    def __init__(self, location):
        self.location = location
        self.postgres = location.startswith(('postgres://', 'postgresql://'))

    @contextlib.contextmanager
    def transaction(self):
        if self.postgres:
            import certifi
            import psycopg
            from psycopg.rows import dict_row
            with psycopg.connect(self.location, autocommit=True, row_factory=dict_row,
                                 sslmode='verify-full', sslrootcert=certifi.where(),
                                 connect_timeout=15, prepare_threshold=None,
                                 application_name='nourlo-accounts') as connection:
                with connection.transaction():
                    connection.execute("SET LOCAL lock_timeout = '10s'")
                    connection.execute("SET LOCAL statement_timeout = '20s'")
                    connection.execute('SELECT pg_advisory_xact_lock(72668704)')
                    yield PostgresConnection(connection)
            return
        connection = sqlite3.connect(self.location, timeout=10, isolation_level=None)
        connection.row_factory = sqlite3.Row
        try:
            connection.execute('PRAGMA foreign_keys=ON')
            connection.execute('PRAGMA journal_mode=WAL')
            connection.execute('BEGIN IMMEDIATE')
            yield connection
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()
