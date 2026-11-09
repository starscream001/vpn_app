"""Isolated reference control API. No VPN server administration or bot token.
Run behind a TLS reverse proxy. Provision access only from a trusted bot backend.
"""
import hashlib
import json
import os
import secrets
import sqlite3
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class ApiError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


class Store:
    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS codes(hash TEXT PRIMARY KEY, subject TEXT, expires INTEGER);
        CREATE TABLE IF NOT EXISTS tokens(hash TEXT PRIMARY KEY, subject TEXT, expires INTEGER);
        CREATE TABLE IF NOT EXISTS catalog(subject TEXT PRIMARY KEY, body TEXT);
        CREATE TABLE IF NOT EXISTS reports(subject TEXT, received INTEGER, body TEXT);
        ''')

    def provision(self, subject, catalog):
        """Trusted adapter calls this after bot has verified entitlement. Never public API."""
        self.db.execute('INSERT OR REPLACE INTO catalog VALUES (?,?)', (subject, json.dumps(catalog)))
        self.db.commit()

    def issue_code(self, subject):
        code = secrets.token_urlsafe(18)
        self.db.execute('INSERT INTO codes VALUES (?,?,?)', (digest(code), subject, int(time.time()) + 300))
        self.db.commit()
        return code

    def exchange(self, code):
        # SQLite transaction ensures the same one-time code cannot be spent twice.
        with self.db:
            self.db.execute('BEGIN IMMEDIATE')
            row = self.db.execute('SELECT subject,expires FROM codes WHERE hash=?', (digest(code),)).fetchone()
            if not row or row[1] <= time.time():
                raise ApiError(401, 'Invalid or expired code')
            self.db.execute('DELETE FROM codes WHERE hash=?', (digest(code),))
            token = secrets.token_urlsafe(32)
            self.db.execute('INSERT INTO tokens VALUES (?,?,?)', (digest(token), row[0], int(time.time()) + 604800))
        return {'access_token': token, 'expires_in': 604800}

    def authorize(self, token):
        row = self.db.execute('SELECT subject,expires FROM tokens WHERE hash=?', (digest(token),)).fetchone()
        if not row or row[1] <= time.time():
            raise ApiError(401, 'Unauthorized')
        return row[0]

    def catalog(self, subject):
        row = self.db.execute('SELECT body FROM catalog WHERE subject=?', (subject,)).fetchone()
        if not row:
            raise ApiError(403, 'No subscription')
        return json.loads(row[0])

    def report(self, subject, body):
        reports = body.get('reports')
        if body.get('schema') != 1 or not isinstance(reports, list) or not 1 <= len(reports) <= 20:
            raise ApiError(400, 'Invalid report batch')
        allowed = {p['id'] for p in self.catalog(subject)['profiles']}
        fields = {'profile_id', 'protocol', 'ok', 'latency_ms', 'rx_delta', 'tx_delta', 'reason', 'at'}
        reasons = {'https_204', 'tunnel_down', 'route_or_response_failed', 'https_failed', 'start_failed'}
        for item in reports:
            if not isinstance(item, dict) or set(item) != fields or item['profile_id'] not in allowed:
                raise ApiError(400, 'Unknown fields or profile')
            if item['protocol'] not in ('vless', 'amnezia') or type(item['ok']) is not bool or item['reason'] not in reasons:
                raise ApiError(400, 'Invalid quality result')
            if not isinstance(item['at'], str) or len(item['at']) > 40:
                raise ApiError(400, 'Invalid timestamp')
            for field in ('latency_ms', 'rx_delta', 'tx_delta'):
                if type(item[field]) is not int or not 0 <= item[field] <= 2**53:
                    raise ApiError(400, 'Invalid measurement')
        now = int(time.time())
        # Retention and rate limit are per authorized subscription, not by browsing IP.
        self.db.execute('DELETE FROM reports WHERE received < ?', (now - 7*86400,))
        count = self.db.execute('SELECT COUNT(*) FROM reports WHERE subject=? AND received>?', (subject, now-60)).fetchone()[0]
        if count >= 10:
            raise ApiError(429, 'Report rate limit')
        self.db.execute('INSERT INTO reports VALUES (?,?,?)', (subject, now, json.dumps(reports)))
        self.db.commit()
        return {'accepted': len(reports)}


def handler(database):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Never log bearer tokens, one-time codes or request bodies.

        def do_GET(self):
            self.dispatch()

        def do_POST(self):
            self.dispatch()

        def dispatch(self):
            store = Store(database)
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 <= length <= 65536:
                    raise ApiError(413, 'Body too large')
                self.connection.settimeout(10)
                body = json.loads(self.rfile.read(length)) if length else {}
                if not isinstance(body, dict):
                    raise ApiError(400, 'Object required')
                if self.path == '/v1/auth/exchange' and self.command == 'POST':
                    code = body.get('code')
                    if not isinstance(code, str) or not 10 <= len(code) <= 128:
                        raise ApiError(400, 'Invalid code')
                    result = store.exchange(code)
                else:
                    auth = self.headers.get('Authorization', '')
                    subject = store.authorize(auth[7:] if auth.startswith('Bearer ') else '')
                    if self.path == '/v1/catalog' and self.command == 'GET':
                        result = store.catalog(subject)
                    elif self.path == '/v1/quality/reports' and self.command == 'POST':
                        result = store.report(subject, body)
                    else:
                        raise ApiError(404, 'Not found')
                self.respond(200, result)
            except ApiError as err:
                self.respond(err.status, {'error': err.message})
            except (ValueError, TypeError, KeyError):
                self.respond(400, {'error': 'Invalid request'})
            finally:
                store.db.close()

        def respond(self, status, value):
            encoded = json.dumps(value).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
    return Handler


if __name__ == '__main__':
    # Bind loopback only. TLS, request limiting and production process management
    # belong to a separately reviewed deployment. Nothing is auto-deployed.
    database = os.environ.get('FOXWAY_DB', 'foxway.sqlite')
    Path(database).touch(mode=0o600, exist_ok=True)
    server = ThreadingHTTPServer(('127.0.0.1', 8787), handler(database))
    server.serve_forever()
