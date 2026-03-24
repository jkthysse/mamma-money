#!/bin/bash
set -e

_OPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${_OPS_DIR}/.env"
ENV_EXAMPLE_FILE="${_OPS_DIR}/.env.example"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: .env not found. Copy ${ENV_EXAMPLE_FILE} to ${ENV_FILE} and fill in the desired configuration values:"
  echo "  cp \"${ENV_EXAMPLE_FILE}\" \"${ENV_FILE}\""
  exit 1
fi

source "${ENV_FILE}"