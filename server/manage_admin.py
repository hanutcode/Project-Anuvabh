"""Grant or revoke admin access to an existing account from the server console."""
import argparse
from contextlib import closing
from pathlib import Path
from app import ROOT, connect, initialize

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('email')
    parser.add_argument('--database', type=Path, default=ROOT / 'server/data/anubhav.sqlite3')
    parser.add_argument('--revoke', action='store_true')
    args = parser.parse_args()
    initialize(args.database)
    with closing(connect(args.database)) as db, db:
        row = db.execute('SELECT id FROM users WHERE email=?', (args.email.strip().lower(),)).fetchone()
        if not row:
            parser.error('Register this account in the app first.')
        if args.revoke:
            db.execute('DELETE FROM admin_users WHERE user_id=?', (row['id'],))
        else:
            db.execute('INSERT OR IGNORE INTO admin_users VALUES(?)', (row['id'],))
            db.execute('DELETE FROM disabled_users WHERE user_id=?', (row['id'],))
        db.execute('INSERT INTO admin_audit(actor_id,target_id,action) VALUES(NULL,?,?)',
                   (row['id'], 'console_revoke' if args.revoke else 'console_grant'))
    print('Administrator access revoked.' if args.revoke else 'Administrator access granted.')
