#!/bin/bash

source environment.sh

echo "Testing $IMAGE at http://$HOST:$PORT"

curl "http://$HOST:$PORT/"
curl "http://$HOST:$PORT/healthz"