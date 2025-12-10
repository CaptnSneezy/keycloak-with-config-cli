#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/..")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Keycloak Deployment ===${NC}"
echo ""

cd "$PROJECT_ROOT"

# Load .env
if [[ -f .env ]]; then
    source .env
fi

# Check if Docker Secrets exist
check_secrets() {
    local missing=0
    local secrets=("admin_password" "db_password" "keystore_password" "gateway_secret" "user_secret" "node_red_secret")
    
    for secret in "${secrets[@]}"; do
        if ! docker secret inspect "$secret" &>/dev/null; then
            echo -e "${RED}[x] Missing secret: $secret${NC}"
            missing=1
        fi
    done
    
    if [[ $missing -eq 1 ]]; then
        echo ""
        echo -e "${YELLOW}Run 'task secrets:setup' to create missing secrets.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}[ok] All secrets present${NC}"
}

# Wait for service to be healthy
wait_for_healthy() {
    local service=$1
    local max_wait=${2:-120}
    local elapsed=0
    
    echo -n "[deploy] Waiting for $service to be healthy"
    while [[ $elapsed -lt $max_wait ]]; do
        if docker compose ps "$service" 2>/dev/null | grep -q "healthy"; then
            echo -e " ${GREEN}ready${NC}"
            return 0
        fi
        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    echo -e " ${RED}timeout${NC}"
    return 1
}

# Check Swarm mode
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo -e "${YELLOW}Docker Swarm not active. Initializing...${NC}"
    docker swarm init 2>/dev/null || docker swarm init --advertise-addr 127.0.0.1
fi

# Check secrets
check_secrets

# Check for merged config
if [[ ! -f config/merged/*-realm.yaml ]]; then
    echo -e "${RED}Error: No merged realm config found.${NC}"
    echo "Run 'task config:build:...' first."
    exit 1
fi

REALM_FILE=$(ls config/merged/*-realm.yaml | head -1)
PRODUCT=$(basename "$REALM_FILE" | sed 's/-realm\.yaml$//')

echo "[deploy] Found config: $REALM_FILE"
echo "[deploy] Product: $PRODUCT"
echo ""

# Stop existing containers
echo "[deploy] Stopping existing containers..."
docker compose down --remove-orphans 2>/dev/null || true

# Start Postgres and Keycloak
echo "[deploy] Starting Postgres and Keycloak..."
docker compose up -d postgres keycloak

wait_for_healthy "keycloak-postgres" 60
wait_for_healthy "keycloak" 120

# Apply User Profile workaround
echo "[deploy] Applying User Profile configuration..."
"$SCRIPT_DIR/add-userprofile.sh" "$PRODUCT"

# Run keycloak-config-cli
echo "[deploy] Importing realm configuration..."
docker compose --profile import up keycloak-cli

echo ""
echo -e "${GREEN}=== Deployment complete ===${NC}"
echo ""
echo "Keycloak is running at: https://${DHOSTNAME:-localhost}:${PORT_KEYCLOAK:-7444}"
echo ""
docker compose ps
