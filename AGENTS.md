# Agent contract

TAK is the TAK Server packaging for EFDI (Docker, rootful today) with its own admin WebUI; it is a sibling of EFDI-Core.

## Required behavior

- Read `CLAUDE.md` in this repository first: it holds the project knowledge and the standing rules, and applies to every agent and tool.
- The operator commits and pushes. Do not commit, push, merge, rebase, tag, reset or clean. Keep the commit message in `docs/COMMIT_MSG.txt` (gitignored, the only commit-message file) and add no co-author or session trailers.
- Inspect existing code and ownership before changing anything; extend what exists instead of building a parallel system. Fix a bug at its root cause and grep every caller.
- Never print, copy or store secret values: passwords, tokens, setup keys, private keys, CA keys, kubeconfigs. The operator creates secrets and runs `sudo`; an agent only checks names and sizes.
- Before anything that deletes, closes, kills or overwrites, look at the target first, and never test a destructive command on something in use. Never bypass an SSH host-key check; accepting a key is the operator's job.
- Update the documentation (English and Lithuanian) and the agent notes in the same change as the code. Lithuanian text keeps established English technical terms (HA, failover, layout, bucket, access key, reverse proxy) and says "sensorius", not "jutiklis".
- A structural fix goes to every sibling repo that shares the pattern (EFDI-Core, EFDI-Edge, EFDI-Inter, EFDI-Allies, TAK, EFDI-Kube).
- Write public addresses as `x.x.x.<last digits>` in documentation. Never add partner or radar-site details to a published output.
- Say plainly what was verified and what was not. Report commands actually run, failures, live changes and the exact next step for the operator.

## Canonical paths

- Stack: `docker-compose.yml`, `Dockerfile`, `Makefile`, `docker/`, `templates/`
- Admin WebUI: `admin/`; host scripts: `scripts/` (`install.sh`, `update.sh` (run as root), `backup.sh`, `restore.sh`, `reset_admin_password.sh` is a sourced function)
- Documentation: `docs/` (English and Lithuanian pairs)

## Validation

- Shell scripts are shellcheck-clean; `scripts/_selftest.sh` and the smoke tests in `scripts/` cover the installer.
- Never print the contents of `takserver.env`; check key names only.

## Repository specifics

- The admin and CoT ports are 1414 and 443 (reverse proxy), set in `docker-compose.yml`; the server address is kept in sync by `scripts/sync_server_address.sh`.
- TAK data lives in `/srv/tak-data` on the TAK VM; set CoT retention in `takserver.env`.
- Revoking a user certificate means the `certmod` revoked group, not only deleting the package.
- Server certificates keep internal CN `takserver` and include `TAK_SERVER_ADDRESS` plus optional `TAK_SERVER_ADDRESS_LAN` as SANs. Existing installations need operator-run `scripts/renew_server_cert.sh` after a backup; image updates do not rotate stored certificates.
- WebUI package creation reads the TAK display name from `BrandSettings.tak_server_name`; command-line package creation continues to use `TAK_SERVER_NAME` from the env file.
- Python and UI CI jobs run dependency audits before tests/builds; check failed-step logs because an audit failure prevents those later steps from running.
- Server certificate renewal must overwrite the existing JKS alias and verify its fingerprint matches the newly issued PEM before restarting TAK; the operator may need to reimport the already generated P12 after a failed renewal.
