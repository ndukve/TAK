# Shared package-layout self-test — source this from update.sh / health.sh.
# Requires scripts/_spinner.sh already sourced (uses its ok/info/warn/fail).
#
# Generates one throwaway ATAK package and one throwaway iTAK package and
# verifies their zip structure actually differs the way make_pkg_zip.sh's
# suffix branching says it should (nested content/ for ATAK/WinTAK, flat for
# iTAK). A matching git-commit image label only proves a container was built
# from the right source — it does NOT prove the code inside actually works,
# which is exactly how an iTAK package kept coming out in the wrong layout
# for several rebuilds even though the label matched HEAD.
#
# package_selftest: returns 0 on pass, 1 on fail. Does not exit/fail itself —
# the caller decides what to do (hard-fail immediately vs. attempt recovery
# first via health.sh).

package_selftest() {
    local dc="docker compose --env-file $ENV_FILE"

    info "Self-test: verifying package layouts..."

    local wait_ok=1
    local deadline=$(( $(date +%s) + 120 ))
    until $dc exec -T takserver_config test -f /opt/tak/data/certs/files/root-ca.pem 2>/dev/null; do
        [ "$(date +%s)" -lt "$deadline" ] || { wait_ok=0; break; }
        sleep 3
    done

    if [ "$wait_ok" -eq 0 ]; then
        warn "Self-test skipped — takserver_config wasn't ready within 2 minutes"
        return 1
    fi

    local failed=0

    _selftest_one() {
        local name="$1" expect_content="$2"  # expect_content: yes|no
        # Full file set makeCert.sh's client path produces (.key .csr .pem
        # .p12 -public.p12 .jks) — a prior run's leftover .jks in particular
        # makes keytool -importkeystore hit an "alias already exists"
        # conflict on the next run, which then hangs/dies waiting on an
        # overwrite prompt that never comes non-interactively.
        $dc exec -T -u root takserver_config rm -f \
            "/opt/tak/data/certs/files/${name}.key" \
            "/opt/tak/data/certs/files/${name}.csr" \
            "/opt/tak/data/certs/files/${name}.pem" \
            "/opt/tak/data/certs/files/${name}.p12" \
            "/opt/tak/data/certs/files/${name}-public.p12" \
            "/opt/tak/data/certs/files/${name}.jks" \
            "/opt/tak/data/certs/files/${name}.certpass" \
            "/opt/tak/data/certs/files/clientpkgs/${name}.zip" 2>/dev/null || true

        local _st_log
        _st_log="$(mktemp)"
        if ! $dc exec -T -e CLIENT_CERT_NAME="$name" takserver_config \
            bash /opt/scripts/gen_client_cert.sh > "$_st_log" 2>&1; then
            warn "Self-test cert generation failed for ${name} — gen_client_cert.sh may be broken"
            cat "$_st_log"
            rm -f "$_st_log"
            return 1
        fi

        if ! $dc exec -T -e CLIENT_CERT_NAME="$name" -e TAK_SERVER_ADDRESS=selftest takserver_config \
            bash /opt/scripts/make_pkg_zip.sh > "$_st_log" 2>&1; then
            warn "Self-test package build failed for ${name} — make_pkg_zip.sh may be broken"
            cat "$_st_log"
            rm -f "$_st_log"
            return 1
        fi
        rm -f "$_st_log"

        local listing has_content
        listing="$($dc exec -T takserver_config unzip -l "/opt/tak/data/certs/files/clientpkgs/${name}.zip" 2>/dev/null)"
        if echo "$listing" | grep -q "content/"; then has_content="yes"; else has_content="no"; fi

        $dc exec -T -u root takserver_config rm -f \
            "/opt/tak/data/certs/files/${name}.key" "/opt/tak/data/certs/files/${name}.pem" \
            "/opt/tak/data/certs/files/${name}.p12" "/opt/tak/data/certs/files/${name}.csr" \
            "/opt/tak/data/certs/files/${name}-public.p12" "/opt/tak/data/certs/files/${name}.jks" \
            "/opt/tak/data/certs/files/${name}.certpass" \
            "/opt/tak/data/certs/files/clientpkgs/${name}.zip" 2>/dev/null || true

        if [ "$has_content" != "$expect_content" ]; then
            warn "Self-test FAILED: ${name}.zip has content/=${has_content}, expected content/=${expect_content}"
            return 1
        fi
        return 0
    }

    _selftest_one "selftest-ATAK" "yes" || failed=1
    _selftest_one "selftest-iTAK" "no"  || failed=1

    if [ "$failed" -eq 0 ]; then
        ok "Self-test passed — ATAK/WinTAK (nested) and iTAK (flat) package layouts both correct"
        return 0
    fi
    return 1
}
