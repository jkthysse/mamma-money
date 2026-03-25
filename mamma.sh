#!/bin/bash
# mamma.sh — unified operator script for mamma-money

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_SCRIPT="${SCRIPT_DIR}/ops/environment.sh"

if [[ ! -f "${ENV_SCRIPT}" ]]; then
  echo "Error: ${ENV_SCRIPT} not found."
  exit 1
fi

source "${ENV_SCRIPT}"

DOCKERFILE="${DOCKERFILE:-src/Dockerfile}"
BASE_URL="${HOST_PROTOCOL}://${HOST_SERVER_NAME}:${HOST_PORT}"

BOLD="\033[1m"
DIM="\033[2m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
RESET="\033[0m"

_header() {
  clear
  echo -e "${BOLD}${BLUE}"
  echo "  ╔══════════════════════════════════════╗"
  echo "  ║          mamma-money  devtools       ║"
  echo "  ╚══════════════════════════════════════╝"
  echo -e "${RESET}"
  echo -e "  ${DIM}Image:${RESET} ${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}   ${DIM}Port:${RESET} ${HOST_PORT}   ${DIM}Platform:${RESET} ${TARGET_PLATFORM}"
  echo ""
}

_step()    { echo -e "\n${CYAN}▶  $*${RESET}"; }
_ok()      { echo -e "${GREEN}✔  $*${RESET}"; }
_err()     { echo -e "${RED}✘  $*${RESET}"; }
_warn()    { echo -e "${YELLOW}⚠  $*${RESET}"; }
_dim()     { echo -e "${DIM}   $*${RESET}"; }
_divider() { echo -e "${DIM}   ────────────────────────────────────${RESET}"; }

_pause() {
  echo ""
  echo -en "${DIM}   Press Enter to return to the menu...${RESET}"
  read -r
}

_require() {
  local cmd="$1" hint="${2:-}"
  if ! command -v "$cmd" &>/dev/null; then
    _err "Required tool not found: ${cmd}"
    [[ -n "$hint" ]] && _dim "$hint"
    return 1
  fi
}

do_build() {
  _require docker "Install Docker Desktop and enable BuildKit"

  _step "Building image"
  _dim  "dockerfile : ${DOCKERFILE}"
  _dim  "context    : ${DOCKER_BUILD_CONTEXT}"
  _dim  "platform   : ${TARGET_PLATFORM}"
  _dim  "tag        : ${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}"
  _divider

  docker buildx build \
    --platform "${TARGET_PLATFORM}" \
    -f "${DOCKERFILE}" \
    -t "${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}" \
    --build-arg ENVIRONMENT="${ENVIRONMENT}" \
    --load \
    "${DOCKER_BUILD_CONTEXT}"

  _ok "Image ready: ${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}"
}

do_run() {
  _require docker

  _step "Starting container"
  _dim  "image : ${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}"
  _dim  "url   : ${BASE_URL}"
  _divider
  _warn "Running in the foreground — press Ctrl+C to stop."
  echo ""

  docker run --rm \
    --name "${CONTAINER_NAME}" \
    -p "${HOST_PORT}:${HOST_PORT}" \
    -e PORT="${HOST_PORT}" \
    "${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}"
}

do_verify() {
  _require curl

  _step "Verifying endpoints at ${BASE_URL}"
  _divider

  local all_ok=true
  local status

  _check() {
    local path="$1" expected="${2:-200}"
    status=$(curl -s -o /dev/null -w "%{http_code}" \
      --max-time 5 "${BASE_URL}${path}" 2>/dev/null || echo "000")
    if [[ "${status}" == "${expected}" ]]; then
      _ok  "GET ${path} -> HTTP ${status}"
    else
      _err "GET ${path} -> HTTP ${status} (expected ${expected})"
      all_ok=false
    fi
  }

  _check "/"
  _check "/healthz"
  _divider

  if [[ "${all_ok}" == "true" ]]; then
    _ok "All checks passed"
  else
    _err "Some checks failed. Is the container running?"
    return 1
  fi
}

do_cluster() {
  _require k3d "Install k3d: https://k3d.io"

  local cluster_name="${CLUSTER_NAME:-mamma-money}"
  local servers="${CLUSTER_SERVERS:-1}"
  local agents="${CLUSTER_AGENTS:-0}"
  local host_port="${HOST_PORT:-8080}"
  local node_port="${NODE_PORT:-30080}"

  if k3d cluster list | grep -q "^${cluster_name} "; then
    _warn "Cluster '${cluster_name}' already exists — skipping creation."
    return 0
  fi

  _step "Creating k3d cluster"
  _dim  "name      : ${cluster_name}"
  _dim  "servers   : ${servers}"
  _dim  "agents    : ${agents}"
  if [[ -n "${host_port}" ]]; then
    _dim  "port      : host ${host_port} → node ${node_port}"
  else
    _dim  "port      : none (use kubectl port-forward)"
  fi
  _dim  "disabled  : traefik, metrics-server"
  _divider

  local port_args=()
  if [[ -n "${host_port}" ]]; then
    local target="server:0"
    [[ "${agents}" -gt 0 ]] && target="agent:0"
    port_args=(--port "${host_port}:${node_port}@${target}")
  fi

  k3d cluster create "${cluster_name}" \
    --servers "${servers}" \
    --agents "${agents}" \
    "${port_args[@]}" \
    --k3s-arg "--disable=traefik@server:0" \
    --k3s-arg "--disable=metrics-server@server:0"

  _ok "Cluster ready"
}

do_deploy() {
  _require k3d  "Install k3d: https://k3d.io"
  _require helm "Install Helm: https://helm.sh"

  local cluster_name="${CLUSTER_NAME:-mamma-money}"
  local chart="${SCRIPT_DIR}/src/helm/mamma-money-api"
  local values_local="${chart}/values.local.yaml"
  local node_port="${NODE_PORT:-30080}"

  if ! k3d cluster list | grep -q "^${cluster_name} "; then
    _err "Cluster '${cluster_name}' not found — run: bash ./mamma.sh cluster"
    return 1
  fi

  _step "Importing image into k3d cluster"
  _dim  "image   : ${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}"
  _dim  "cluster : ${cluster_name}"
  _divider
  k3d image import "${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}" -c "${cluster_name}"

  _step "Deploying Helm chart"
  _dim  "chart     : ${chart}"
  _dim  "values    : values.yaml + values.local.yaml"
  _dim  "node port : ${node_port}"
  _divider
  helm dependency build "${chart}"
  helm upgrade --install mamma-money-api "${chart}" \
    -f "${values_local}" \
    --set service.nodePort="${node_port}" \
    --set image.tag="${DOCKER_IMAGE_TAG}"
  _ok "Deployed — service reachable at ${BASE_URL}"
}

do_down() {
  _require k3d "Install k3d: https://k3d.io"

  local cluster_name="${CLUSTER_NAME:-mamma-money}"

  _step "Deleting k3d cluster '${cluster_name}'"
  _warn "This will remove the cluster and free all associated memory."
  _divider
  k3d cluster delete "${cluster_name}"
  _ok "Cluster deleted"
}

show_help() {
  cat <<'EOF'
Usage:
  bash ./mamma.sh <command>
  ./mamma.sh <command>

Commands:
  build     Build the Docker image
  b         Alias for build
  run       Run the Docker container (foreground)
  r         Alias for run
  verify    Smoke test / and /healthz
  v         Alias for verify
  all       Build then verify (expects container already running)
  cluster   Create the local k3d cluster (idempotent)
  deploy    Import image into k3d and install/upgrade Helm chart
  down      Delete the k3d cluster and free resources
  menu      Open interactive menu
  help      Show this help
EOF
}

menu_main() {
  while true; do
    _header
    echo -e "  ${BOLD}1)${RESET} Build"
    echo -e "  ${BOLD}2)${RESET} Run"
    echo -e "  ${BOLD}3)${RESET} Verify"
    echo -e "  ${BOLD}4)${RESET} Build -> Verify"
    echo ""
    echo -e "  ${BOLD}5)${RESET} Create k3d cluster"
    echo -e "  ${BOLD}6)${RESET} Deploy to k3d"
    echo -e "  ${BOLD}7)${RESET} Down k3d cluster"
    echo ""
    echo -e "  ${BOLD}q)${RESET} Quit"
    echo ""
    echo -en "  ${BOLD}Choose: ${RESET}"
    read -r choice

    case "${choice}" in
      1) do_build; _pause ;;
      2) do_run; _pause ;;
      3) do_verify; _pause ;;
      4) do_build && do_verify; _pause ;;
      5) do_cluster; _pause ;;
      6) do_deploy; _pause ;;
      7) do_down; _pause ;;
      q|Q)
        echo -e "\n${DIM}  Bye.${RESET}\n"
        exit 0
        ;;
      *) _warn "Unknown option"; _pause ;;
    esac
  done
}

main() {
  local cmd="${1:-menu}"
  case "${cmd}" in
    build|b) do_build ;;
    run|r) do_run ;;
    verify|v) do_verify ;;
    all) do_build; do_verify ;;
    cluster) do_cluster ;;
    deploy) do_deploy ;;
    down) do_down ;;
    menu) menu_main ;;
    help|-h|--help) show_help ;;
    *)
      _err "Unknown command: ${cmd}"
      show_help
      return 1
      ;;
  esac
}

main "${1:-}"