#!/bin/bash
# scripts/setup-portainer.sh
# Pre-flight checks and Portainer deployment for rootless Podman
#
# Usage: sudo bash scripts/setup-portainer.sh [--skip-checks]
#
# Options:
#   --skip-checks   Skip pre-flight user existence checks and go straight
#                   to Portainer installation.

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

PORTAINER_IMAGE="docker.io/portainer/portainer-ce:latest"
PORTAINER_CONTAINER="portainer"
PORTAINER_VOLUME="portainer_data"
PORTAINER_HTTP_PORT="8000"
PORTAINER_HTTPS_PORT="9443"
SKIP_CHECKS=false

# ============================================================================
# COLOUR HELPERS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}ℹ️  $*${NC}"; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠️  $*${NC}"; }
error()   { echo -e "${RED}❌ ERROR: $*${NC}" >&2; }
die()     { error "$*"; exit 1; }

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-checks) SKIP_CHECKS=true; shift ;;
        --help|-h)
            echo "Usage: sudo bash $0 [--skip-checks]"
            echo ""
            echo "Options:"
            echo "  --skip-checks   Skip user pre-flight checks"
            echo "  --help          Show this help and exit"
            exit 0
            ;;
        *) die "Unknown option: $1  (run with --help)" ;;
    esac
done

# ============================================================================
# STEP 1 — ROOTLESS CHECK
# ============================================================================

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║       NEXTCLOUD — PORTAINER SETUP FOR PODMAN (ROOTLESS)     ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$EUID" -eq 0 ]; then
    die "This script must NOT be run as root. Run it as the regular user."
fi
success "Running as unprivileged user."

# ============================================================================
# STEP 2 — PRE-FLIGHT CHECKS
# ============================================================================

if ! "$SKIP_CHECKS"; then
    info "Step 2/5 — Pre-flight checks..."

    if ! command -v podman &>/dev/null; then
        die "Podman is not installed. Install it before running this script."
    fi
    success "Podman $(podman --version | cut -d' ' -f3) found."
else
    info "Step 2/5 — Pre-flight checks skipped (--skip-checks)."
fi

# ============================================================================
# STEP 3 — ENABLE PODMAN SOCKET
# ============================================================================

info "Step 3/5 — Enabling rootless user Podman API socket..."

if systemctl --user is-active --quiet podman.socket 2>/dev/null; then
    success "podman.socket is already active for this user."
else
    if systemctl --user enable --now podman.socket 2>/dev/null; then
        success "podman.socket enabled and started for rootless user."
    else
        warn "Could not enable podman.socket via systemd. Portainer will still be deployed;"
        warn "verify the socket path manually if the container cannot reach the Podman API."
    fi
fi

# ============================================================================
# STEP 4 — DEPLOY PORTAINER
# ============================================================================

info "Step 4/5 — Deploying Portainer..."

# Remove a stopped/failed container with the same name, if present
if podman container exists "$PORTAINER_CONTAINER" 2>/dev/null; then
    CONTAINER_STATUS="$(podman inspect --format '{{.State.Status}}' "$PORTAINER_CONTAINER" 2>/dev/null || echo "unknown")"
    if [ "$CONTAINER_STATUS" = "running" ]; then
        success "Portainer container is already running. Nothing to do."
        PORTAINER_ALREADY_RUNNING=true
    else
        warn "Removing existing stopped Portainer container..."
        podman rm "$PORTAINER_CONTAINER"
        PORTAINER_ALREADY_RUNNING=false
    fi
else
    PORTAINER_ALREADY_RUNNING=false
fi

# Create persistent data volume (idempotent)
if ! podman volume exists "$PORTAINER_VOLUME" 2>/dev/null; then
    podman volume create "$PORTAINER_VOLUME"
    success "Created Portainer data volume: $PORTAINER_VOLUME"
fi

if [ "$PORTAINER_ALREADY_RUNNING" = "false" ]; then
    # Determine correct socket path for rootless podman
    USER_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$EUID}"
    SOCKET_PATH="${USER_RUNTIME_DIR}/podman/podman.sock"

    if [ ! -S "$SOCKET_PATH" ]; then
        warn "Rootless Podman socket not found at $SOCKET_PATH."
        warn "Make sure you started podman.socket: 'systemctl --user start podman.socket'"
    fi

    podman run -d \
        -p "${PORTAINER_HTTP_PORT}:8000" \
        -p "${PORTAINER_HTTPS_PORT}:9443" \
        --name "$PORTAINER_CONTAINER" \
        --restart=always \
        -v "${SOCKET_PATH}:/var/run/docker.sock:Z" \
        -v "${PORTAINER_VOLUME}:/data:Z" \
        "$PORTAINER_IMAGE"

    success "Portainer container started."
fi

# ============================================================================
# STEP 5 — SUMMARY
# ============================================================================

info "Step 5/5 — Summary."

# Resolve host IP for convenience
HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "$HOST_IP" ] && HOST_IP="<YOUR_SERVER_IP>"

echo ""
echo -e "${GREEN}Portainer has been deployed successfully!${NC}"
echo ""
echo "  Web UI (HTTPS):    https://${HOST_IP}:${PORTAINER_HTTPS_PORT}"
echo "  Edge Agent / API:  https://${HOST_IP}:${PORTAINER_HTTP_PORT}"
echo ""
echo -e "${YELLOW}First-run actions:${NC}"
echo "  1. Open https://${HOST_IP}:${PORTAINER_HTTPS_PORT} in your browser."
echo "  2. Accept the self-signed certificate warning."
echo "  3. Create the initial administrator account."
echo "  4. Select 'Get Started' to manage the local environment."
echo "  5. Go to Stacks → Add stack → paste your docker-compose / podman-compose file."
echo "  6. Load environment variables from your .env.secure file."
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "  Check status:   podman ps --filter name=${PORTAINER_CONTAINER}"
echo "  View logs:      podman logs -f ${PORTAINER_CONTAINER}"
echo "  Stop:           podman stop ${PORTAINER_CONTAINER}"
echo "  Start:          podman start ${PORTAINER_CONTAINER}"
echo ""
