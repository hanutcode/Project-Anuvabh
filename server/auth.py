"""Password hashing, session cookies and the account migration."""
import hashlib
import hmac
from http.cookies import SimpleCookie, CookieError
import json
import re
import secrets
import time
import os
from pathlib import Path

ITERATIONS = 600_000
SESSION_SECONDS = 7 * 24 * 60 * 60


def hash_password(password, salt=None):
    salt = salt or secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), ITERATIONS).hex()
    return f'pbkdf2_sha256${ITERATIONS}${salt}${digest}'


DUMMY_HASH = hash_password(secrets.token_urlsafe(32))


def verify_password(password, encoded):
    _, iterations, salt, expected = encoded.split('$')
    actual = hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), int(iterations)).hex()
    return hmac.compare_digest(actual, expected)


def token_hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


def cookie_token(headers):
    try:
        cookies = SimpleCookie()
        cookies.load(headers.get('Cookie', ''))
        return cookies['anubhav_session'].value if 'anubhav_session' in cookies else ''
    except CookieError:
        return ''


def current_user(db, headers):
    token = session_token(headers)
    if not token or len(token) > 200:
        return None
    row = db.execute('''SELECT users.id,users.email FROM auth_sessions
        JOIN users ON users.id=auth_sessions.user_id
        WHERE token_hash=? AND expires_at>?''', (token_hash(token), int(time.time()))).fetchone()
    return dict(row) if row else None


def cookie(token='', expire=False):
    return f'anubhav_session={token}; Path=/api; HttpOnly; SameSite=Strict; Max-Age={0 if expire else SESSION_SECONDS}' + ('; Secure' if os.environ.get('APP_ENV') == 'production' else '')


def migrate(db):
    if db.execute('PRAGMA user_version').fetchone()[0] >= 2:
        return
    db.execute('CREATE TABLE users(id INTEGER PRIMARY KEY, email TEXT NOT NULL UNIQUE COLLATE NOCASE, password_hash TEXT NOT NULL)')
    db.execute('CREATE TABLE auth_sessions(token_hash TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, expires_at INTEGER NOT NULL)')
    db.execute('CREATE INDEX auth_sessions_user ON auth_sessions(user_id)')
    db.execute('CREATE TABLE auth_attempts(ip TEXT NOT NULL, email TEXT NOT NULL, attempted_at INTEGER NOT NULL)')
    db.execute('CREATE INDEX auth_attempts_time ON auth_attempts(attempted_at)')
    for table in ('games', 'classes', 'sessions'):
        db.execute(f'ALTER TABLE {table} ADD COLUMN user_id INTEGER REFERENCES users(id)')
        db.execute(f'CREATE INDEX {table}_user ON {table}(user_id)')
    db.execute('CREATE TABLE account_settings(user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE, key TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(user_id,key))')
    db.execute('PRAGMA user_version = 2')


def register(db, data, root):
    name = data.get('name', '')
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 100:
        raise ValueError('Enter your name (up to 100 characters).')
    email, password = credentials(data)
    if not re.fullmatch(r'[0-9]{6}', password):
        raise ValueError('Password must be exactly 6 digits.')
    if db.execute('SELECT id FROM users WHERE email=?', (email,)).fetchone():
        raise ValueError('An account already uses this email. Please log in.')
    first = db.execute('SELECT count(*) FROM users').fetchone()[0] == 0 and not db.execute("SELECT 1 FROM settings WHERE key='__legacy_claimed'").fetchone()
    user_id = db.execute('INSERT INTO users(email,password_hash) VALUES(?,?)', (email, hash_password(password))).lastrowid
    if first:
        for table in ('games', 'classes', 'sessions'):
            db.execute(f'UPDATE {table} SET user_id=? WHERE user_id IS NULL', (user_id,))
        db.execute("INSERT INTO account_settings SELECT ?,key,value FROM settings WHERE key NOT LIKE '__legacy_%'", (user_id,))
        db.execute('DELETE FROM settings')
        db.execute("INSERT INTO settings VALUES('__legacy_claimed',?)", (str(user_id),))
    else:
        seed = json.loads((Path(root) / 'server/seed.json').read_text())
        featured = ''
        for game in seed['games']:
            row = db.execute('INSERT INTO games(title,subject,base,tone,minutes,description,user_id) VALUES(:title,:subject,:base,:tone,:minutes,:description,:user_id)', {**game, 'user_id': user_id})
            featured = featured or str(row.lastrowid)
        db.executemany('INSERT INTO account_settings VALUES(?,?,?)', [(user_id, 'teacher_name', name.strip()), (user_id, 'school', ''), (user_id, 'featured_game_id', featured)])
    # Keep a customized legacy name on the first account; replace the placeholder.
    db.execute("UPDATE account_settings SET value=? WHERE user_id=? AND key='teacher_name' AND value='Teacher'", (name.strip(), user_id))
    return {'id': user_id, 'email': email}


def credentials(data):
    email, password = data.get('email', ''), data.get('password', '')
    if not isinstance(email, str) or len(email) > 254 or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email.strip()):
        raise ValueError('Enter a valid email address.')
    if not isinstance(password, str) or not 1 <= len(password) <= 128:
        raise ValueError('Enter a password of up to 128 characters.')
    return email.strip().lower(), password


def session_token(headers):
    authorization = headers.get('Authorization', '')
    return authorization[7:] if authorization.startswith('Bearer ') else cookie_token(headers)


def delete_account(db, user_id, db_path):
    user = db.execute('SELECT email FROM users WHERE id=?', (user_id,)).fetchone()
    if not user:
        raise ValueError('Account no longer exists.')
    for table in ('sessions', 'classes', 'games', 'account_settings', 'auth_sessions'):
        db.execute(f'DELETE FROM {table} WHERE user_id=?', (user_id,))
    db.execute('DELETE FROM auth_attempts WHERE email=?', (user['email'],))
    claimed = db.execute("SELECT value FROM settings WHERE key='__legacy_claimed'").fetchone()
    # Legacy database/profile copies belong to the first account. Remove them
    # on deletion, without touching another account's active records.
    first_id = db.execute('SELECT min(id) FROM users').fetchone()[0]
    if (claimed and claimed[0] == str(user_id)) or (not claimed and first_id == user_id):
        Path(str(db_path) + '.pre-auth-backup').unlink(missing_ok=True)
        db.execute('DELETE FROM settings')
        db.execute("INSERT INTO settings VALUES('__legacy_claimed','deleted')")
    db.execute('DELETE FROM users WHERE id=?', (user_id,))
