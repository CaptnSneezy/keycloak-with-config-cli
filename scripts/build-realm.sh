#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/..")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check dependencies
"$SCRIPT_DIR/check-dependencies.sh"

# Parse arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <product> [customer]"
    echo ""
    echo "Arguments:"
    echo "  product   Product name (smartfactory, iot-gateway)"
    echo "  customer  Customer name (optional, for customer-specific overlay)"
    echo ""
    echo "Examples:"
    echo "  $0 smartfactory"
    echo "  $0 smartfactory umsicht"
    echo "  $0 iot-gateway"
    exit 1
fi

PRODUCT="$1"
CUSTOMER="${2:-}"

# Validate product
case "$PRODUCT" in
    smartfactory|iot-gateway)
        ;;
    *)
        echo -e "${RED}Error: Invalid product '$PRODUCT'${NC}"
        echo "Available products: smartfactory, iot-gateway"
        exit 1
        ;;
esac

# Paths
CONFIG_DIR="$PROJECT_ROOT/config/$PRODUCT"
OUTPUT_DIR="$PROJECT_ROOT/config/merged"
MERGED_REALM="$OUTPUT_DIR/${PRODUCT}-realm.yaml"
TEMP_DIR="$PROJECT_ROOT/.tmp"
CUSTOMER_CLONE_DIR="$TEMP_DIR/customer-config"

echo -e "${CYAN}[build-realm] Building configuration${NC}"
echo "  Product:  $PRODUCT"
echo "  Customer: ${CUSTOMER:-base}"
echo ""

# Check if product config directory exists
if [[ ! -d "$CONFIG_DIR" ]]; then
    echo -e "${RED}Error: Product directory not found: $CONFIG_DIR${NC}"
    exit 1
fi

# Prepare directories
mkdir -p "$OUTPUT_DIR"
mkdir -p "$TEMP_DIR"

# Clone customer repo if customer is specified
CUSTOMER_CONFIG_DIR=""
if [[ -n "$CUSTOMER" ]]; then
    # Load .env for CUSTOMER_CONFIG_REPO_URL
    if [[ -f "$PROJECT_ROOT/.env" ]]; then
        source "$PROJECT_ROOT/.env"
    fi

    CUSTOMER_CONFIG_REPO_URL="${CUSTOMER_CONFIG_REPO_URL:-}"

    if [[ -z "$CUSTOMER_CONFIG_REPO_URL" ]]; then
        echo -e "${RED}Error: CUSTOMER_CONFIG_REPO_URL not set${NC}"
        echo "Set it in .env file or export it"
        exit 1
    fi

    echo "[build-realm] Cloning customer repository..."
    rm -rf "$CUSTOMER_CLONE_DIR"

    if ! git clone --depth 1 "$CUSTOMER_CONFIG_REPO_URL" "$CUSTOMER_CLONE_DIR" 2>/dev/null; then
        echo -e "${RED}Error: Failed to clone customer repository${NC}"
        exit 1
    fi

    CUSTOMER_CONFIG_DIR="$CUSTOMER_CLONE_DIR/$CUSTOMER/$PRODUCT/keycloak"

    if [[ ! -d "$CUSTOMER_CONFIG_DIR" ]]; then
        echo -e "${RED}Warning: Customer config not found: $CUSTOMER_CONFIG_DIR${NC}"
        echo "Continuing without customer-specific config..."
        CUSTOMER_CONFIG_DIR=""
    else
        echo "[build-realm] Found customer config at: $CUSTOMER_CONFIG_DIR"
    fi
fi

# Start with realm.yaml as base
REALM_FILE="$CONFIG_DIR/realm.yaml"
if [[ ! -s "$REALM_FILE" ]]; then
    echo -e "${RED}Error: Missing or empty realm.yaml in $CONFIG_DIR${NC}"
    exit 1
fi

cp "$REALM_FILE" "$MERGED_REALM"

# Mapping: filename -> yaml_path:id_field
declare -A FILE_TO_PATH_AND_KEY=(
    ["users.yaml"]="users:username"
    ["roles.yaml"]="roles:realm:name"
    ["groups.yaml"]="groups:name"
    ["client-scopes.yaml"]="clientScopes:name"
    ["clients.yaml"]="clients:clientId"
    ["ldap.yaml"]="components:special"
)

# Merge function
merge_yaml_file() {
    local file="$1"
    local source_dir="$2"
    local label="$3"
    local path_key="${FILE_TO_PATH_AND_KEY[$file]}"

    local source="$source_dir/$file"
    [[ ! -s "$source" ]] && return 0

    echo "  Merging $file ($label)"

    # Special handling for components (ldap.yaml)
    if [[ "$path_key" == "components:special" ]]; then
        yq eval-all --no-doc 'select(fileIndex == 0) * select(fileIndex == 1)' "$MERGED_REALM" "$source" \
            > "$MERGED_REALM.tmp"
        mv "$MERGED_REALM.tmp" "$MERGED_REALM"
        return 0
    fi

    # Parse path and ID field
    IFS=":" read -r path mid id_field <<< "$path_key"
    [[ -z "$id_field" ]] && { id_field="$mid"; mid=""; }

    # Array merge with intelligent overwrite by ID field
    if [[ -z "$mid" ]]; then
        yq eval-all --no-doc '
            (select(fileIndex == 0) | .'"$path"') as $base |
            (select(fileIndex == 1) | .'"$path"') as $override |
            select(fileIndex == 0) |
            .'"$path"' = (
                ($base // []) + ($override // []) |
                group_by(.'"$id_field"') |
                map(reverse | .[0])
            )
        ' "$MERGED_REALM" "$source" > "$MERGED_REALM.tmp"
    else
        yq eval-all --no-doc '
            (select(fileIndex == 0) | .'"$path"'.'"$mid"') as $base |
            (select(fileIndex == 1) | .'"$path"'.'"$mid"') as $override |
            select(fileIndex == 0) |
            .'"$path"'.'"$mid"' = (
                ($base // []) + ($override // []) |
                group_by(.'"$id_field"') |
                map(reverse | .[0])
            )
        ' "$MERGED_REALM" "$source" > "$MERGED_REALM.tmp"
    fi

    mv "$MERGED_REALM.tmp" "$MERGED_REALM"
}

PROCESSING_ORDER=(
    "roles.yaml"
    "groups.yaml"
    "client-scopes.yaml"
    "clients.yaml"
    "users.yaml"
    "ldap.yaml"
)

# Merge base product configuration
echo "[build-realm] Merging base configuration..."
for file in "${PROCESSING_ORDER[@]}"; do
    if [[ -n "${FILE_TO_PATH_AND_KEY[$file]:-}" ]]; then
        merge_yaml_file "$file" "$CONFIG_DIR" "base"
    fi
done

# Merge customer-specific configuration
if [[ -n "$CUSTOMER_CONFIG_DIR" ]]; then
    echo "[build-realm] Merging customer configuration..."
    for file in "${PROCESSING_ORDER[@]}"; do
        if [[ -n "${FILE_TO_PATH_AND_KEY[$file]:-}" ]]; then
            merge_yaml_file "$file" "$CUSTOMER_CONFIG_DIR" "customer"
        fi
    done
fi

# Apply variable substitution placeholders for keycloak-config-cli
echo "[build-realm] Applying variable substitution placeholders..."
sed -i 's/DHOSTNAME/$(DHOSTNAME)/g' "$MERGED_REALM"
sed -i 's/PORT_GATEWAY/$(PORT_GATEWAY)/g' "$MERGED_REALM"
sed -i 's/PORT_KEYCLOAK/$(PORT_KEYCLOAK)/g' "$MERGED_REALM"
sed -i 's/GATEWAY_SECRET/$(GATEWAY_SECRET)/g' "$MERGED_REALM"
sed -i 's/USER_SECRET/$(USER_SECRET)/g' "$MERGED_REALM"
sed -i 's/NODE_RED_SECRET/$(NODE_RED_SECRET)/g' "$MERGED_REALM"

# Cleanup
if [[ -n "$CUSTOMER" ]]; then
    rm -rf "$CUSTOMER_CLONE_DIR"
fi

echo ""
echo -e "${GREEN}[build-realm] Build complete!${NC}"
echo "  Output: $MERGED_REALM"