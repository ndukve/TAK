#!/usr/bin/env bash
# Unified user/package management CLI — merges what used to be
# generate_user.sh, purge_user.sh, and get_package.sh into one tool.
#
# Usage:
#   ./users.sh                          interactive menu
#   ./users.sh create [callsign-XXX]    generate cert + package + authorize
#   ./users.sh purge <name>             force-remove all cert/package files for a user
#   ./users.sh get [name]               download a package (no name: list available)
#   ./users.sh repair-groups             assign all packaged clients to the shared routing group
#   ./users.sh grant-admin <cert-name>  grant TAK server admin rights to a cert
#   ./users.sh revoke-admin <cert-name> revoke TAK server admin rights from a cert
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/takserver.env"
# shellcheck source=scripts/_spinner.sh
. "$SCRIPT_DIR/scripts/_spinner.sh"

[ -f "$ENV_FILE" ] || fail "takserver.env not found — run ./install.sh first"

TAK_USER_GROUP=$(grep '^TAK_USER_GROUP=' "$ENV_FILE" | cut -d= -f2- || true)
TAK_USER_GROUP=${TAK_USER_GROUP:-TAK-USERS}
[[ "$TAK_USER_GROUP" =~ ^[A-Za-z0-9_.-]+$ ]] \
    || fail "TAK_USER_GROUP must contain only letters, numbers, dots, hyphens, or underscores"

DC="docker compose"
docker info &>/dev/null 2>&1 || DC="sudo docker compose"

_NAME_RE='^[a-zA-Z0-9_-]+-(ATAK|WinTAK|iTAK|Service)$'

cmd_create() {
    local USERNAME="${1:-}"
    if [ -z "$USERNAME" ]; then
        while true; do
            printf "  Callsign, ending in -ATAK, -WinTAK, -iTAK, or -Service (e.g. alpha1-iTAK): "
            read -r USERNAME
            [[ "$USERNAME" =~ $_NAME_RE ]] && break
            printf "  ${R}Invalid — must end in -ATAK, -WinTAK, -iTAK, or -Service${NC}\n"
        done
    elif [[ ! "$USERNAME" =~ $_NAME_RE ]]; then
        fail "Callsign must end in -ATAK, -WinTAK, -iTAK, or -Service (e.g. alpha1-iTAK)"
    fi

    local TAK_SERVER_ADDRESS
    TAK_SERVER_ADDRESS=$(grep '^TAK_SERVER_ADDRESS=' "$ENV_FILE" | cut -d= -f2)

    banner "New User: $USERNAME"

    run_spin "Generating device certificate" "Certificate generated" \
        $DC --env-file "$ENV_FILE" exec -T \
            -e CLIENT_CERT_NAME="$USERNAME" \
            takserver_config bash /opt/scripts/gen_client_cert.sh \
        || fail "Certificate generation failed (see output above)."

    run_spin "Building data package" "Package built" \
        $DC --env-file "$ENV_FILE" exec -T \
            -e CLIENT_CERT_NAME="$USERNAME" \
            -e TAK_SERVER_ADDRESS="$TAK_SERVER_ADDRESS" \
            takserver_config bash /opt/scripts/make_pkg_zip.sh \
        || fail "Package build failed (see output above)."

    run_spin "Authorizing on server" "Authorized" \
        $DC --env-file "$ENV_FILE" exec -T \
            -e USER_CERT_NAME="$USERNAME" \
            -e TAK_USER_GROUP="$TAK_USER_GROUP" \
            takserver_config bash /opt/scripts/enable_user.sh \
        || fail "Authorization failed (see output above)."

    printf "\n"
    printf "  ${G}┌────────────────────────────────────────────────┐${NC}\n"
    printf "  ${G}│${NC}  ${W}%s${NC} is ready                              ${G}│${NC}\n" "$USERNAME"
    printf "  ${G}└────────────────────────────────────────────────┘${NC}\n"
    printf "\n"
    printf "  ${DIM}Download:${NC}  https://${TAK_SERVER_ADDRESS}:8889/packages -> ${USERNAME}.zip (admin login required)\n"
    printf "\n"
    printf "  ${DIM}Import in TAK client:${NC}\n"
    printf "  ${DIM}  iTAK  :${NC}  Settings → Network → Servers → + → Upload Server Package\n"
    printf "  ${DIM}  ATAK  :${NC}  Hamburger → Settings → Network Preferences → TAK Servers → Import\n"
    printf "  ${DIM}  WinTAK:${NC}  Settings → Network Preferences → Server Connections → Import\n"
    printf "\n"
}

cmd_repair_groups() {
    banner "Repair Client Routing Groups"

    local USERS
    USERS=$($DC --env-file "$ENV_FILE" exec -T takserver_config bash -c '
        shopt -s nullglob
        for package in /opt/tak/data/certs/files/clientpkgs/*.zip; do
            basename "$package" .zip
        done
    ')

    [ -n "$USERS" ] || { warn "No packaged TAK clients found."; return; }

    local USERNAME COUNT=0
    while IFS= read -r USERNAME; do
        [[ "$USERNAME" =~ $_NAME_RE || "$USERNAME" = "efdi-bridge" ]] \
            || { warn "Skipping unexpected package name: $USERNAME"; continue; }
        run_spin "Assigning $USERNAME to $TAK_USER_GROUP" "Assigned $USERNAME" \
            $DC --env-file "$ENV_FILE" exec -T \
                -e USER_CERT_NAME="$USERNAME" \
                -e TAK_USER_GROUP="$TAK_USER_GROUP" \
                takserver_config bash /opt/scripts/enable_user.sh \
            || fail "Group assignment failed for $USERNAME (see output above)."
        COUNT=$((COUNT + 1))
    done <<< "$USERS"

    ok "$COUNT client certificate(s) assigned to $TAK_USER_GROUP with IN + OUT access"
}

cmd_purge() {
    local NAME="${1:-}"
    [ -n "$NAME" ] || fail "Usage: $0 purge <name>"
    [[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || fail "Name must be alphanumeric (hyphens/underscores allowed) — got: $NAME"
    case "$NAME" in
        efdi-bridge|efdi-bridge-ATAK|efdi-bridge-WinTAK|efdi-bridge-iTAK|efdi-bridge-Service)
            fail "efdi-bridge is an always-on integration and cannot be purged"
            ;;
    esac

    local CR=/opt/tak/data/certs
    local FILES=(
        "$CR/files/$NAME.certpass"
        "$CR/files/$NAME.p12"
        "$CR/files/$NAME.pem"
        "$CR/files/$NAME.key"
        "$CR/files/$NAME.csr"
        "$CR/files/$NAME.jks"
        "$CR/files/$NAME-public.p12"
        "$CR/files/$NAME-trusted.pem"
        "$CR/files/clientpkgs/$NAME.zip"
    )
    $DC --env-file "$ENV_FILE" exec -T -u root takserver_config rm -f "${FILES[@]}"
    ok "${NAME} purged"
}

cmd_get() {
    local NAME="${1:-}"

    if [ -z "$NAME" ]; then
        info "Available packages:"
        $DC --env-file "$ENV_FILE" exec -T takserver_config \
            bash -c "ls /opt/tak/data/certs/files/clientpkgs/*.zip 2>/dev/null | xargs -n1 basename" \
            || warn "No packages found."
        return
    fi

    local DEST="./${NAME}.zip"
    [ ! -f "$DEST" ] || fail "$DEST already exists in the current directory — remove it first or run this from elsewhere."
    $DC --env-file "$ENV_FILE" exec -T takserver_config \
        bash -c 'cat "/opt/tak/data/certs/files/clientpkgs/$1.zip"' -- "$NAME" > "$DEST" \
        || { rm -f "$DEST"; fail "Package '$NAME' not found."; }
    ok "Saved to ${DEST}"
}

cmd_grant_admin() {
    local NAME="${1:-}"
    [ -n "$NAME" ] || fail "Usage: $0 grant-admin <cert-name>"
    $DC --env-file "$ENV_FILE" exec -T -e ADMIN_CERT_NAME="$NAME" \
        takserver_config bash /opt/scripts/enable_admin.sh \
        || fail "Granting admin rights failed (see output above)."
}

cmd_revoke_admin() {
    local NAME="${1:-}"
    [ -n "$NAME" ] || fail "Usage: $0 revoke-admin <cert-name>"
    $DC --env-file "$ENV_FILE" exec -T -e ADMIN_CERT_NAME="$NAME" \
        takserver_config bash /opt/scripts/disable_admin.sh \
        || fail "Revoking admin rights failed (see output above)."
}

case "${1:-}" in
    create)       shift; cmd_create "${1:-}" ;;
    purge)        shift; cmd_purge "${1:-}" ;;
    get)          shift; cmd_get "${1:-}" ;;
    repair-groups) shift; cmd_repair_groups ;;
    grant-admin)  shift; cmd_grant_admin "${1:-}" ;;
    revoke-admin) shift; cmd_revoke_admin "${1:-}" ;;
    "")
        banner "Users & Packages"
        while true; do
            echo ""
            echo "1) Create user (cert + package + authorize)"
            echo "2) Purge user (force-remove cert/package files)"
            echo "3) Get package (list, or download by name)"
            echo "4) Repair shared client routing groups"
            echo "5) Grant TAK admin rights to a cert"
            echo "6) Revoke TAK admin rights from a cert"
            echo "7) Exit"
            read -rp "> " CHOICE || { echo; exit 0; }
            case "$CHOICE" in
                1) read -rp "Callsign (blank to be prompted): " N; cmd_create "$N" ;;
                2) read -rp "Name to purge: " N; [ -n "$N" ] && cmd_purge "$N" || warn "No name given." ;;
                3) read -rp "Package name (blank to list): " N; cmd_get "$N" ;;
                4) cmd_repair_groups ;;
                5) read -rp "Cert name: " N; [ -n "$N" ] && cmd_grant_admin "$N" || warn "No name given." ;;
                6) read -rp "Cert name: " N; [ -n "$N" ] && cmd_revoke_admin "$N" || warn "No name given." ;;
                7) exit 0 ;;
                *) warn "Invalid choice." ;;
            esac
        done
        ;;
    *) fail "Usage: $0 [create [callsign-XXX] | purge <name> | get [name] | repair-groups | grant-admin <name> | revoke-admin <name>]" ;;
esac
