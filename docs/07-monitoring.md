# 07 — Monitoring

## Admin panel Dashboard

Real-time service status (5s poll): CPU/RAM/disk/uptime/load/network, each service shown with a status indicator and time of last observation ("as of Xs ago"). The overall judgment (NOMINAL/INCOMPLETE) is computed from real data — NOMINAL when every service is running and disk isn't critical, otherwise it names the specific service/signal that needs attention.

## `health.sh`

```bash
./health.sh
```

Self-heal + self-test for a running deployment against the currently checked-out commit:

- **Self-heal:** checks whether each running image's baked-in git-commit label matches HEAD. A mismatch means Docker's layer cache silently reused a stale layer — automatically forces a `--no-cache` rebuild.
- **Self-test:** verifies the package builder actually produces the right zip layout for each client type, not just that the image was built from the right commit.

Safe to run any time — it doesn't `git pull`/`fetch` (that's `update.sh`'s job). `update.sh` calls `health.sh` automatically if its own quick self-test fails after a normal build.

## Audit

The admin panel writes audit entries (logins, user management, config changes) — visible to the `superadmin` role under Audit Logs.

## Notifications

In-app toast notifications in the admin panel for success/failure of operations. There is **no** external notification channel (Slack, email, webhook) — if you need one, it would need to be built; it doesn't exist today.

## Logs

```bash
make logs       # all services, follow mode
make logs-db    # takdb only
```

Admin panel: Logs (superadmin, filterable by service).
