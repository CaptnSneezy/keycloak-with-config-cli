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
  echo "Available products: smartfactory, iot-gateway"
  echo "Optional: customer name for customer-specific config"
  echo ""
  echo "Examples:"
  echo "  $0 smartfactory"
  echo "  $0 smartfactory umsicht"
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

echo -e "${CYAN}[build-config] Building configuration for product: $PRODUCT${NC}"
if [[ -n "$CUSTOMER" ]]; then
  echo "[build-config] Customer: $CUSTOMER"
fi

# Check if product config directory exists
if [[ ! -d "$CONFIG_DIR" ]]; then
  echo -e "${RED}[build-config] Error: Product directory not found: $CONFIG_DIR${NC}"
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
    echo -e "${RED}[build-config] Error: CUSTOMER_CONFIG_REPO_URL not set${NC}"
    echo "Set it in .env file or export it"
    exit 1
  fi

  echo "[build-config] Cloning customer repository..."
  rm -rf "$CUSTOMER_CLONE_DIR"

  if ! git clone --depth 1 "$CUSTOMER_CONFIG_REPO_URL" "$CUSTOMER_CLONE_DIR" 2>/dev/null; then
    echo -e "${RED}[build-config] Error: Failed to clone customer repository${NC}"
    exit 1
  fi

  CUSTOMER_CONFIG_DIR="$CUSTOMER_CLONE_DIR/$CUSTOMER/$PRODUCT/keycloak"

  if [[ ! -d "$CUSTOMER_CONFIG_DIR" ]]; then
    echo -e "${RED}[build-config] Warning: Customer config not found: $CUSTOMER_CONFIG_DIR${NC}"
    echo "[build-config] Continuing without customer-specific config..."
    CUSTOMER_CONFIG_DIR=""
  else
    echo "[build-config] Found customer config at: $CUSTOMER_CONFIG_DIR"
  fi
fi

# Use realm.yaml as base
REALM_FILE="$CONFIG_DIR/realm.yaml"
if [[ ! -s "$REALM_FILE" ]]; then
  echo -e "${RED}[build-config] Error: Missing or empty realm.yaml in $CONFIG_DIR${NC}"
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
echo "[build-config] Merging base configuration..."
for file in "${PROCESSING_ORDER[@]}"; do
  if [[ -n "${FILE_TO_PATH_AND_KEY[$file]:-}" ]]; then
    merge_yaml_file "$file" "$CONFIG_DIR" "base"
  fi
done

# Merge customer-specific configuration
if [[ -n "$CUSTOMER_CONFIG_DIR" ]]; then
  echo "[build-config] Merging customer configuration..."
  for file in "${PROCESSING_ORDER[@]}"; do
    if [[ -n "${FILE_TO_PATH_AND_KEY[$file]:-}" ]]; then
      merge_yaml_file "$file" "$CUSTOMER_CONFIG_DIR" "customer"
    fi
  done
fi

# Cleanup
if [[ -n "$CUSTOMER" ]]; then
  rm -rf "$CUSTOMER_CLONE_DIR"
fi

echo ""
echo -e "${GREEN}[build-config] Build complete!${NC}"
echo "  Product: $PRODUCT"
if [[ -n "$CUSTOMER" ]]; then
  echo "  Customer: $CUSTOMER"
fi
echo "  Output: $MERGED_REALM"