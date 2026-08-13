# 10 — Updates

```bash
make update
# or directly:
./update.sh
```

## What happens

1. **Pull** — `git fetch` + `git merge --ff-only` on the current branch. If `update.sh` itself changed, the script re-execs itself fresh (rather than continuing on a now-stale buffer).
2. **Env backfill** — checks `takserver.env` for missing variables and appends defaults for any that are missing.
3. **Rebuild** — images are rebuilt with the new `GIT_COMMIT` label.
4. **`admin_proxy` restart** — forced, so nginx always resolves the `admin` container's current IP (otherwise it would keep 502ing against the old, now-dead container until its own next restart).
5. **Self-test → self-heal** — a quick functional check right after the build. If it fails, `health.sh` is called automatically (forces a `--no-cache` rebuild). Only if that also fails does the script stop with an error.

## Before updating

- Take a backup (see [08-backups.md](08-backups.md)), especially on a production deployment.
- Make sure the repo isn't in a `detached HEAD` state (`update.sh` checks this and stops with instructions to `git checkout main`).
- Fast-forward-only: if there are incompatible local changes, `update.sh` stops without merging — resolve manually before retrying.

## After updating

```bash
docker compose --env-file takserver.env logs -f
```

Confirm every service is up (`make status`) and the admin panel is reachable.
