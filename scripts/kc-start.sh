#!/bin/bash
set -e

echo "[kc-start.sh] Updating CA trust store..."
update-ca-trust extract

echo "[kc-start.sh] Starting Keycloak in production mode..."
/opt/keycloak/bin/kc.sh start \
                        --optimized \
                        --https-key-store-password="${KC_HTTPS_KEY_STORE_PASSWORD}" &

echo "[kc-start.sh] Wait for Keycloak to become healthy..."
timeout=60
elapsed=0
while ! curl -k --silent --fail https://localhost:9000/health/ready > /dev/null; do
  sleep 2
  elapsed=$((elapsed + 2))
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "Timeout on waiting for Keycloak to become healthy"
    exit 1
  fi
done
echo "[kc-start.sh] Keycloak started successful!"

wait
