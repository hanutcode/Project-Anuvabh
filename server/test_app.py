import json
from pathlib import Path
from http.cookiejar import CookieJar
import sqlite3
from unittest.mock import patch
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen, build_opener, HTTPCookieProcessor
from app import make_server, initialize
import auth


class ApiTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'test.sqlite3'
        self.opener = build_opener(HTTPCookieProcessor(CookieJar()))
        self.start()
        self.request('POST', 'auth/register', dict(name='Teacher', email='teacher@example.test', password='012345'))

    def start(self):
        self.server = make_server(0, self.path)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f'http://127.0.0.1:{self.server.server_port}'

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def tearDown(self):
        self.stop()
        self.temp.cleanup()

    def request(self, method='GET', path='state', data=None, status=200, client=None):
        request = Request(self.base + '/api/' + path, method=method,
                          data=json.dumps(data).encode() if data is not None else None,
                          headers={'Content-Type': 'application/json'})
        try:
            response = (client or self.opener).open(request)
        except HTTPError as error:
            response = error
        with response:
            self.assertEqual(response.status, status)
            return json.load(response)

    def test_crud_history_and_restart(self):
        initial = self.request()
        self.assertEqual(len(initial['games']), 8)
        game = dict(title="Teacher's new game", subject='maths', base='Cards', tone=4290000000,
                    minutes=30, description='Explain, play, reflect.')
        state = self.request('POST', 'games', game)
        game_id = state['games'][-1]['id']
        game['title'] = 'Updated game'
        self.request('PUT', f'games/{game_id}', game)
        state = self.request('POST', 'classes', dict(name='Year 8', students=25))
        class_id = state['classes'][0]['id']
        self.request('PUT', f'classes/{class_id}', dict(name='Year 8B', students=26))
        self.request('PUT', 'settings', dict(teacher_name='Anita', school='Community school', featured_game_id=game_id))
        state = self.request('POST', 'sessions', dict(game_id=game_id, class_id=class_id))
        session_id = state['sessions'][0]['id']
        self.request('PUT', f'sessions/{session_id}')
        self.stop()
        self.start()
        state = self.request()
        self.assertEqual(len(state['games']), 9)
        self.assertEqual(state['settings']['teacher_name'], 'Anita')
        self.assertEqual(state['settings']['featured_game_id'], str(game_id))
        self.assertEqual(state['sessions'][0]['status'], 'completed')
        self.assertTrue(state['sessions'][0]['completed_at'])
        self.request('DELETE', f'games/{game_id}')
        state = self.request('DELETE', f'classes/{class_id}')
        self.assertEqual(state['sessions'][0]['game_title'], 'Updated game')
        self.assertEqual(state['sessions'][0]['class_name'], 'Year 8B')
        self.assertIsNone(state['sessions'][0]['game_id'])
        self.assertIsNone(state['sessions'][0]['class_id'])

    def test_validation_and_rollback(self):
        self.request('POST', 'classes', dict(name='', students=-1), status=400)
        self.request('POST', 'classes', dict(name='Class', students=True), status=400)
        self.request('POST', 'sessions', dict(game_id=99999), status=400)
        self.request('PUT', 'settings', dict(teacher_name='Changed', featured_game_id=99999), status=400)
        self.assertEqual(self.request()['settings']['teacher_name'], 'Teacher')
        self.request('DELETE', 'games/99999', status=404)
        self.request('PUT', 'sessions/99999', status=404)
        self.assertEqual(self.request()['classes'], [])

    def test_deleting_all_games_does_not_reseed(self):
        for game in self.request()['games']:
            self.request('DELETE', f'games/{game["id"]}')
        self.stop()
        self.start()
        self.assertEqual(self.request()['games'], [])

    def test_login_logout_and_cookie_replay(self):
        anonymous = build_opener(HTTPCookieProcessor(CookieJar()))
        self.request(client=anonymous, status=401)
        self.request('POST', 'classes', dict(name='Private', students=20), client=anonymous, status=401)
        self.request('POST', 'auth/login', dict(email='teacher@example.test', password='wrong'), client=anonymous, status=401)
        self.request('POST', 'auth/login', dict(email='unknown@example.test', password='wrong'), client=anonymous, status=401)
        credentials = dict(email='TEACHER@example.test', password='012345')
        state = self.request('POST', 'auth/login', credentials, client=anonymous)
        self.assertEqual(state['user']['email'], 'teacher@example.test')
        jar = next(h.cookiejar for h in anonymous.handlers if isinstance(h, HTTPCookieProcessor))
        session = next(iter(jar))
        self.assertTrue(session.has_nonstandard_attr('HttpOnly'))
        self.assertEqual(session.get_nonstandard_attr('SameSite'), 'Strict')
        token = session.value
        with sqlite3.connect(self.path) as db:
            stored = db.execute('SELECT token_hash FROM auth_sessions WHERE token_hash=?', (auth.token_hash(token),)).fetchone()
            self.assertIsNotNone(stored)
            password_hash = db.execute('SELECT password_hash FROM users').fetchone()[0]
            self.assertNotIn(credentials['password'], password_hash)
            self.assertTrue(auth.verify_password(credentials['password'], password_hash))
        self.request('POST', 'auth/logout', client=anonymous)
        self.request(client=anonymous, status=401)
        replay = Request(self.base + '/api/state', headers={'Cookie': 'anubhav_session=' + token})
        with self.assertRaises(HTTPError) as error:
            urlopen(replay)
        self.assertEqual(error.exception.code, 401)
        error.exception.close()

    def test_account_isolation(self):
        mine = self.request('POST', 'classes', dict(name='Private class', students=20))
        class_id = mine['classes'][0]['id']
        game_id = mine['games'][0]['id']
        mine = self.request('POST', 'sessions', dict(game_id=game_id, class_id=class_id))
        session_id = mine['sessions'][0]['id']
        other = build_opener(HTTPCookieProcessor(CookieJar()))
        theirs = self.request('POST', 'auth/register', dict(name='Other', email='other@example.test', password='654321'), client=other)
        self.assertEqual(theirs['classes'], [])
        self.assertEqual(theirs['sessions'], [])
        self.assertEqual(theirs['settings']['teacher_name'], 'Other')
        self.assertTrue(set(g['id'] for g in mine['games']).isdisjoint(g['id'] for g in theirs['games']))
        self.request('DELETE', f'games/{game_id}', client=other, status=404)
        self.request('PUT', f'classes/{class_id}', dict(name='Hijacked', students=10), client=other, status=404)
        self.request('DELETE', f'classes/{class_id}', client=other, status=404)
        self.request('PUT', f'sessions/{session_id}', client=other, status=404)
        self.request('PUT', 'settings', dict(featured_game_id=game_id), client=other, status=400)
        self.request('POST', 'sessions', dict(game_id=game_id), client=other, status=400)
        self.request('POST', 'sessions', dict(game_id=theirs['games'][0]['id'], class_id=class_id), client=other, status=400)
        self.request('PUT', 'settings', dict(teacher_name='Changed'), client=other)
        self.assertEqual(self.request()['settings']['teacher_name'], 'Teacher')
        self.assertEqual(self.request()['classes'][0]['name'], 'Private class')

    def test_expiry_registration_validation_and_throttling(self):
        anonymous = build_opener(HTTPCookieProcessor(CookieJar()))
        self.request('POST', 'auth/register', dict(name='Short', email='short@example.test', password='short'), client=anonymous, status=400)
        self.request('POST', 'auth/register', dict(name='Duplicate', email='teacher@example.test', password='123456'), client=anonymous, status=400)
        for _ in range(9):
            self.request('POST', 'auth/login', dict(email='throttled@example.test', password='incorrect'), client=anonymous, status=401)
        self.request('POST', 'auth/login', dict(email='throttled@example.test', password='incorrect'), client=anonymous, status=401)
        self.request('POST', 'auth/login', dict(email='throttled@example.test', password='incorrect'), client=anonymous, status=429)
        with sqlite3.connect(self.path) as db:
            db.execute('UPDATE auth_sessions SET expires_at=0')
        self.request(status=401)

    def test_password_requires_exactly_six_ascii_digits(self):
        anonymous = build_opener(HTTPCookieProcessor(CookieJar()))
        for index, password in enumerate(('12345', '1234567', 'abcdef', '12a456', '１２３４５６', ' 12345')):
            result = self.request('POST', 'auth/register', dict(name='Test', email=f'invalid{index}@example.test', password=password), client=anonymous, status=400)
            self.assertEqual(result['error'], 'Password must be exactly 6 digits.')
        # Existing passwords remain usable; password hashes cannot be converted.
        with sqlite3.connect(self.path) as db:
            db.execute('UPDATE users SET password_hash=? WHERE email=?', (auth.hash_password('older-password-123'), 'teacher@example.test'))
        self.request('POST', 'auth/login', dict(email='teacher@example.test', password='older-password-123'), client=anonymous)

    def test_foreign_host_rejected(self):
        request = Request(self.base + '/api/state', headers={'Host': 'untrusted.example'})
        with self.assertRaises(HTTPError) as error:
            urlopen(request)
        self.assertEqual(error.exception.code, 403)
        error.exception.close()

    def test_admin_permissions_suspension_and_restore(self):
        anonymous = build_opener(HTTPCookieProcessor(CookieJar()))
        self.request(path='admin/overview', client=anonymous, status=401)
        self.request(path='admin/overview', status=403)
        with sqlite3.connect(self.path) as db:
            admin_id = db.execute('SELECT id FROM users WHERE email=?', ('teacher@example.test',)).fetchone()[0]
            db.execute('INSERT INTO admin_users VALUES(?)', (admin_id,))
        overview = self.request(path='admin/overview')
        self.assertEqual(overview['counts']['users'], 1)
        self.assertNotIn('password_hash', overview['users'][0])
        other = build_opener(HTTPCookieProcessor(CookieJar()))
        user = self.request('POST', 'auth/register', dict(name='Other', email='other@example.test', password='654321'), client=other)['user']
        self.request('POST', 'admin/user-status', dict(user_id=admin_id, disabled=True), status=400)
        self.request('POST', 'admin/user-status', dict(user_id=user['id'], disabled=True), client=other, status=403)
        self.request('POST', 'admin/user-status', dict(user_id=user['id'], disabled=True))
        self.request(client=other, status=401)
        self.request('POST', 'auth/login', dict(email='other@example.test', password='654321'), client=other, status=403)
        self.request('POST', 'admin/user-status', dict(user_id=user['id'], disabled=False))
        self.request('POST', 'auth/login', dict(email='other@example.test', password='654321'), client=other)
        self.assertEqual(len(self.request(path='admin/overview')['audit']), 2)
        with self.opener.open(self.base + '/admin') as response:
            self.assertIn(b'Administrator login', response.read())

    def test_foreign_origin_rejected(self):
        request = Request(self.base + '/api/classes', method='POST', data=b'{"name":"Class","students":20}',
                          headers={'Origin': 'https://example.com', 'Content-Type': 'application/json'})
        with self.assertRaises(HTTPError) as error:
            urlopen(request)
        self.assertEqual(error.exception.code, 403)
        error.exception.close()


class MigrationTest(unittest.TestCase):
    def test_legacy_data_is_preserved_and_claimed_once(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'legacy.sqlite3'
            with patch('app.auth.migrate'):
                initialize(path)
            with sqlite3.connect(path) as db:
                db.execute("UPDATE settings SET value='Existing Teacher' WHERE key='teacher_name'")
                db.execute("INSERT INTO classes(name,students) VALUES('Existing class',25)")
            server = make_server(0, path)
            server.server_close()
            self.assertTrue(Path(str(path) + '.pre-auth-backup').exists())
            with sqlite3.connect(path) as db:
                self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0], 2)
                user = auth.register(db, dict(name='First', email='first@example.test', password='111111'), Path(__file__).resolve().parent.parent)
                self.assertEqual(db.execute('SELECT user_id FROM classes').fetchone()[0], user['id'])
                self.assertEqual(db.execute("SELECT value FROM account_settings WHERE user_id=? AND key='teacher_name'", (user['id'],)).fetchone()[0], 'Existing Teacher')
                second = auth.register(db, dict(name='Second', email='second@example.test', password='222222'), Path(__file__).resolve().parent.parent)
                self.assertEqual(db.execute('SELECT count(*) FROM classes WHERE user_id=?', (second['id'],)).fetchone()[0], 0)
                self.assertEqual(db.execute('SELECT count(*) FROM games WHERE user_id=?', (second['id'],)).fetchone()[0], 8)


if __name__ == '__main__':
    unittest.main()
