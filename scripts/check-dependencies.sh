#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MISSING_DEPS=0

# Check yq
if ! command -v yq &>/dev/null; then
    echo -e "${RED}[x] yq is not installed${NC}"
    echo "    Install: https://github.com/mikefarah/yq"
    MISSING_DEPS=1
else
    YQ_VERSION=$(yq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    YQ_MAJOR=$(echo "$YQ_VERSION" | cut -d. -f1)
    
    if [[ "$YQ_MAJOR" -lt 4 ]]; then
        echo -e "${RED}[x] yq v$YQ_VERSION is too old (requires v4+)${NC}"
        MISSING_DEPS=1
    else
        echo -e "${GREEN}[ok] yq v$YQ_VERSION${NC}"
    fi
fi

# Check jq
if ! command -v jq &>/dev/null; then
    echo -e "${RED}[x] jq is not installed${NC}"
    echo "    Install: https://jqlang.github.io/jq/download/"
    MISSING_DEPS=1
else
    JQ_VERSION=$(jq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    echo -e "${GREEN}[ok] jq $JQ_VERSION${NC}"
fi

# Check docker
if ! command -v docker &>/dev/null; then
    echo -e "${YELLOW}[!] docker is not installed${NC}"
    echo "    Install: https://docs.docker.com/get-docker/"
else
    DOCKER_VERSION=$(docker --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo -e "${GREEN}[ok] docker $DOCKER_VERSION${NC}"
fi

# Check git
if ! command -v git &>/dev/null; then
    echo -e "${YELLOW}[!] git is not installed${NC}"
else
    GIT_VERSION=$(git --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo -e "${GREEN}[ok] git $GIT_VERSION${NC}"
fi

if [[ $MISSING_DEPS -eq 1 ]]; then
    echo ""
    echo -e "${RED}Missing required dependencies.${NC}"
    exit 1
fi
