#!/bin/bash

source environment.sh

echo "Building $IMAGE for $PLATFORM"

docker buildx build \
  --platform "${PLATFORM}" \
  -t "${IMAGE}" \
  --build-arg ENVIRONMENT="${ENVIRONMENT}" \
  --load \
  "${BUILD_CONTEXT}"