#!/usr/bin/env bash
# Reset (or create) the admin panel's superadmin account password directly in
# Postgres. Needed because api/auth.py's _ensure_first_user() bootstrap only
# creates the account when none exists yet — setting ADMIN_FIRST_PASS in
# takserver.env again is a silent no-op once the account already exists, so a
# real reset has to write a fresh bcrypt hash straight into admin_users.
# Mirrors EFDI's compose/../scripts/reset_admin_password.sh — same problem,
# same fix, different DB engine (Postgres here, MariaDB there).
reset_admin_password() {  # reset_admin_password <env_file> <username> <password>
    local env_file="$1" username="$2" password="$3"
    local admin_container db_container hash pg_user

    admin_container="$(docker compose --env-file "$env_file" ps -q admin)"
    if [ -z "$admin_container" ]; then
        echo "  Could not find the running admin container to hash the password" >&2
        return 1
    fi
    # Matches api/deps.py's BcryptContext exactly: bcrypt.hashpw(..., bcrypt.gensalt())
    # — no explicit rounds override there, so none here either.
    hash="$(docker exec "$admin_container" python3 -c "
import bcrypt, sys
print(bcrypt.hashpw(sys.argv[1].encode('utf-8'), bcrypt.gensalt()).decode('ascii'))
" "$password" 2>/dev/null)"
    if [ -z "$hash" ]; then
        echo "  Could not hash the new admin password" >&2
        return 1
    fi

    pg_user="$(grep '^POSTGRES_USER=' "$env_file" | head -1 | cut -d= -f2-)"
    pg_user="${pg_user:-martiuser}"
    db_container="$(docker compose --env-file "$env_file" ps -q takdb)"
    if [ -z "$db_container" ]; then
        echo "  Could not find the running takdb container" >&2
        return 1
    fi

    # created_at/is_active/failed_logins/password_changed_at have no DB-level
    # default (only SQLAlchemy's client-side default=... on the ORM's INSERT
    # path) — verified against the real schema, not assumed.
    docker exec "$db_container" psql -U "$pg_user" -d admin -c "
        INSERT INTO admin_users (id, username, password_hash, role, auth_provider, created_by, created_at, is_active, failed_logins, locked_until, password_changed_at)
        VALUES (gen_random_uuid(), '$username', '$hash', 'superadmin', 'local', 'reset', now(), true, 0, NULL, now())
        ON CONFLICT (username) DO UPDATE SET password_hash=EXCLUDED.password_hash, failed_logins=0, locked_until=NULL;
    "
}
