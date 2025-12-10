#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Docker Secrets Setup ===${NC}"
echo ""

# Check if Docker Swarm is initialized
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo -e "${YELLOW}Docker Swarm is not initialized.${NC}"
    echo "Initializing Swarm mode (local only, no cluster)..."
    docker swarm init 2>/dev/null || docker swarm init --advertise-addr 127.0.0.1
    echo -e "${GREEN}Swarm initialized.${NC}"
    echo ""
fi

# Function to create or update a secret
create_secret() {
    local name=$1
    local prompt=$2
    
    # Check if secret already exists
    if docker secret inspect "$name" &>/dev/null; then
        echo -e "${YELLOW}Secret '$name' already exists.${NC}"
        read -p "Overwrite? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping $name"
            return 0
        fi
        docker secret rm "$name" >/dev/null
    fi
    
    # Read secret value
    read -s -p "$prompt: " secret_value
    echo
    
    if [[ -z "$secret_value" ]]; then
        echo -e "${RED}Error: Secret cannot be empty${NC}"
        return 1
    fi
    
    # Create secret
    echo "$secret_value" | docker secret create "$name" -
    echo -e "${GREEN}Created secret: $name${NC}"
}

echo "This will create Docker Secrets for Keycloak deployment."
echo "Secrets are stored encrypted by Docker and never written to disk."
echo ""

# Create all required secrets
create_secret "admin_password" "Enter Keycloak admin password"
create_secret "db_password" "Enter database password"
create_secret "keystore_password" "Enter keystore password"
create_secret "gateway_secret" "Enter gateway client secret"
create_secret "user_secret" "Enter user client secret"
create_secret "node_red_secret" "Enter Node-RED client secret"

echo ""
echo -e "${GREEN}=== Setup complete ===${NC}"
echo ""
echo "Created secrets:"
docker secret ls
echo ""
echo -e "Run ${CYAN}task dev:up${NC} to start Keycloak."
