#!/bin/bash
set -e

echo "[kc-start] Updating CA trust store..."
update-ca-trust extract

# Read password from secret file if provided
if [[ -f "$KC_HTTPS_KEY_STORE_PASSWORD_FILE" ]]; then
    export KC_HTTPS_KEY_STORE_PASSWORD=$(cat "$KC_HTTPS_KEY_STORE_PASSWORD_FILE")
fi

if [[ -f "$KC_BOOTSTRAP_ADMIN_PASSWORD_FILE" ]]; then
    export KC_BOOTSTRAP_ADMIN_PASSWORD=$(cat "$KC_BOOTSTRAP_ADMIN_PASSWORD_FILE")
fi

if [[ -f "$KC_DB_PASSWORD_FILE" ]]; then
    export KC_DB_PASSWORD=$(cat "$KC_DB_PASSWORD_FILE")
fi

echo "[kc-start] Starting Keycloak..."
exec /opt/keycloak/bin/kc.sh start --optimized
