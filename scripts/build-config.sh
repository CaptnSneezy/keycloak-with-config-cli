#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(realpath "$SCRIPT_DIR/..")"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

PROCESSING_ORDER=(
  "roles.yaml"
  "groups.yaml"
  "client-scopes.yaml"
  "clients.yaml"
  "users.yaml"
  "ldap.yaml"
)

declare -A FILE_TO_PATH_AND_KEY=(
  ["users.yaml"]="users:username"
  ["roles.yaml"]="roles:realm:name"
  ["groups.yaml"]="groups:name"
  ["client-scopes.yaml"]="clientScopes:name"
  ["clients.yaml"]="clients:clientId"
  ["ldap.yaml"]="components:special"
)

# =============================================================================
# Functions
# =============================================================================

usage() {
  echo "Usage: $0 <product> [customer]"
  echo ""
  echo "Arguments:"
  echo "  product   smartfactory | iot-gateway"
  echo "  customer  Optional: customer name for overlay config"
  echo ""
  echo "Examples:"
  echo "  $0 smartfactory"
  echo "  $0 smartfactory umsicht"
  exit 1
}

error() {
  echo -e "${RED}[build-config] Error: $1${NC}" >&2
  exit 1
}

info() {
  echo -e "${CYAN}[build-config]${NC} $1"
}

success() {
  echo -e "${GREEN}[build-config]${NC} $1"
}

merge_yaml_file() {
  local file="$1"
  local source_dir="$2"
  local label="$3"
  local path_key="${FILE_TO_PATH_AND_KEY[$file]}"
  local source="$source_dir/$file"

  [[ ! -s "$source" ]] && return 0

  echo "  -> $file ($label)"

  # Special handling for components (ldap.yaml)
  if [[ "$path_key" == "components:special" ]]; then
    yq eval-all --no-doc 'select(fileIndex == 0) * select(fileIndex == 1)' \
      "$MERGED_REALM" "$source" > "$MERGED_REALM.tmp"
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
      .'"$path"' = (($base // []) + ($override // []) | group_by(.'"$id_field"') | map(reverse | .[0]))
    ' "$MERGED_REALM" "$source" > "$MERGED_REALM.tmp"
  else
    yq eval-all --no-doc '
      (select(fileIndex == 0) | .'"$path"'.'"$mid"') as $base |
      (select(fileIndex == 1) | .'"$path"'.'"$mid"') as $override |
      select(fileIndex == 0) |
      .'"$path"'.'"$mid"' = (($base // []) + ($override // []) | group_by(.'"$id_field"') | map(reverse | .[0]))
    ' "$MERGED_REALM" "$source" > "$MERGED_REALM.tmp"
  fi

  mv "$MERGED_REALM.tmp" "$MERGED_REALM"
}

clone_customer_repo() {
  [[ -f "$PROJECT_ROOT/.env" ]] && source "$PROJECT_ROOT/.env"

  CUSTOMER_CONFIG_REPO_URL="${CUSTOMER_CONFIG_REPO_URL:-}"
  [[ -z "$CUSTOMER_CONFIG_REPO_URL" ]] && error "CUSTOMER_CONFIG_REPO_URL not set in .env"

  info "Cloning customer repository..."
  rm -rf "$CUSTOMER_CLONE_DIR"

  git clone --depth 1 "$CUSTOMER_CONFIG_REPO_URL" "$CUSTOMER_CLONE_DIR" 2>/dev/null \
    || error "Failed to clone customer repository"

  CUSTOMER_CONFIG_DIR="$CUSTOMER_CLONE_DIR/$CUSTOMER/$PRODUCT/keycloak"

  if [[ ! -d "$CUSTOMER_CONFIG_DIR" ]]; then
    echo -e "${RED}[build-config] Warning: Customer config not found: $CUSTOMER_CONFIG_DIR${NC}"
    CUSTOMER_CONFIG_DIR=""
  else
    info "Found customer config: $CUSTOMER_CONFIG_DIR"
  fi
}

# =============================================================================
# Main
# =============================================================================

"$SCRIPT_DIR/check-dependencies.sh"

[[ $# -lt 1 ]] && usage

PRODUCT="$1"
CUSTOMER="${2:-}"

case "$PRODUCT" in
  smartfactory|iot-gateway) ;;
  *) error "Invalid product '$PRODUCT'. Available: smartfactory, iot-gateway" ;;
esac

# Paths
CONFIG_DIR="$PROJECT_ROOT/config/$PRODUCT"
OUTPUT_DIR="$PROJECT_ROOT/config/merged"
MERGED_REALM="$OUTPUT_DIR/${PRODUCT}-realm.yaml"
TEMP_DIR="$PROJECT_ROOT/.tmp"
CUSTOMER_CLONE_DIR="$TEMP_DIR/customer-config"
CUSTOMER_CONFIG_DIR=""

info "Building: $PRODUCT${CUSTOMER:+ + $CUSTOMER}"

[[ ! -d "$CONFIG_DIR" ]] && error "Product directory not found: $CONFIG_DIR"

mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"

# Clone customer repo if specified
[[ -n "$CUSTOMER" ]] && clone_customer_repo

# Start with realm.yaml as base
REALM_FILE="$CONFIG_DIR/realm.yaml"
[[ ! -s "$REALM_FILE" ]] && error "Missing or empty realm.yaml in $CONFIG_DIR"
cp "$REALM_FILE" "$MERGED_REALM"

# Merge base configuration
info "Merging base configuration..."
for file in "${PROCESSING_ORDER[@]}"; do
  merge_yaml_file "$file" "$CONFIG_DIR" "base"
done

# Merge customer configuration
if [[ -n "$CUSTOMER_CONFIG_DIR" ]]; then
  info "Merging customer configuration..."
  for file in "${PROCESSING_ORDER[@]}"; do
    merge_yaml_file "$file" "$CUSTOMER_CONFIG_DIR" "customer"
  done
fi

# Cleanup
[[ -n "$CUSTOMER" ]] && rm -rf "$CUSTOMER_CLONE_DIR"

echo ""
success "Build complete!"
echo "  Product:  $PRODUCT"
[[ -n "$CUSTOMER" ]] && echo "  Customer: $CUSTOMER"
echo "  Output:   $MERGED_REALM"