#!/bin/bash
# mamma.sh — unified operator script for mamma-money
#
# Usage:  bash ./mamma.sh <command>
# Run without arguments to open the interactive menu.

set -euo pipefail

# ─── Bootstrap ───────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_SCRIPT="${SCRIPT_DIR}/ops/environment.sh"

if [[ ! -f "${ENV_SCRIPT}" ]]; then
  echo "Error: ${ENV_SCRIPT} not found."
  exit 1
fi

source "${ENV_SCRIPT}"

DOCKERFILE="${DOCKERFILE:-src/Dockerfile}"
BASE_URL="${HOST_PROTOCOL}://${HOST_SERVER_NAME}:${HOST_PORT}"

# ─── Logging ─────────────────────────────────────────────────────────────────
# CI=true (set automatically by GitHub Actions and most CI platforms) activates
# structured log mode: plain text, no ANSI colour, no Unicode box-drawing, and
# every line is prefixed with a log-level tag so it is easy to grep or parse.
# Interactive mode uses colour and symbols for readability.

CI="${CI:-false}"

if [[ "${CI}" == "true" ]]; then
  _step()    { echo "[INFO]  $*"; }
  _ok()      { echo "[OK]    $*"; }
  _err()     { echo "[ERROR] $*" >&2; }
  _warn()    { echo "[WARN]  $*"; }
  _dim()     { echo "[INFO]  $*"; }
  _divider() { :; }
  _header()  { :; }
  _pause()   { :; }
else
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
  _err()     { echo -e "${RED}✘  $*${RESET}" >&2; }
  _warn()    { echo -e "${YELLOW}⚠  $*${RESET}"; }
  _dim()     { echo -e "${DIM}   $*${RESET}"; }
  _divider() { echo -e "${DIM}   ────────────────────────────────────${RESET}"; }

  _pause() {
    echo ""
    echo -en "${DIM}   Press Enter to return to the menu...${RESET}"
    read -r
  }
fi

# ─── Preflight helpers ────────────────────────────────────────────────────────

# Abort if a required tool is missing.
_require() {
  local cmd="$1" hint="${2:-}"
  if ! command -v "$cmd" &>/dev/null; then
    _err "Required tool not found: ${cmd}"
    [[ -n "$hint" ]] && _dim "$hint"
    return 1
  fi
}

# Abort if the Docker daemon is not reachable.
_require_docker_daemon() {
  if ! docker info &>/dev/null; then
    _err "Docker daemon is not running or not reachable."
    _dim "Start Docker Desktop (or the Docker service) and try again."
    return 1
  fi
}

# Abort if HOST_PORT is already bound on the host.
_require_port_free() {
  local port="${HOST_PORT}"
  # Use ss if available (Linux), fall back to lsof (macOS/Linux).
  if command -v ss &>/dev/null; then
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
      _err "Port ${port} is already in use."
      _dim "Change HOST_PORT in ops/.env or stop the process using that port."
      return 1
    fi
  elif command -v lsof &>/dev/null; then
    if lsof -iTCP:"${port}" -sTCP:LISTEN &>/dev/null; then
      _err "Port ${port} is already in use."
      _dim "Change HOST_PORT in ops/.env or stop the process using that port."
      return 1
    fi
  fi
  # If neither tool is available we skip the check rather than blocking.
}

# ─── Commands ─────────────────────────────────────────────────────────────────

do_build() {
  _require docker "Install Docker Desktop and enable BuildKit: curl -fsSL https://get.docker.com | bash"
  _require_docker_daemon

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

# run — foreground, container removed on exit (Ctrl+C).
do_run() {
  _require docker "Install Docker Desktop and enable BuildKit: curl -fsSL https://get.docker.com | bash"
  _require_docker_daemon
  _require_port_free

  _step "Starting container (foreground)"
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

# run-bg — detached; use `stop` to remove it.
do_run_bg() {
  _require docker "Install Docker Desktop and enable BuildKit: curl -fsSL https://get.docker.com | bash"
  _require_docker_daemon 
  _require_port_free

  _step "Starting container (detached)"
  _dim  "image : ${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}"
  _dim  "url   : ${BASE_URL}"
  _dim  "name  : ${CONTAINER_NAME}"
  _divider

  docker run -d \
    --name "${CONTAINER_NAME}" \
    -p "${HOST_PORT}:${HOST_PORT}" \
    -e PORT="${HOST_PORT}" \
    "${DOCKER_IMAGE}:${DOCKER_IMAGE_TAG}"

  _ok "Container started. Run 'bash ./mamma.sh verify' to check endpoints."
  _ok "Run 'bash ./mamma.sh stop' to remove it."
}

# stop — stops and removes the named container started by run-bg.
do_stop() {
  _require docker "Install Docker Desktop and enable BuildKit: curl -fsSL https://get.docker.com | bash"
  _require_docker_daemon

  _step "Stopping container '${CONTAINER_NAME}'"
  _divider

  if ! docker ps -q --filter "name=^${CONTAINER_NAME}$" | grep -q .; then
    _warn "Container '${CONTAINER_NAME}' is not running — nothing to stop."
    return 0
  fi

  docker stop "${CONTAINER_NAME}"
  docker rm   "${CONTAINER_NAME}" 2>/dev/null || true
  _ok "Container stopped and removed."
}

do_verify() {
  _require curl "Install Curl: https://curl.se/"

  _step "Verifying endpoints at ${BASE_URL}"
  _divider

  local all_ok=true

  _check() {
    local path="$1" expected="${2:-200}"
    local status
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

# status — quick node and pod health overview for the k3d cluster.
do_status() {
  _require kubectl "Install kubectl: https://kubernetes.io/docs/tasks/tools/"

  local cluster_name="${CLUSTER_NAME:-mamma-money}"
  local context="k3d-${cluster_name}"

  _step "Cluster status: ${cluster_name}"
  _divider

  if ! kubectl --context "${context}" cluster-info &>/dev/null; then
    _err "Cannot reach cluster '${cluster_name}'. Is it running? (bash ./mamma.sh cluster)"
    return 1
  fi

  _dim "Nodes"
  kubectl --context "${context}" get nodes \
    -o wide \
    --no-headers \
    | awk '{
        status = $2; name = $1; role = $3; version = $5; os = $9
        icon = (status == "Ready") ? "✔" : "✘"
        printf "   %s  %-28s  %-12s  %-8s  %s\n", icon, name, role, status, version
      }'

  echo ""
  _dim "Pods (all namespaces)"
  kubectl --context "${context}" get pods \
    --all-namespaces \
    --no-headers \
    | awk '{
        ns = $1; name = $2; ready = $3; status = $4; restarts = $5
        icon = (status == "Running" || status == "Completed") ? "✔" : "✘"
        printf "   %s  %-20s  %-36s  %-12s  ready: %s  restarts: %s\n", \
          icon, ns, name, status, ready, restarts
      }'

  echo ""
  _dim "Services"
  kubectl --context "${context}" get svc \
    --all-namespaces \
    --no-headers \
    | awk '{
        printf "   %-20s  %-28s  %-12s  %s\n", $1, $2, $3, $5
      }'

  _divider
  _ok "Status complete"
}

# ─── Help ─────────────────────────────────────────────────────────────────────

show_help() {
  cat <<'EOF'
Usage:
  bash ./mamma.sh <command>
  ./mamma.sh <command>

Docker commands:
  build       Build the Docker image
  b           Alias for build
  run         Run the container in the foreground (Ctrl+C to stop)
  r           Alias for run
  run-bg      Run the container detached in the background
  stop        Stop and remove the detached container
  verify      Smoke test / and /healthz
  v           Alias for verify
  all         Build then verify (expects container already running)

Kubernetes commands:
  cluster     Create the local k3d cluster (idempotent)
  deploy      Import image into k3d and install/upgrade Helm chart
  down        Delete the k3d cluster and free resources
  status      Show node, pod, and service health for the k3d cluster

General:
  menu        Open interactive menu
  help        Show this help

Environment:
  Set CI=true to activate structured log output (plain text, [LEVEL] prefixes).
  GitHub Actions sets this automatically.
EOF
}

# ─── Interactive menu ──────────────────────────────────────────────────────────

menu_main() {
  while true; do
    _header
    echo -e "  ${BOLD}Docker${RESET}"
    echo -e "  ${BOLD}1)${RESET} Build"
    echo -e "  ${BOLD}2)${RESET} Run (foreground)"
    echo -e "  ${BOLD}3)${RESET} Run in background"
    echo -e "  ${BOLD}4)${RESET} Stop background container"
    echo -e "  ${BOLD}5)${RESET} Verify"
    echo -e "  ${BOLD}6)${RESET} Build -> Verify"
    echo ""
    echo -e "  ${BOLD}Kubernetes${RESET}"
    echo -e "  ${BOLD}7)${RESET} Create k3d cluster"
    echo -e "  ${BOLD}8)${RESET} Deploy to k3d"
    echo -e "  ${BOLD}9)${RESET} Cluster status"
    echo -e "  ${BOLD}0)${RESET} Down k3d cluster"
    echo ""
    echo -e "  ${BOLD}q)${RESET} Quit"
    echo ""
    echo -en "  ${BOLD}Choose: ${RESET}"
    read -r choice

    case "${choice}" in
      1) do_build;                  _pause ;;
      2) do_run;                    _pause ;;
      3) do_run_bg;                 _pause ;;
      4) do_stop;                   _pause ;;
      5) do_verify;                 _pause ;;
      6) do_build && do_verify;     _pause ;;
      7) do_cluster;                _pause ;;
      8) do_deploy;                 _pause ;;
      9) do_status;                 _pause ;;
      0) do_down;                   _pause ;;
      q|Q)
        echo -e "\n${DIM}  Bye.${RESET}\n"
        exit 0
        ;;
      *) _warn "Unknown option"; _pause ;;
    esac
  done
}

# ─── Entry point ──────────────────────────────────────────────────────────────

main() {
  local cmd="${1:-menu}"
  case "${cmd}" in
    build|b)   do_build   ;;
    run|r)     do_run     ;;
    run-bg)    do_run_bg  ;;
    stop)      do_stop    ;;
    verify|v)  do_verify  ;;
    all)       do_build; do_verify ;;
    cluster)   do_cluster ;;
    deploy)    do_deploy  ;;
    down)      do_down    ;;
    status)    do_status  ;;
    menu)      menu_main  ;;
    help|-h|--help) show_help ;;
    *)
      _err "Unknown command: ${cmd}"
      show_help
      return 1
      ;;
  esac
}

main "${1:-}"