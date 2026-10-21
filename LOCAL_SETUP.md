# Project Anubhav — local SQLite app

The Flutter UI reads and writes data through the Python API. Both the web app and
API are served from http://127.0.0.1:8080. Python's standard library provides SQLite;
there are no backend packages to install.

## Start the app

```sh
./scripts/flutter pub get
./scripts/flutter build web --no-wasm-dry-run
python3 server/app.py
```

Open http://127.0.0.1:8080. Stop the server with Ctrl+C. To preview UI changes,
rebuild the web app and refresh the browser. Keep the Python server running.
Do not use a static-only HTTP server: the UI requires `/api/state` and the write APIs.

The project-local Flutter 3.47.7 SDK lives in `.local/flutter`. `scripts/flutter`
selects it and stores downloaded packages in `.local/pub-cache`.

## Data

- Database: `server/data/anubhav.sqlite3` (created automatically on first start).
- Schema version: 2 via SQLite `PRAGMA user_version`; initial schema is in `server/app.py` and the account migration is in `server/auth.py`.
- Starter content: `server/seed.json`, inserted once, during database creation.
- Games: add, edit, delete, search, filter by subject, choose today's featured game.
- Classes: add, edit, delete, store student counts.
- Activities: start independently or for a class, mark completed, retain history.
- Profile: save teacher name and school; the home greeting uses the saved name.
- Dashboard statistics are derived from stored games, subjects and completed activities.
- Lesson stages and classroom roles are loaded from SQLite.

Database files and local tools are ignored by Git. To back up your data, stop the
server and copy `server/data/anubhav.sqlite3`. Retain this file across app updates.
Deleting all games intentionally leaves an empty library; restarting does not reseed it.
Deleting games or classes preserves activity titles and class names in history.

## Accounts and sessions

Open the app and select **New here? Create an account**. Enter your name, email and
a password containing exactly six digits (0–9). Registration signs you in immediately. Returning
users log in with their email and password. Existing accounts with older passwords can still log in; passwords are never silently reset. Log out from the **Me** tab.
There are no default accounts or passwords. Email is used as a local login identifier;
email verification and password recovery are not implemented.

On the first start after this update, the server backs up the version 1 database to
`server/data/anubhav.sqlite3.pre-auth-backup` before migrating it. The first account
created inherits the existing games, classes, activity history and profile. Additional
accounts receive independent starter libraries; all private reads and writes are
scoped to the signed-in account. Lesson stages and roles remain shared reference data.

Passwords use PBKDF2-HMAC-SHA256 with a random salt and 600,000 iterations. Session
cookies are HttpOnly, SameSite=Strict, expire after seven days, and contain random
tokens; only token hashes are stored in SQLite. Logout revokes the current session.
The UI clears account data on logout or an unauthorized API response. Login and
registration are throttled to 10 attempts per email or 30 per client IP in 15 minutes.
Sessions survive app server restarts until they expire or are revoked.

This setup is a local account-based app. The server binds only to 127.0.0.1.
For remote deployment, use HTTPS, set the session cookie's Secure attribute and
replace the development HTTP server with a production server. Mobile builds have not been configured or tested with this API. For a
future mobile deployment, the API URL is configurable using Flutter's
`--dart-define=API_BASE_URL=...`; hosting and native networking configuration are
separate work.

## Checks

```sh
python3 -m unittest discover -s server -p 'test_*.py'
./scripts/flutter analyze
./scripts/flutter test
./scripts/flutter build web --no-wasm-dry-run
```

Backend tests use disposable databases and cover login/logout, cookie revocation and expiry, account isolation, migration preservation, rate limiting, CRUD, validation, transaction
rollback, history retention, persistence across server restart and cross-origin
write rejection. Flutter tests cover API loading, derived counts, filtering,
failed-save handling and class form validation/save.

## API

- `POST /api/auth/register`: name, email, password; creates an account and session.
- `POST /api/auth/login`: email, password; creates a fresh session.
- `POST /api/auth/logout`: revokes the current session and clears its cookie.
- `GET /api/state`: authenticated user, games, classes, sessions, settings, stages, roles.
- `POST /api/games`, `PUT /api/games/{id}`, `DELETE /api/games/{id}`.
- `POST /api/classes`, `PUT /api/classes/{id}`, `DELETE /api/classes/{id}`.
- `PUT /api/settings`: teacher_name, school and/or featured_game_id.
- `POST /api/sessions`: game_id and optional class_id.
- `PUT /api/sessions/{id}`: mark activity completed.

All data endpoints require a valid session cookie. Writes use JSON and return the refreshed app state (logout returns an acknowledgement). Invalid input returns a JSON
error without saving partial changes.
