

## Updating from a private repository

The update script fetches from the host's `origin`. When the repository is private (the Forgejo copy), git needs a login.

**Default: log in each time, nothing is stored.** Run `scripts/update.sh` in a terminal. Before the update starts it asks for your Forgejo username and a password; paste a **read-only access token** instead of your account password. The answer is held in memory only (git's `credential-cache`) for the length of the run and wiped when the script ends: no file on the host ever contains it. Without a terminal (cron, a service) the script never prompts and stops with a clear message instead.

1. **Point `origin` at the private repository** (once, in the install directory): `git remote set-url origin https://gv3mkw.mokomasis.org/gabrielius.ndukve/TAK.git`. Never put a token in the URL.
2. **Make a token for yourself.** In Forgejo, Settings, Applications, create an access token named after the purpose, with only the `read:repository` scope. A leaked token can read, not write; revoke it any time.
3. **Run the update** and enter the username and token when asked. A wrong value stops the run before anything changes.

**Unattended updates (optional).** For a host that must update by itself, use a separate machine user (for example `efdi-deploy`) with read-only access to `TAK` and its own token, then run `git config --global credential.helper store` and one manual `git fetch`; the token then stays in `~/.git-credentials` (mode 600). Do this only where storing a credential is acceptable. An agent never handles the token.

## Versions: updating to a tag and going back

`scripts/update.sh` with no argument moves to the tip of the branch, as before, but now shows the version it is on and the commits it is about to apply, and asks first when run from a terminal (`--yes` or `EFDI_UPDATE_YES=1` skips the question).

- `scripts/update.sh --to v0.9.0` moves to a release tag (a tag called `stable` works the same). When a signers file exists (`EFDI_ALLOWED_SIGNERS`, or `.allowed_signers` in the repository directory), the tag must be signed by one of those SSH keys (`git verify-tag`); an unsigned tag is refused.
- Before it moves, the script records the version it came from (`.previous-version`, untracked). `scripts/update.sh --rollback` goes back to it. Moving back is refused if this checkout holds commits that exist on no remote.
- The update ends by printing the version (`git describe`).

A rollback moves the code back; it does not undo data changes. Take a backup first when a release changes configuration.
