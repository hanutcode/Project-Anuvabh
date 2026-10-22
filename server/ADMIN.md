# Web administration

Run the existing Python server, then visit `/admin`. The dashboard uses the same
SQLite database as the classroom app. It includes account search, total counts,
recent classroom activity, suspension/restoration, and an access-change audit log.

Register a normal account in the classroom app, then explicitly grant it admin
access from the server console:

```sh
python3 server/manage_admin.py your-email@example.com
```

There are no default admin credentials. Existing users are not automatically
promoted. Use `--database /path/to/anubhav.sqlite3` for a production database.
Add `--revoke` to remove admin access. Administrators cannot be suspended through
the dashboard. Suspension revokes existing sessions and blocks further logins;
restoration requires the user to log in again. Account records are retained.

The dashboard intentionally does not expose passwords, session tokens, or database
downloads. Its API requires an administrator session on every request. Serve the
production application behind HTTPS using the production WSGI entry point.
Child accounts and verified parental consent remain separate, unfinished work.
