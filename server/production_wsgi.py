"""WSGI bridge for the existing request handlers; no development HTTP listener.

Run behind the single HTTPS reverse proxy in deployment/compose.yaml:
  gunicorn --chdir server --workers 1 --threads 4 production_wsgi:application
"""
from email.message import Message
from http import HTTPStatus
from io import BytesIO
import os
from pathlib import Path
from types import SimpleNamespace
from urllib.parse import urlsplit

from app import Handler, ROOT, initialize


def validate_config():
    origin = urlsplit(os.environ.get('PUBLIC_ORIGIN', ''))
    if os.environ.get('APP_ENV') != 'production' or origin.scheme != 'https' or not origin.hostname or origin.path or origin.query or origin.fragment:
        raise ValueError('Configure APP_ENV=production and PUBLIC_ORIGIN=https://your-domain.')
    if not os.environ.get('DEVELOPER_NAME') or not os.environ.get('SUPPORT_EMAIL'):
        raise ValueError('Configure real DEVELOPER_NAME and SUPPORT_EMAIL before deployment.')
    if os.environ.get('PRIVACY_REVIEWED') != '1':
        raise ValueError('Finalize the draft privacy notice before setting PRIVACY_REVIEWED=1.')
    os.environ['ALLOWED_HOSTS'] = origin.hostname
    return Path(os.environ.get('DATABASE_PATH', '/data/anubhav.sqlite3'))


class WsgiHandler(Handler):
    def __init__(self, environ, db_path):
        self.directory = str(ROOT / 'build/web')
        self.command = environ['REQUEST_METHOD']
        self.path = environ.get('PATH_INFO', '/')
        self.headers = Message()
        for key, value in environ.items():
            if key.startswith('HTTP_'):
                self.headers[key[5:].replace('_', '-')] = value
        self.headers['Content-Type'] = environ.get('CONTENT_TYPE', '')
        self.headers['Content-Length'] = environ.get('CONTENT_LENGTH', '0') or '0'
        self.rfile = environ['wsgi.input']
        self.wfile = BytesIO()
        self.server = SimpleNamespace(db_path=db_path)
        # The internal app port is reachable only from the configured Caddy proxy.
        self.client_address = (environ.get('HTTP_X_FORWARDED_FOR', environ.get('REMOTE_ADDR', '')).split(',')[-1].strip(), 0)
        self.status = 200
        self.response_headers = []

    def send_response(self, code, message=None):
        self.status = code

    def send_header(self, name, value):
        self.response_headers.append((name, str(value)))

    def end_headers(self):
        self.response_headers.extend([
            ('Cache-Control', 'no-store'), ('X-Content-Type-Options', 'nosniff'),
            ('X-Frame-Options', 'DENY'), ('Referrer-Policy', 'no-referrer'),
            ('Strict-Transport-Security', 'max-age=31536000'),
        ])

    def log_message(self, format, *args):
        pass


_database = None


def application(environ, start_response):
    global _database
    if _database is None:
        _database = validate_config()
        initialize(_database)
    if environ.get('HTTP_X_FORWARDED_PROTO') != 'https':
        start_response('403 Forbidden', [('Content-Type', 'application/json')])
        return [b'{"error":"HTTPS is required."}']
    handler = WsgiHandler(environ, _database)
    try:
        if handler.command == 'GET':
            handler.do_GET()
        elif handler.command in ('POST', 'PUT', 'DELETE'):
            handler.mutate()
        else:
            handler.reply(405, {'error': 'Unsupported method.'})
    except Exception:
        handler.wfile = BytesIO()
        handler.response_headers = []
        handler.reply(500, {'error': 'Could not complete the request. Please try again.'})
    status = f'{handler.status} {HTTPStatus(handler.status).phrase}'
    start_response(status, handler.response_headers)
    return [handler.wfile.getvalue()]
