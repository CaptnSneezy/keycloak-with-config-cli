#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <tag>"
    exit 1
fi

TAG="$1"
IMAGE="atrdocker01.atr.local:7444/keycloak:$TAG"

echo "Building image: $IMAGE"
docker build \
    -t "$IMAGE" \
    --label "git.commit.hash=${BUILD_SOURCEVERSION:-unknown}" \
    --label "git.commit.branch=${BUILD_SOURCEBRANCHNAME:-unknown}" \
    "."
