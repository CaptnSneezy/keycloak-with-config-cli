#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/..")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <product>"
    echo "Products: smartfactory, iot-gateway"
    exit 1
fi

PRODUCT="$1"

case "$PRODUCT" in
    smartfactory|iot-gateway) ;;
    *)
        echo -e "${RED}Error: Invalid product '$PRODUCT'${NC}"
        exit 1
        ;;
esac

echo -e "${CYAN}[add-userprofile] Setting up User Profile for: $PRODUCT${NC}"

# Load .env
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    source "$PROJECT_ROOT/.env"
fi

: "${DHOSTNAME:?DHOSTNAME is required}"
: "${PORT_KEYCLOAK:?PORT_KEYCLOAK is required}"

# Read admin password from Docker Secret or prompt
if [[ -f /run/secrets/admin_password ]]; then
    ADMIN_PASSWORD=$(cat /run/secrets/admin_password)
elif [[ -z "${ADMIN_PASSWORD:-}" ]]; then
    read -s -p "Enter admin password: " ADMIN_PASSWORD
    echo
fi

KEYCLOAK_URL="https://${DHOSTNAME}:${PORT_KEYCLOAK}"

echo "[add-userprofile] Keycloak URL: $KEYCLOAK_URL"
echo "[add-userprofile] Realm: $PRODUCT"

# Get token
echo "[add-userprofile] Getting token..."
TOKEN_RESPONSE=$(curl -s -k -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=admin" \
    -d "password=${ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli")

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
    echo -e "${RED}Error: Failed to get token${NC}"
    echo "$TOKEN_RESPONSE"
    exit 1
fi

# Create realm if it doesn't exist
echo "[add-userprofile] Checking realm..."
REALM_CHECK=$(curl -s -k -w "%{http_code}" -o /dev/null \
    "${KEYCLOAK_URL}/admin/realms/$PRODUCT" \
    -H "Authorization: Bearer $TOKEN")

if [[ "$REALM_CHECK" == "404" ]]; then
    echo "[add-userprofile] Creating realm $PRODUCT..."
    curl -s -k -X POST \
        "${KEYCLOAK_URL}/admin/realms" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"realm\":\"$PRODUCT\",\"enabled\":true}"
fi

# User Profile configuration
USER_PROFILE_JSON='{
  "attributes": [
    {
      "name": "username",
      "displayName": "Username",
      "permissions": {"view": ["admin", "user"], "edit": ["admin"]},
      "required": {"roles": ["user"]}
    },
    {
      "name": "email",
      "displayName": "Email",
      "permissions": {"view": ["admin", "user"], "edit": ["admin"]},
      "required": {"roles": ["user"]}
    },
    {
      "name": "firstName",
      "displayName": "First name",
      "permissions": {"view": ["admin", "user"], "edit": ["admin"]}
    },
    {
      "name": "lastName",
      "displayName": "Last name",
      "permissions": {"view": ["admin", "user"], "edit": ["admin"]}
    },
    {
      "name": "atrIntern",
      "displayName": "atrIntern",
      "permissions": {"view": ["admin", "user"], "edit": ["admin"]}
    },
    {
      "name": "personnelNumber",
      "displayName": "Personnel Number",
      "permissions": {"view": ["admin", "user"], "edit": ["admin"]}
    }
  ]
}'

echo "[add-userprofile] Applying User Profile..."
HTTP_CODE=$(curl -s -k -w "%{http_code}" -o /dev/null -X PUT \
    "${KEYCLOAK_URL}/admin/realms/$PRODUCT/users/profile" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$USER_PROFILE_JSON")

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "204" ]]; then
    echo -e "${GREEN}[add-userprofile] User Profile setup complete${NC}"
else
    echo -e "${RED}[add-userprofile] Failed with HTTP $HTTP_CODE${NC}"
    exit 1
fi
