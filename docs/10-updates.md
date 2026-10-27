

## Updating from a private repository

The update script fetches from the host's `origin`. When the repository is private (the Forgejo copy), git needs a login.

**Default: log in each time, nothing is stored.** Run `scripts/update.sh` in a terminal. Before the update starts it asks for your Forgejo username and a password; paste a **read-only access token** instead of your account password. The answer is held in memory only (git's `credential-cache`) for the length of the run and wiped when the script ends: no file on the host ever contains it. Without a terminal (cron, a service) the script never prompts and stops with a clear message instead.

1. **Point `origin` at the private repository** (once, in the install directory): `git remote set-url origin https://gv3mkw.mokomasis.org/gabrielius.ndukve/TAK.git`. Never put a token in the URL.
2. **Make a token for yourself.** In Forgejo, Settings, Applications, create an access token named after the purpose, with only the `read:repository` scope. A leaked token can read, not write; revoke it any time.
3. **Run the update** and enter the username and token when asked. A wrong value stops the run before anything changes.

**Unattended updates (optional).** For a host that must update by itself, use a separate machine user (for example `efdi-deploy`) with read-only access to `TAK` and its own token, then run `git config --global credential.helper store` and one manual `git fetch`; the token then stays in `~/.git-credentials` (mode 600). Do this only where storing a credential is acceptable. An agent never handles the token.
