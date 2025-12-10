#!/bin/bash
set -e

echo "[keycloak-cli] Reading secrets..."

# Read secrets from Docker Secret files and export as env vars
if [[ -f /run/secrets/admin_password ]]; then
    export KEYCLOAK_PASSWORD=$(cat /run/secrets/admin_password)
fi

if [[ -f /run/secrets/gateway_secret ]]; then
    export IMPORT_VAR_GATEWAY_SECRET=$(cat /run/secrets/gateway_secret)
fi

if [[ -f /run/secrets/user_secret ]]; then
    export IMPORT_VAR_USER_SECRET=$(cat /run/secrets/user_secret)
fi

if [[ -f /run/secrets/node_red_secret ]]; then
    export IMPORT_VAR_NODE_RED_SECRET=$(cat /run/secrets/node_red_secret)
fi

echo "[keycloak-cli] Starting import..."
exec java -jar /opt/keycloak-config-cli.jar
