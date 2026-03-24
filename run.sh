#!/bin/bash

source environment.sh

echo "Running $IMAGE on $HOST:$PORT"

docker run --rm \
  --name "$CONTAINER_NAME" \
  -p "$PORT:$PORT" \
  -e PORT="$PORT" \
  "$IMAGE"