# Project Anubhav

A Flutter classroom activity app with a Python API and SQLite database.

Features include account registration, login/logout, a searchable game library,
class management, activity history, and teacher profiles. New accounts use exactly
six-digit passwords. Each account has its own games, classes and history.

## Run locally

Install Flutter 3.47 or later with Dart 3.13.2 or later, and Python 3 with SQLite support.

```sh
flutter pub get
flutter build web --no-wasm-dry-run
python3 server/app.py
```

Open http://127.0.0.1:8080. Create your account from the login screen; there are no
default credentials. Log out from the Me tab.

The database is created automatically at `server/data/anubhav.sqlite3` and is not
tracked in Git. Existing data is preserved by database migrations; the first account
claims data created before accounts were introduced.

## Validate

```sh
python3 -m unittest discover -s server -p 'test_*.py'
flutter analyze
flutter test
flutter build web --no-wasm-dry-run
```

See [LOCAL_SETUP.md](LOCAL_SETUP.md) for local tooling, database backups, API details
and session behavior.

## Web administration

Open `/admin` for the browser-based management dashboard. Grant access to an
existing account with `python3 server/manage_admin.py your-email@example.com`.
See [server/ADMIN.md](server/ADMIN.md) for setup and access controls.

## Hosting

The app requires its Python API and a persistent SQLite database. GitHub Pages alone
cannot run the backend. The included server is for local development and listens on
127.0.0.1. Remote hosting requires a production server, HTTPS, and Secure session
cookies; see the deployment notes in LOCAL_SETUP.md.
