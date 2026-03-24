#!/bin/bash
set -e

if [[ ! -f .env ]]; then
  echo "Error: .env not found. Copy .env.example and fill in the values:"
  echo "  cp .env.example .env"
  exit 1
fi

source .env

echo "Building $IMAGE for $PLATFORM"

docker buildx build \
  --platform "${PLATFORM}" \
  -t "${IMAGE}" \
  --build-arg ENVIRONMENT="${ENVIRONMENT}" \
  --load \
  "${BUILD_CONTEXT}"