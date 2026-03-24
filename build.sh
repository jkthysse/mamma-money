#!/bin/bash
set -e

PLATFORM=${1:-linux/amd64}
IMAGE=${2:-hello-world:local}

docker buildx build \
  --platform "$PLATFORM" \
  -f src/Dockerfile \
  -t "$IMAGE" \
  --load \
  src