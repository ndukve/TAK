# Field User Package Access — Design

## Purpose

`scripts/serve_packages.py` (port 8888) currently serves TAK client data
packages — including client certificates and private keys — with no
authentication beyond an optional shared Basic Auth password. Anyone who
knows or guesses a callsign can download that user's cert bundle and
impersonate their device on the TAK server. This design retires that public
server and replaces it with per-user, authenticated, per-user-scoped access
through the existing admin panel, so a field user can log in from their own
phone and download only their own package(s) — never anyone else's.

## Non-goals

- No change to how TAK device packages are *generated* (cert content,
  `-ATAK`/`-WinTAK`/`-iTAK` suffix branching, `make_pkg_zip.sh` internals).
- No change to existing `superadmin`/`admin`/`readonly` admin-panel behavior
  — they keep seeing everything they see today.
- No full mobile-responsive redesign of the entire admin panel — only the
  screens a `field` account actually sees (login, Packages, Maps).
- No mechanism for the CLI (`generate_user.sh`) to auto-create a field login
  — that path is web-UI-only, per the scoping conversation. CLI-generated
  packages remain fully functional as-is; they just don't get an
  automatically-created panel login. A manual "Create field login" action
  in the panel covers that case when needed.

## Architecture

**New role: `field`.** `admin_users.role` already stores a free-text string
(`superadmin`/`admin`/`readonly` today); `field` becomes a fourth accepted
value everywhere role is checked. A new nullable column,
`admin_users.owned_callsign`, stores the *base* callsign (suffix stripped —
e.g. `"Alpha1"`, not `"Alpha1-iTAK"`) for `field` accounts only; it stays
`NULL` for every other role.

**One account per person, not per package.** A `field` account's
`owned_callsign` is the base name shared across all of that person's
device packages. Generating `Alpha1-iTAK` creates (or, if one already
exists for `"Alpha1"`, reuses) the field account. Generating `Alpha1-ATAK`
later reuses the same account — the person accumulates access to more of
their own packages without a new login being created each time.

**Server-side filtering, not just UI hiding.** `admin/api/packages.py`
already serves three resource types under one router: TAK packages
(`clientpkgs/*.zip`), plugins, and maps. Its existing listing/download
endpoints for TAK packages get `field` added to their allowed roles, with a
filter applied whenever the caller's role is `field`: only files whose name
starts with `{owned_callsign}-` are visible or downloadable. This must be
enforced in the **download** endpoint itself (checking the authenticated
caller's `owned_callsign` against the requested filename), not only in the
listing endpoint — otherwise a field user could bypass the filtered list by
requesting another user's filename directly. Maps endpoints allow `field`
unfiltered (shared reference data, not personal). Plugins stay
admin/superadmin-only; `field` accounts have no reason to see them.

**Port 8888 is retired entirely.** The `pkg_server` compose service and
`scripts/serve_packages.py` are removed. Packages, plugins, and maps are
now only reachable through the admin panel (`admin_proxy`, TLS, already
auth-gated) — one consistent access story instead of two. This is a
breaking change for any existing bookmark/QR-code pointed at
`http://<server>:8888/<name>.zip`; that's an accepted tradeoff given the
security motivation.

**Break-glass CLI fallback.** If the admin panel container is down for some
reason, packages still need to be retrievable. A new root-level script,
`get_package.sh <name>`, copies a package zip (or, given no name, lists
what's available) out of the `takserver_config` container onto the host
filesystem the script is run from — the same trust model as
`purge_user.sh` or `generate_user.sh` today: it requires SSH/shell access to
the server itself, not network reachability, so it doesn't reintroduce the
"anyone on the network can pull anyone's cert" problem port 8888 had. An
admin with server access uses it to retrieve a package and relay it to the
field user through whatever out-of-band channel makes sense (this is not a
network service — no port, no listener, nothing for an unauthenticated
party to reach).

## Data flow — account creation

1. Superadmin/admin generates `Alpha1-iTAK`'s package via the web UI
   (`admin/api/users.py`'s `make_package` endpoint, which has direct DB
   access).
2. The endpoint derives the base name (`Alpha1`) by stripping the
   `-ATAK`/`-WinTAK`/`-iTAK` suffix, then checks whether an `admin_users`
   row with `role='field' AND owned_callsign='Alpha1'` already exists.
   - **If not:** creates one with a randomly generated password, and
     includes that password **once** in the API response, surfaced in the
     admin UI's success screen — same "shown once, never again" pattern
     already used for the install-time admin password.
   - **If it exists:** does nothing further; the response instead notes
     "Existing field login: Alpha1" so the operator knows no new password
     was generated (and doesn't need one — the person already has access).
3. Operator hands the shown-once password to the field user out of band
   (same as any other credential in this system).

## Data flow — field user session

1. Field user logs in at the same URL/form as any admin account
   (`/auth/login`, unchanged) with their `owned_callsign` as username.
2. Frontend nav (`Layout.tsx`) renders only **Packages** and **Maps** for
   `role === 'field'` — Dashboard, Users, Plugins, Logs, Shell, and Admin
   Users are hidden. This is a UX convenience only; the real enforcement is
   server-side (point 3).
3. Packages page calls the existing listing endpoint; the backend returns
   only `Alpha1-*` entries. Download links point at the existing download
   endpoint, which independently re-checks `owned_callsign` against the
   requested filename before serving bytes.
4. If a field-role token is used to call any admin/superadmin-only endpoint
   (Users, Plugins management, Logs, Shell, Admin Users) directly — not
   through the UI — the existing `require_role(...)` dependency rejects it
   with 403, same mechanism already protecting `readonly` from
   admin-only actions today.

## Admin Users tab and password reset

`field` accounts live in the same `admin_users` table as real operator
accounts, so they'll appear in the existing **Admin Users** management tab
unless that view is adjusted. Given a deployment could plausibly have many
field accounts (one per person with a device) mixed in with a handful of
real operators, the Admin Users list gets a role filter (defaulting to
hiding `field` rows, with a toggle to show them) so it doesn't get
overwhelmed. Password reset needs no new mechanism — it's the same
"set/reset password" action Admin Users already offers for any account,
which works unchanged for `field` rows since they're stored identically.

## Error handling

- A field user requesting a package that isn't theirs (wrong filename, or
  guessing another callsign) gets the same 404 the listing would show for a
  nonexistent file — not a 403 that would confirm "that file exists but
  isn't yours." Existence of other users' packages should not be
  disclosable to a field account.
- Creating a field account when one already exists for that base name is
  not an error — it's the expected "reuse" path described above.
- If `make_package` fails after the field-account step already succeeded,
  the account still exists (harmless — it just won't have a package to show
  yet until generation is retried).

## Testing

- Generate `Alpha1-iTAK` → confirm a `field` account for `Alpha1` is
  created with a shown-once password; log in as it → see only
  `Alpha1-iTAK.zip` in Packages, Maps fully visible, no other nav items.
- Generate `Alpha1-ATAK` afterward → confirm the *same* account is reused
  (no second password shown), and the field login now sees both
  `Alpha1-iTAK.zip` and `Alpha1-ATAK.zip`.
- As the `Alpha1` field account, attempt to fetch another user's package
  filename directly (bypassing the UI) → confirm 404, not the file.
- Attempt to hit `/api/users`, `/api/logs`, `/api/shell/ws`, or
  `/api/admin-users` as a field-role token → confirm 403 on each.
- Confirm existing `superadmin`/`admin`/`readonly` behavior is completely
  unchanged (full package list, full nav, etc).
- Confirm port 8888 is no longer published or listening after deployment.
- Confirm `get_package.sh <name>` retrieves the right package with the admin
  panel stopped (`docker compose stop admin admin_proxy`), proving it
  doesn't depend on the panel being up.
- Confirm the Packages/Maps/login pages render usably on a phone-sized
  viewport.
