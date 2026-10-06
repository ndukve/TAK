#!/usr/bin/env -S /bin/bash
# shellcheck shell=bash

G='\033[0;32m' R='\033[0;31m' C='\033[0;36m' NC='\033[0m'
ok()   { printf "${G}  ✓${NC}  %s\n" "$*"; }
fail() { printf "${R}  ✗${NC}  %s\n" "$*" >&2; exit 1; }
info() { printf "${C}  →${NC}  %s\n" "$*"; }

set -e

TR=/opt/tak

export TAKCL_CORECONFIG_PATH=${TR}/data/CoreConfig_${1}.xml
COMMON_CONFIG_PATH=${TR}/data/CoreConfig.xml
IGNITE_CONFIG_PATH=${TR}/data/TAKIgniteConfig.xml

sleep 2

info "Generating CoreConfig for process: ${1}"
gomplate -f /opt/templates/CoreConfig.tpl -o ${COMMON_CONFIG_PATH}
gomplate -f /opt/templates/CoreConfig.tpl -o ${TAKCL_CORECONFIG_PATH}
ln -sf ${TAKCL_CORECONFIG_PATH} ${TR}/CoreConfig.xml
ok "CoreConfig ready"

info "Generating IgniteConfig"
gomplate -f /opt/templates/TAKIgniteConfig.tpl -o ${IGNITE_CONFIG_PATH}
ln -sf ${IGNITE_CONFIG_PATH} ${TR}/TAKIgniteConfig.xml
ok "IgniteConfig ready"

info "Ensuring Logback config is in place"
cp /opt/templates/logback-stdout.xml /opt/tak/
ok "Logback config ready"

# Restore symlinks if needed (e.g. after container restart)
if [[ ! -L "${TR}/certs" ]]; then
    mv ${TR}/certs ${TR}/certs.orig
    ln -s "${TR}/data/certs/" "${TR}/certs"
fi
if [[ ! -L "${TR}/logs" ]]; then
    mv ${TR}/logs ${TR}/logs.orig
    ln -s "${TR}/data/logs/" "${TR}/logs"
fi

cd ${TR}
. ./setenv.sh

case "${1}" in
    messaging)
        info "Starting TAK Messaging"
        exec java -jar -Xmx${MESSAGING_MAX_HEAP}m \
            -Dspring.profiles.active=messaging,consolelog \
            -Dkeystore.pkcs12.legacy takserver.war
        ;;
    config)
        info "Starting TAK Config"
        exec java -jar -Xmx${CONFIG_MAX_HEAP}m \
            -Dspring.profiles.active=config takserver.war
        ;;
    api)
        info "Starting TAK API"
        exec java -jar -Xmx${API_MAX_HEAP}m \
            -Dspring.profiles.active=api,consolelog \
            -Dkeystore.pkcs12.legacy takserver.war
        ;;
    retention)
        info "Starting TAK Retention"
        # The jar's logback.xml reads ${AUDIT_ENABLED} and ${JSON_FORMAT_ENABLED} through
        # <springProperty>, which logback ignores outside a Spring context, so the <if> on
        # them fails to parse ("AUDIT_ENABLED_IS_UNDEFINED is not an rvalue") and the service
        # dies in its static logger initialiser. Plain environment variables define them.
        export AUDIT_ENABLED="${AUDIT_ENABLED:-false}" JSON_FORMAT_ENABLED="${JSON_FORMAT_ENABLED:-false}"
        # Retention policy. TAK_RETENTION_COT_DAYS is how many days of CoT to keep ("null" = forever).
        # TAK_RETENTION_CRON is a Spring cron for the purge run; "-" (the default) keeps the
        # service idle, so setting the policy never deletes anything until a schedule is set on purpose.
        cat > /opt/tak/conf/retention/retention-policy.yml <<POLICY
---
dataRetentionMap:
  cot: ${TAK_RETENTION_COT_DAYS:-1}
  files: null
  missionpackages: null
  missions: null
  geochat: null

retentionSettings:
  files:
    exemptKeywords: []
POLICY
        printf -- '---\ncronExpression: "%s"\n' "${TAK_RETENTION_CRON:--}" > /opt/tak/conf/retention/retention-service.yml
        exec java -jar -Xmx${RETENTION_MAX_HEAP}m takserver-retention.jar
        ;;
    pm)
        info "Starting TAK Plugin Manager"
        exec java -jar -Xmx${PLUGIN_MANAGER_MAX_HEAP}m \
            -Dloader.path=WEB-INF/lib-provided,WEB-INF/lib,WEB-INF/classes,file:lib/ \
            takserver-pm.jar
        ;;
    *)
        fail "Unknown component: ${1}  (valid: messaging, config, api, retention, pm)"
        ;;
esac
