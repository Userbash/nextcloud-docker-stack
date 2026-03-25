#!/bin/bash
# =============================================================================
# Nextcloud Docker Stack — One-Click Setup Script
# =============================================================================
#
# USAGE
#   bash setup.sh [OPTIONS]
#
# OPTIONS
#   --domain <domain>     Set the Nextcloud domain (e.g. cloud.example.com)
#   --email  <email>      Let's Encrypt notification e-mail
#   --dev                 Use development/local mode (no SSL, localhost only)
#   --skip-start          Prepare config but do not start containers
#   --rootless            Use rootless Podman instead of Docker
#   --help                Show this help and exit
#
# EXAMPLES
#   # Minimal local test — everything on localhost
#   bash setup.sh --dev
#
#   # Production with SSL
#   bash setup.sh --domain cloud.example.com --email admin@example.com
#
#   # Prepare config only, start containers manually later
#   bash setup.sh --dev --skip-start
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}ℹ  $*${NC}"; }
success() { echo -e "${GREEN}✔  $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠  $*${NC}"; }
error()   { echo -e "${RED}✖  $*${NC}" >&2; }
die()     { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         NEXTCLOUD DOCKER STACK — ONE-CLICK SETUP            ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
DOMAIN=""
EMAIL=""
DEV_MODE=false
SKIP_START=false
ROOTLESS=false

usage() {
    sed -n '/^# USAGE/,/^# =\{10\}/p' "$0" | grep -v "^# ===" | sed 's/^# //'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)  DOMAIN="$2";  shift 2 ;;
        --email)   EMAIL="$2";   shift 2 ;;
        --dev)     DEV_MODE=true; shift  ;;
        --skip-start) SKIP_START=true; shift ;;
        --rootless) ROOTLESS=true; shift ;;
        --help|-h) usage ;;
        *) die "Unknown option: $1  (run with --help)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Resolve project root (the directory this script lives in)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

print_banner
info "Working directory: $SCRIPT_DIR"

# ===========================================================================
# STEP 1 — CHECK PREREQUISITES
# ===========================================================================
echo ""
info "Step 1/6 — Checking prerequisites..."

check_command() {
    if command -v "$1" &>/dev/null; then
        success "$1 found ($(command -v "$1"))"
        return 0
    else
        return 1
    fi
}

# Detect container runtime
RUNTIME=""
COMPOSE_CMD=""

if $ROOTLESS; then
    if ! check_command podman; then
        die "podman not found. Install it or omit --rootless."
    fi
    RUNTIME="podman"
    check_command podman-compose && COMPOSE_CMD="podman-compose" \
        || { check_command podman && COMPOSE_CMD="podman compose" ; } \
        || die "podman-compose not found. Install it: pip install podman-compose"
else
    if check_command docker; then
        RUNTIME="docker"
        if check_command docker-compose; then
            COMPOSE_CMD="docker-compose"
        elif docker compose version &>/dev/null; then
            COMPOSE_CMD="docker compose"
            success "docker compose (plugin) found"
        else
            die "docker-compose not found. Install Docker Compose v2: https://docs.docker.com/compose/install/"
        fi
    elif check_command podman; then
        RUNTIME="podman"
        if check_command podman-compose; then
            COMPOSE_CMD="podman-compose"
        else
            die "podman-compose not found. Install it: pip install podman-compose"
        fi
    else
        die "Neither Docker nor Podman found. Install Docker: https://docs.docker.com/engine/install/"
    fi
fi

# Check Docker daemon is running (Docker only)
if [ "$RUNTIME" = "docker" ]; then
    if ! docker info &>/dev/null; then
        die "Docker daemon is not running. Start it with: sudo systemctl start docker"
    fi
    success "Docker daemon is running"
fi

# Check Podman unqualified-search-registries (Podman only)
if [ "$RUNTIME" = "podman" ]; then
    _reg_ok=false
    for _conf in /etc/containers/registries.conf \
                 "${XDG_CONFIG_HOME:-$HOME/.config}/containers/registries.conf"; do
        if [ -f "$_conf" ] && grep -qE '^[[:space:]]*unqualified-search-registries[[:space:]]*=' "$_conf" 2>/dev/null; then
            _reg_ok=true
            break
        fi
    done
    if ! $_reg_ok; then
        warn "Podman: unqualified-search-registries not configured."
        warn "Image pulls may fail with 'short-name did not resolve to an alias'."
        warn "System fix:  echo 'unqualified-search-registries = [\"docker.io\"]' | sudo tee -a /etc/containers/registries.conf"
        warn "Project fix: all images in docker-compose.yaml already use fully-qualified names (docker.io/library/...)."
    else
        success "Podman unqualified-search-registries configured"
    fi
fi

# Check optional tools
for tool in openssl curl git; do
    check_command "$tool" || warn "$tool not found — some features may not work"
done

success "Prerequisites check passed"

# ===========================================================================
# STEP 2 — CONFIGURE ENVIRONMENT
# ===========================================================================
echo ""
info "Step 2/6 — Configuring environment..."

ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    if [ ! -f "$SCRIPT_DIR/.env.example" ]; then
        die ".env.example not found. Repository may be incomplete."
    fi
    cp "$SCRIPT_DIR/.env.example" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    success "Created .env from .env.example (permissions: 600)"
else
    success ".env already exists — keeping existing configuration"
    PERMS="$(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE" 2>/dev/null || echo 'unknown')"
    if [ "$PERMS" != "600" ]; then
        chmod 600 "$ENV_FILE"
        warn ".env permissions fixed to 600"
    else
        success ".env permissions OK (600)"
    fi
fi

# Apply user-supplied overrides
apply_env_override() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "$ENV_FILE"; then
        # sed -i requires an empty string on macOS, no argument on Linux
        if sed --version 2>/dev/null | grep -q GNU; then
            sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        else
            sed -i '' "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        fi
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

if [ -n "$DOMAIN" ]; then
    apply_env_override "NEXTCLOUD_DOMAIN" "$DOMAIN"
    apply_env_override "NEXTCLOUD_TRUSTED_DOMAINS" "${DOMAIN},www.${DOMAIN}"
    success "Domain set to: $DOMAIN"
fi

if [ -n "$EMAIL" ]; then
    apply_env_override "LETSENCRYPT_EMAIL" "$EMAIL"
    success "Let's Encrypt email set to: $EMAIL"
fi

if $DEV_MODE; then
    apply_env_override "NEXTCLOUD_DOMAIN" "localhost"
    apply_env_override "NEXTCLOUD_TRUSTED_DOMAINS" "localhost,127.0.0.1"
    apply_env_override "OVERWRITEPROTOCOL" "http"
    success "Development mode: domain set to localhost"
fi

# Warn about default passwords
if grep -qE "^(POSTGRES_PASSWORD|NEXTCLOUD_ADMIN_PASSWORD)=CHANGE_ME" "$ENV_FILE"; then
    warn "Default passwords detected in .env — change them before using in production!"
    warn "Edit $ENV_FILE and replace all CHANGE_ME values."
    echo ""
fi

# ===========================================================================
# STEP 3 — CREATE REQUIRED DIRECTORIES
# ===========================================================================
echo ""
info "Step 3/6 — Creating required directories..."

for dir in config/ssl config/webroot backups logs; do
    mkdir -p "$SCRIPT_DIR/$dir"
    success "Directory ready: $dir/"
done

# ===========================================================================
# STEP 4 — SET SCRIPT PERMISSIONS
# ===========================================================================
echo ""
info "Step 4/6 — Setting script permissions..."

find "$SCRIPT_DIR/scripts" -maxdepth 1 -name "*.sh" -type f -exec chmod +x {} \;
chmod +x "$SCRIPT_DIR/FIRST_STEPS.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/tests/run_tests.sh" 2>/dev/null || true
success "All scripts are now executable"

# ===========================================================================
# STEP 5 — (OPTIONAL) GENERATE SELF-SIGNED CERT FOR DEV MODE
# ===========================================================================
if $DEV_MODE; then
    echo ""
    info "Step 5/6 — Generating self-signed certificate for development..."
    CERT_DIR="$SCRIPT_DIR/config/ssl"
    if [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
        if command -v openssl &>/dev/null; then
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$CERT_DIR/privkey.pem" \
                -out "$CERT_DIR/fullchain.pem" \
                -subj "/C=US/ST=Dev/L=Dev/O=Dev/CN=localhost" \
                2>/dev/null
            chmod 600 "$CERT_DIR/privkey.pem"
            success "Self-signed certificate created (valid 365 days)"
        else
            warn "openssl not found — skipping certificate generation (HTTPS may not work)"
        fi
    else
        success "SSL certificate already present"
    fi
else
    info "Step 5/6 — Skipping certificate generation (production mode uses Let's Encrypt)"
fi

# ===========================================================================
# STEP 6 — START CONTAINERS
# ===========================================================================
echo ""
info "Step 6/6 — Starting containers..."

if $SKIP_START; then
    warn "--skip-start flag set — skipping container start"
    echo ""
    success "Setup complete! Start manually with:"
    echo "    $COMPOSE_CMD up -d"
    exit 0
fi

# Choose the right compose file
COMPOSE_FILE="docker-compose.yaml"
if $ROOTLESS && [ -f "$SCRIPT_DIR/docker-compose.rootless.yaml" ]; then
    COMPOSE_FILE="docker-compose.rootless.yaml"
    info "Using rootless compose file: $COMPOSE_FILE"
fi

cd "$SCRIPT_DIR"
info "Pulling latest images (this may take a minute on first run)..."
$COMPOSE_CMD -f "$COMPOSE_FILE" pull --quiet 2>/dev/null || warn "Image pull failed — will use cached images"

info "Starting containers in the background..."
$COMPOSE_CMD -f "$COMPOSE_FILE" up -d

# ===========================================================================
# WAIT FOR CONTAINERS TO BECOME HEALTHY
# ===========================================================================
echo ""
info "Waiting for services to become healthy (up to 60 seconds)..."
MAX_WAIT=60
WAITED=0
SLEEP=5

while [ $WAITED -lt $MAX_WAIT ]; do
    # Count running containers
    UP=$($COMPOSE_CMD -f "$COMPOSE_FILE" ps 2>/dev/null | grep -c " Up\| running" || true)
    if [ "$UP" -ge 3 ]; then
        break
    fi
    sleep $SLEEP
    WAITED=$((WAITED + SLEEP))
    echo -n "."
done
echo ""

# ===========================================================================
# SHOW FINAL STATUS
# ===========================================================================
echo ""
$COMPOSE_CMD -f "$COMPOSE_FILE" ps

# ---------------------------------------------------------------------------
# Print access URL
# ---------------------------------------------------------------------------
DOMAIN_VAL=""
if [ -n "$DOMAIN" ]; then
    DOMAIN_VAL="$DOMAIN"
elif $DEV_MODE; then
    DOMAIN_VAL="localhost"
else
    DOMAIN_VAL="$(grep '^NEXTCLOUD_DOMAIN=' "$ENV_FILE" | cut -d= -f2 | tr -d ' ')"
    [ -z "$DOMAIN_VAL" ] && DOMAIN_VAL="localhost"
fi

HTTP_PORT="$(grep '^NEXTCLOUD_HTTP_PORT=' "$ENV_FILE" | cut -d= -f2 | tr -d ' ')"
HTTPS_PORT="$(grep '^NEXTCLOUD_HTTPS_PORT=' "$ENV_FILE" | cut -d= -f2 | tr -d ' ')"

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    SETUP COMPLETE ✔                         ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Nextcloud is starting up at:${NC}"
if $DEV_MODE; then
    [ -n "$HTTP_PORT" ]  && echo "    HTTP:   http://localhost:${HTTP_PORT}"
    [ -n "$HTTPS_PORT" ] && echo "    HTTPS:  https://localhost:${HTTPS_PORT}  (self-signed cert)"
else
    echo "    https://${DOMAIN_VAL}"
fi
echo ""
echo -e "${GREEN}Useful commands:${NC}"
echo "    View logs:        $COMPOSE_CMD logs -f"
echo "    Container status: $COMPOSE_CMD ps"
echo "    Stop stack:       $COMPOSE_CMD down"
echo "    Backup:           bash scripts/backup.sh"
echo "    Health check:     bash scripts/health-check.sh"
echo "    First-steps check: bash FIRST_STEPS.sh"
echo ""
echo -e "${YELLOW}Admin credentials are in .env — change defaults before going live!${NC}"
echo ""
