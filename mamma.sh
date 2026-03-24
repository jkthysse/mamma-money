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
BASE_URL="http://${HOST}:${PORT}"

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
  echo -e "  ${DIM}Image:${RESET} ${IMAGE}   ${DIM}Port:${RESET} ${PORT}   ${DIM}Platform:${RESET} ${PLATFORM}"
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
  _dim  "context    : ${BUILD_CONTEXT}"
  _dim  "platform   : ${PLATFORM}"
  _dim  "tag        : ${IMAGE}"
  _divider

  docker buildx build \
    --platform "${PLATFORM}" \
    -f "${DOCKERFILE}" \
    -t "${IMAGE}" \
    --build-arg ENVIRONMENT="${ENVIRONMENT}" \
    --load \
    "${BUILD_CONTEXT}"

  _ok "Image ready: ${IMAGE}"
}

do_run() {
  _require docker

  _step "Starting container"
  _dim  "image : ${IMAGE}"
  _dim  "url   : ${BASE_URL}"
  _divider
  _warn "Running in the foreground — press Ctrl+C to stop."
  echo ""

  docker run --rm \
    --name "${CONTAINER_NAME}" \
    -p "${PORT}:${PORT}" \
    -e PORT="${PORT}" \
    "${IMAGE}"
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

show_help() {
  cat <<'EOF'
Usage:
  bash ./mamma.sh <command>
  ./mamma.sh <command>

Commands:
  build    Build the Docker image
  b        Alias for build
  run      Run the Docker container (foreground)
  r        Alias for run
  verify   Smoke test / and /healthz
  v        Alias for verify
  all      Build then verify (expects container already running)
  menu     Open interactive menu
  help     Show this help
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
    echo -e "  ${BOLD}q)${RESET} Quit"
    echo ""
    echo -en "  ${BOLD}Choose: ${RESET}"
    read -r choice

    case "${choice}" in
      1) do_build; _pause ;;
      2) do_run; _pause ;;
      3) do_verify; _pause ;;
      4) do_build && do_verify; _pause ;;
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