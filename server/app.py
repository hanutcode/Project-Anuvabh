"""Local account-based API and web server. Run: python3 server/app.py."""
import argparse
from contextlib import closing
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import sqlite3
import secrets
import time
import os
from html import escape
import auth
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent


def connect(path):
    db = sqlite3.connect(path, timeout=10)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA foreign_keys = ON')
    db.execute('PRAGMA secure_delete = ON')
    return db


def initialize(path):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with closing(connect(path)) as db, db:
        version = db.execute('PRAGMA user_version').fetchone()[0]
        if version == 0:
            db.executescript('''
                CREATE TABLE games (id INTEGER PRIMARY KEY, title TEXT NOT NULL,
                    subject TEXT NOT NULL CHECK(subject IN ('physics','chemistry','maths')),
                    base TEXT NOT NULL, tone INTEGER NOT NULL, minutes INTEGER NOT NULL CHECK(minutes BETWEEN 1 AND 240),
                    description TEXT NOT NULL);
                CREATE TABLE classes (id INTEGER PRIMARY KEY, name TEXT NOT NULL, students INTEGER NOT NULL CHECK(students BETWEEN 1 AND 500));
                CREATE TABLE sessions (id INTEGER PRIMARY KEY, game_id INTEGER REFERENCES games(id) ON DELETE SET NULL,
                    class_id INTEGER REFERENCES classes(id) ON DELETE SET NULL, game_title TEXT NOT NULL,
                    class_name TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
                    completed_at TEXT, status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','completed')));
                CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE stages (number TEXT PRIMARY KEY, name TEXT NOT NULL, note TEXT NOT NULL);
                CREATE TABLE roles (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
            ''')
            seed = json.loads((ROOT / 'server/seed.json').read_text())
            for g in seed['games']:
                db.execute('INSERT INTO games(title,subject,base,tone,minutes,description) VALUES(:title,:subject,:base,:tone,:minutes,:description)', g)
            db.executemany('INSERT INTO stages VALUES(:number,:name,:note)', seed['stages'])
            db.executemany('INSERT INTO roles(name) VALUES(?)', [(r,) for r in seed['roles']])
            db.executemany('INSERT INTO settings VALUES(?,?)', [('teacher_name', 'Teacher'), ('school', ''), ('featured_game_id', '1')])
            db.execute('PRAGMA user_version = 1')
        auth.migrate(db)
        db.executescript('''
            CREATE TABLE IF NOT EXISTS admin_users (user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE);
            CREATE TABLE IF NOT EXISTS disabled_users (user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE);
            CREATE TABLE IF NOT EXISTS admin_audit (id INTEGER PRIMARY KEY, actor_id INTEGER,
                target_id INTEGER, action TEXT NOT NULL, created_at TEXT DEFAULT CURRENT_TIMESTAMP);
        ''')


def text(data, key, maximum=200, optional=False):
    value = data.get(key, '')
    if not isinstance(value, str) or len(value.strip()) > maximum or (not optional and not value.strip()):
        raise ValueError(f'{key.replace("_", " ").capitalize()} must contain {1 if not optional else 0}–{maximum} characters.')
    return value.strip()


def integer(data, key, low, high):
    value = data.get(key)
    if type(value) is not int or not low <= value <= high:
        raise ValueError(f'{key.capitalize()} must be between {low} and {high}.')
    return value


def snapshot(db, user):
    rows = lambda query: [dict(r) for r in db.execute(query, (user['id'],))]
    return dict(user=user, games=rows('SELECT * FROM games WHERE user_id=? ORDER BY id'),
                classes=rows('SELECT * FROM classes WHERE user_id=? ORDER BY name COLLATE NOCASE'),
                sessions=rows('SELECT * FROM sessions WHERE user_id=? ORDER BY id DESC'),
                stages=[dict(r) for r in db.execute('SELECT * FROM stages ORDER BY number')],
                roles=[r[0] for r in db.execute('SELECT name FROM roles ORDER BY id')],
                settings=dict(db.execute('SELECT key,value FROM account_settings WHERE user_id=?', (user['id'],))))


def legal_content():
    content = json.loads((ROOT / 'server/public/privacy.json').read_text())
    content['developer'] = os.environ.get('DEVELOPER_NAME', '')
    content['support_email'] = os.environ.get('SUPPORT_EMAIL', '')
    content['configured'] = bool(content['developer'] and content['support_email'])
    return content


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT / 'build/web'), **kwargs)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Referrer-Policy', 'no-referrer')
        super().end_headers()

    def reply(self, code, body, session_cookie=None):
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(raw)))
        if session_cookie is not None:
            self.send_header('Set-Cookie', session_cookie)
        self.end_headers()
        self.wfile.write(raw)

    def local_host(self):
        try:
            return urlsplit('http://' + self.headers.get('Host', '')).hostname in os.environ.get('ALLOWED_HOSTS', '127.0.0.1,localhost').split(',')
        except ValueError:
            return False

    def do_GET(self):
        if not self.local_host():
            return self.reply(403, {'error': 'Use the local app address.'})
        path = urlsplit(self.path).path
        if path in ('/admin', '/admin/'):
            raw = (ROOT / 'server/public/admin.html').read_bytes()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        if path == '/api/admin/overview':
            return self.admin_request()
        if path in ('/privacy', '/delete-account'):
            return self.legal_page(path)
        if path == '/api/legal':
            return self.reply(200, legal_content())
        if path == '/health':
            return self.reply(200, {'status': 'ok'})
        if path == '/api/state':
            with closing(connect(self.server.db_path)) as db:
                user = auth.current_user(db, self.headers)
                if not user:
                    return self.reply(401, {'error': 'Please log in to continue.'})
                return self.reply(200, snapshot(db, user))
        if urlsplit(self.path).path.startswith('/api/'):
            return self.reply(404, {'error': 'Endpoint not found.'})
        return super().do_GET()

    def mutate(self):
        if not self.local_host():
            return self.reply(403, {'error': 'Use the local app address.'})
        # Browser requests are same-origin. Reject foreign form/script submissions.
        origin = self.headers.get('Origin')
        if origin and origin != os.environ.get('PUBLIC_ORIGIN', 'http://' + self.headers.get('Host', '')):
            return self.reply(403, {'error': 'Use the app from this server.'})
        if self.headers.get('Content-Type', '').split(';')[0].strip() != 'application/json':
            return self.reply(415, {'error': 'Send JSON from the app.'})
        if urlsplit(self.path).path.startswith('/api/admin/'):
            return self.admin_request()
        if urlsplit(self.path).path.startswith('/api/auth/'):
            return self.authenticate()
        try:
            length = int(self.headers.get('Content-Length', 0))
            if length < 0 or length > 65536:
                return self.reply(413, {'error': 'Request too large.'})
            data = json.loads(self.rfile.read(length) or b'{}')
            if not isinstance(data, dict):
                raise ValueError('Expected a JSON object.')
            parts = urlsplit(self.path).path.strip('/').split('/')
            if len(parts) not in (2, 3) or parts[0] != 'api':
                return self.reply(404, {'error': 'Endpoint not found.'})
            resource = parts[1]
            item_id = int(parts[2]) if len(parts) == 3 else None
            with closing(connect(self.server.db_path)) as db, db:
                user = auth.current_user(db, self.headers)
                if not user:
                    return self.reply(401, {'error': 'Your session ended. Please log in again.'})
                user_id = user['id']
                if resource in ('games', 'classes'):
                    if self.command == 'POST' and item_id is not None or self.command != 'POST' and item_id is None:
                        return self.reply(405, {'error': 'Unsupported operation.'})
                    if item_id is not None and not db.execute(f'SELECT id FROM {resource} WHERE id=? AND user_id=?', (item_id, user_id)).fetchone():
                        return self.reply(404, {'error': 'Item no longer exists.'})
                    if self.command == 'DELETE':
                        db.execute(f'DELETE FROM {resource} WHERE id=? AND user_id=?', (item_id, user_id))
                    else:
                        if resource == 'games':
                            subject = text(data, 'subject')
                            if subject not in ('physics', 'chemistry', 'maths'):
                                raise ValueError('Choose a supported subject.')
                            fields = dict(title=text(data, 'title', 100), subject=subject, base=text(data, 'base', 80),
                                          tone=integer(data, 'tone', 0, 4294967295), minutes=integer(data, 'minutes', 1, 240),
                                          description=text(data, 'description', 3000))
                        else:
                            fields = dict(name=text(data, 'name', 80), students=integer(data, 'students', 1, 500))
                        fields['user_id'] = user_id
                        if item_id is None:
                            db.execute(f'INSERT INTO {resource} ({",".join(fields)}) VALUES ({",".join("?" for _ in fields)})', tuple(fields.values()))
                        else:
                            db.execute(f'UPDATE {resource} SET {",".join(k+"=?" for k in fields)} WHERE id=? AND user_id=?', (*fields.values(), item_id, user_id))
                elif resource == 'settings' and self.command == 'PUT' and item_id is None:
                    for key in ('teacher_name', 'school'):
                        if key in data:
                            value = text(data, key, 100, optional=key == 'school')
                            db.execute('UPDATE account_settings SET value=? WHERE key=? AND user_id=?', (value, key, user_id))
                    if 'featured_game_id' in data:
                        game_id = integer(data, 'featured_game_id', 1, 2147483647)
                        if not db.execute('SELECT id FROM games WHERE id=? AND user_id=?', (game_id, user_id)).fetchone():
                            raise ValueError('Game no longer exists.')
                        db.execute("UPDATE account_settings SET value=? WHERE key='featured_game_id' AND user_id=?", (str(game_id), user_id))
                elif resource == 'sessions' and self.command == 'POST' and item_id is None:
                    game_id = integer(data, 'game_id', 1, 2147483647)
                    game = db.execute('SELECT title FROM games WHERE id=? AND user_id=?', (game_id, user_id)).fetchone()
                    class_id = data.get('class_id')
                    classroom = None
                    if class_id is not None:
                        integer(data, 'class_id', 1, 2147483647)
                        classroom = db.execute('SELECT name FROM classes WHERE id=? AND user_id=?', (class_id, user_id)).fetchone()
                        if not classroom:
                            raise ValueError('Class no longer exists.')
                    if not game:
                        raise ValueError('Game no longer exists.')
                    db.execute('INSERT INTO sessions(game_id,class_id,game_title,class_name,user_id) VALUES(?,?,?,?,?)',
                               (game_id, class_id, game[0], classroom[0] if classroom else 'Independent activity', user_id))
                elif resource == 'sessions' and self.command == 'PUT' and item_id is not None:
                    if not db.execute('SELECT id FROM sessions WHERE id=? AND user_id=?', (item_id, user_id)).fetchone():
                        return self.reply(404, {'error': 'Activity no longer exists.'})
                    db.execute("UPDATE sessions SET status='completed',completed_at=COALESCE(completed_at,strftime('%Y-%m-%dT%H:%M:%fZ','now')) WHERE id=? AND user_id=?", (item_id, user_id))
                else:
                    return self.reply(405, {'error': 'Unsupported operation.'})
                result = snapshot(db, user)
            self.reply(200, result)
        except (ValueError, TypeError, json.JSONDecodeError) as error:
            self.reply(400, {'error': str(error)})
        except sqlite3.Error:
            self.reply(500, {'error': 'Could not save changes. Please try again.'})

    def admin_request(self):
        try:
            with closing(connect(self.server.db_path)) as db, db:
                user = auth.current_user(db, self.headers)
                if not user:
                    return self.reply(401, {'error': 'Please log in.'})
                if not db.execute('SELECT 1 FROM admin_users WHERE user_id=?', (user['id'],)).fetchone():
                    return self.reply(403, {'error': 'Administrator access is required.'})
                path = urlsplit(self.path).path
                if self.command == 'POST' and path == '/api/admin/user-status':
                    length = int(self.headers.get('Content-Length', 0))
                    if not 0 < length <= 4096:
                        return self.reply(413, {'error': 'Invalid request size.'})
                    data = json.loads(self.rfile.read(length))
                    if not isinstance(data, dict) or type(data.get('user_id')) is not int or type(data.get('disabled')) is not bool:
                        raise ValueError('Provide a user ID and disabled boolean.')
                    target = data['user_id']
                    if not db.execute('SELECT 1 FROM users WHERE id=?', (target,)).fetchone():
                        return self.reply(404, {'error': 'Account not found.'})
                    if db.execute('SELECT 1 FROM admin_users WHERE user_id=?', (target,)).fetchone():
                        raise ValueError('Administrator accounts cannot be suspended here.')
                    if data['disabled']:
                        db.execute('INSERT OR IGNORE INTO disabled_users VALUES(?)', (target,))
                        db.execute('DELETE FROM auth_sessions WHERE user_id=?', (target,))
                    else:
                        db.execute('DELETE FROM disabled_users WHERE user_id=?', (target,))
                    db.execute('INSERT INTO admin_audit(actor_id,target_id,action) VALUES(?,?,?)',
                               (user['id'], target, 'suspend' if data['disabled'] else 'restore'))
                    return self.reply(200, {'ok': True})
                if self.command != 'GET' or path != '/api/admin/overview':
                    return self.reply(404, {'error': 'Admin endpoint not found.'})
                counts = {table: db.execute(f'SELECT count(*) FROM {table}').fetchone()[0]
                          for table in ('users', 'games', 'classes', 'sessions')}
                users = [dict(r) for r in db.execute('''SELECT u.id,u.email,
                    COALESCE((SELECT value FROM account_settings WHERE user_id=u.id AND key='teacher_name'),'') AS name,
                    EXISTS(SELECT 1 FROM admin_users WHERE user_id=u.id) AS admin,
                    EXISTS(SELECT 1 FROM disabled_users WHERE user_id=u.id) AS disabled
                    FROM users u ORDER BY u.id DESC LIMIT 500''')]
                activity = [dict(r) for r in db.execute('''SELECT id,user_id,game_title,class_name,status,created_at
                    FROM sessions ORDER BY id DESC LIMIT 50''')]
                audit = [dict(r) for r in db.execute('SELECT * FROM admin_audit ORDER BY id DESC LIMIT 50')]
                return self.reply(200, {'user': user, 'counts': counts, 'users': users, 'activity': activity, 'audit': audit})
        except (ValueError, TypeError, json.JSONDecodeError):
            self.reply(400, {'error': 'Invalid admin request.'})
        except sqlite3.Error:
            self.reply(500, {'error': 'Could not complete the admin request.'})

    def authenticate(self):
        if self.command != 'POST':
            return self.reply(405, {'error': 'Unsupported operation.'})
        try:
            length = int(self.headers.get('Content-Length', 0))
            if not 0 <= length <= 8192:
                return self.reply(413, {'error': 'Request too large.'})
            data = json.loads(self.rfile.read(length) or b'{}')
            if not isinstance(data, dict):
                raise ValueError('Expected a JSON object.')
            action = urlsplit(self.path).path.rsplit('/', 1)[-1]
            with closing(connect(self.server.db_path)) as db, db:
                if action == 'logout':
                    db.execute('DELETE FROM auth_sessions WHERE token_hash=?', (auth.token_hash(auth.session_token(self.headers)),))
                    result, session_cookie = {'ok': True}, auth.cookie(expire=True)
                elif action == 'delete-account':
                    user = auth.current_user(db, self.headers)
                    if not user:
                        return self.reply(401, {'error': 'Please log in before deleting your account.'})
                    password = data.get('password', '')
                    if not isinstance(password, str) or len(password) > 128:
                        raise ValueError('Enter your current password.')
                    now = int(time.time())
                    db.execute('DELETE FROM auth_attempts WHERE attempted_at<?', (now - 900,))
                    attempts = db.execute('SELECT count(*) FROM auth_attempts WHERE email=?', (user['email'],)).fetchone()[0]
                    if attempts >= 10:
                        return self.reply(429, {'error': 'Too many attempts. Please try again in 15 minutes.'})
                    db.execute('INSERT INTO auth_attempts VALUES(?,?,?)', (self.client_address[0], user['email'], now))
                    db.commit()
                    db.execute('BEGIN IMMEDIATE')
                    row = db.execute('SELECT password_hash FROM users WHERE id=?', (user['id'],)).fetchone()
                    if not row or not auth.verify_password(password, row['password_hash']):
                        return self.reply(400, {'error': 'Password is incorrect. Your account has not been deleted.'})
                    if data.get('confirmation') != 'DELETE':
                        raise ValueError('Confirm account deletion by typing DELETE.')
                    auth.delete_account(db, user['id'], self.server.db_path)
                    result, session_cookie = {'ok': True}, auth.cookie(expire=True)
                elif action in ('register', 'login'):
                    email, password = auth.credentials(data)
                    now = int(time.time())
                    db.execute('DELETE FROM auth_attempts WHERE attempted_at<?', (now - 900,))
                    count = db.execute('SELECT count(*) FROM auth_attempts WHERE email=?', (email,)).fetchone()[0]
                    ip_count = db.execute('SELECT count(*) FROM auth_attempts WHERE ip=?', (self.client_address[0],)).fetchone()[0]
                    if count >= 10 or ip_count >= 30:
                        return self.reply(429, {'error': 'Too many attempts. Please try again in 15 minutes.'})
                    db.execute('INSERT INTO auth_attempts VALUES(?,?,?)', (self.client_address[0], email, now))
                    # Commit attempts even if credentials are rejected.
                    db.commit()
                    db.execute('BEGIN IMMEDIATE')
                    if action == 'register':
                        user = auth.register(db, data, ROOT)
                    else:
                        row = db.execute('SELECT * FROM users WHERE email=?', (email,)).fetchone()
                        valid = auth.verify_password(password, row['password_hash'] if row else auth.DUMMY_HASH)
                        if not row or not valid:
                            return self.reply(401, {'error': 'Email or password is incorrect.'})
                        user = {'id': row['id'], 'email': row['email']}
                        if db.execute('SELECT 1 FROM disabled_users WHERE user_id=?', (user['id'],)).fetchone():
                            return self.reply(403, {'error': 'This account is suspended. Contact the administrator.'})
                    db.execute('DELETE FROM auth_sessions WHERE expires_at<=?', (now,))
                    old_token = auth.session_token(self.headers)
                    if old_token:
                        db.execute('DELETE FROM auth_sessions WHERE token_hash=?', (auth.token_hash(old_token),))
                    token = secrets.token_urlsafe(32)
                    db.execute('INSERT INTO auth_sessions VALUES(?,?,?)', (auth.token_hash(token), user['id'], now + auth.SESSION_SECONDS))
                    result, session_cookie = snapshot(db, user), auth.cookie(token)
                    if self.headers.get('X-App-Client') == 'native':
                        result['session_token'] = token
                else:
                    return self.reply(404, {'error': 'Endpoint not found.'})
            self.reply(200, result, session_cookie)
        except (ValueError, TypeError) as error:
            self.reply(400, {'error': str(error)})
        except sqlite3.IntegrityError:
            self.reply(400, {'error': 'Could not create this account. Try a different email.'})
        except sqlite3.Error:
            self.reply(500, {'error': 'Could not sign in. Please try again.'})

    def legal_page(self, path):
        content = legal_content()
        template = (ROOT / 'server/public/legal.html').read_text()
        raw = template.replace('{{LEGAL_JSON}}', json.dumps(content).replace('<', '\u003c')).replace('{{PAGE}}', 'deletion' if path == '/delete-account' else 'privacy').encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def list_directory(self, path):
        self.send_error(404)
        return None

    do_POST = mutate
    do_PUT = mutate
    do_DELETE = mutate


def make_server(port=8080, db_path=None):
    if os.environ.get('APP_ENV') == 'production':
        raise ValueError('Use the production WSGI entrypoint behind HTTPS, not the development server.')
    path = db_path or ROOT / 'server/data/anubhav.sqlite3'
    if Path(path).exists():
        with closing(connect(path)) as source:
            if source.execute('PRAGMA user_version').fetchone()[0] == 1:
                backup_path = Path(str(path) + '.pre-auth-backup')
                if not backup_path.exists():
                    with closing(sqlite3.connect(backup_path)) as target:
                        source.backup(target)
    initialize(path)
    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.db_path = path
    return server


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8080)
    args = parser.parse_args()
    with make_server(args.port) as server:
        print(f'Project Anubhav: http://127.0.0.1:{args.port}', flush=True)
        server.serve_forever()
