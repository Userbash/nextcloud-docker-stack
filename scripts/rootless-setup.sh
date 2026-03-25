#!/bin/bash

###############################################################################
# NEXTCLOUD DOCKER STACK - ROOTLESS SETUP
# Configure Podman for rootless container execution
#
# Features:
#   ✅ Rootless user creation
#   ✅ Subuid/subgid configuration for user namespace isolation
#   ✅ Podman configuration for rootless mode
#   ✅ Systemd service setup for auto-start
#   ✅ Socket activation for API access
#   ✅ Comprehensive testing and verification
#
# Usage: sudo bash rootless-setup.sh
#
###############################################################################

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTLESS_USER="nextcloud-rootless"
ROOTLESS_UID=5001
ROOTLESS_GID=5001
SUBUID_START=100000
SUBUID_COUNT=65536

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    echo -e "$@"
}

log_title() {
    log "${CYAN}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    log "${CYAN}║  $1${NC}"
    log "${CYAN}╚════════════════════════════════════════════════════════════════════════╝${NC}"
}

log_section() {
    log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${BLUE}  $1${NC}"
    log "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_success() {
    log "${GREEN}✅ $1${NC}"
}

log_error() {
    log "${RED}❌ ERROR: $1${NC}"
}

log_warning() {
    log "${YELLOW}⚠️  WARNING: $1${NC}"
}

log_info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# ============================================================================
# REQUIREMENT CHECKS
# ============================================================================

check_requirements() {
    log_section "CHECKING REQUIREMENTS"
    
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
    
    if ! command -v podman &>/dev/null; then
        log_error "Podman is not installed. Please install Podman first."
        exit 1
    fi
    
    log_success "All requirements met"
    log_info "Podman: $(podman --version)"
}

# ============================================================================
# USER CREATION
# ============================================================================

create_rootless_user() {
    log_section "STEP 1: CREATING ROOTLESS USER"
    
    if id "$ROOTLESS_USER" &>/dev/null; then
        log_info "User $ROOTLESS_USER already exists (UID: $(id -u "$ROOTLESS_USER"))"
        return
    fi
    
    log_info "Creating rootless user: $ROOTLESS_USER"
    useradd -m -u "$ROOTLESS_UID" -s /bin/bash -c "Rootless Container User" "$ROOTLESS_USER"
    
    log_success "User created: $ROOTLESS_USER"
    log_info "Home directory: /home/$ROOTLESS_USER"
}

# ============================================================================
# SUBUID/SUBGID CONFIGURATION
# ============================================================================

configure_subuid_subgid() {
    log_section "STEP 2: CONFIGURING SUBUID/SUBGID"
    
    # Check if already configured
    if grep -q "^${ROOTLESS_USER}:" /etc/subuid 2>/dev/null; then
        log_info "User namespace already configured for $ROOTLESS_USER"
        log_info "SUBUID: $(grep "^${ROOTLESS_USER}:" /etc/subuid)"
        log_info "SUBGID: $(grep "^${ROOTLESS_USER}:" /etc/subgid)"
        return
    fi
    
    log_info "Adding subuid/subgid entries..."
    echo "${ROOTLESS_USER}:${SUBUID_START}:${SUBUID_COUNT}" >> /etc/subuid
    echo "${ROOTLESS_USER}:${SUBUID_START}:${SUBUID_COUNT}" >> /etc/subgid
    
    log_success "Subuid/subgid configured"
    log_info "UID mapping: ${SUBUID_START}-$((SUBUID_START + SUBUID_COUNT - 1))"
}

# ============================================================================
# DIRECTORY SETUP
# ============================================================================

setup_directories() {
    log_section "STEP 3: CREATING DIRECTORIES"
    
    local home_dir="/home/${ROOTLESS_USER}"
    local config_dir="${home_dir}/.config/containers"
    local storage_dir="${home_dir}/.local/share/containers"
    local socket_dir="/run/user/${ROOTLESS_UID}/podman"
    
    # Create directories
    mkdir -p "$config_dir" "$storage_dir" "$socket_dir"
    chown -R "${ROOTLESS_UID}:${ROOTLESS_GID}" "$home_dir"
    chmod 700 "$home_dir"
    
    log_success "Directories created:"
    log_info "- Config: $config_dir"
    log_info "- Storage: $storage_dir"
    log_info "- Socket: $socket_dir"
}

# ============================================================================
# PODMAN CONFIGURATION
# ============================================================================

configure_podman() {
    log_section "STEP 4: CONFIGURING PODMAN"
    
    local home_dir="/home/${ROOTLESS_USER}"
    local config_dir="${home_dir}/.config/containers"
    local storage_dir="${home_dir}/.local/share/containers/storage"
    
    # Create registries.conf
    cat > "${config_dir}/registries.conf" << 'EOF'
[[registry]]
location = "docker.io"
insecure = false

[[registry]]
location = "quay.io"
insecure = false
EOF
    
    # Create storage.conf
    cat > "${config_dir}/storage.conf" << EOF
[storage]
driver = "overlay"
graphroot = "${storage_dir}"

[storage.options]
mount_program = "/usr/bin/fuse-overlayfs"
additionalimagestores = []
EOF
    
    # Create podman.conf
    cat > "${config_dir}/podman.conf" << EOF
[engine]
cgroup_manager = "systemd"
events_backend = "journald"
network_backend = "netavark"
EOF
    
    chown -R "${ROOTLESS_UID}:${ROOTLESS_GID}" "$config_dir"
    chmod 700 "$config_dir"
    
    log_success "Podman configuration created"
}

# ============================================================================
# SYSTEMD SERVICE SETUP
# ============================================================================

setup_systemd_services() {
    log_section "STEP 5: SETTING UP SYSTEMD SERVICES"
    
    local user_service_dir="/home/${ROOTLESS_USER}/.config/systemd/user"
    mkdir -p "$user_service_dir"
    
    # Create socket service
    cat > "${user_service_dir}/podman.socket" << 'EOF'
[Unit]
Description=Podman API Socket
Documentation=man:podman-system-service(1)

[Socket]
ListenStream=%t/podman/podman.sock
SocketMode=0660

[Install]
WantedBy=sockets.target
EOF
    
    # Create podman service
    cat > "${user_service_dir}/podman.service" << EOF
[Unit]
Description=Podman API Service
Requires=podman.socket
After=podman.socket
Documentation=man:podman-system-service(1)

[Service]
Type=notify
ExecStart=/usr/libexec/podman/podman system service

[Install]
WantedBy=default.target
EOF
    
    chown -R "${ROOTLESS_UID}:${ROOTLESS_GID}" "$user_service_dir"
    chmod 644 "${user_service_dir}"/*
    
    log_success "Systemd services created:"
    log_info "- podman.socket"
    log_info "- podman.service"
}

# ============================================================================
# LINGER SETUP (ENABLE AUTO-START)
# ============================================================================

enable_linger() {
    log_section "STEP 6: ENABLING LINGER FOR AUTO-START"
    
    loginctl enable-linger "$ROOTLESS_USER"
    
    log_success "Linger enabled for $ROOTLESS_USER"
    log_info "User services will start on boot"
}

# ============================================================================
# TESTING AND VERIFICATION
# ============================================================================

verify_installation() {
    log_section "STEP 7: VERIFICATION AND TESTING"
    
    # Check user
    if id "$ROOTLESS_USER" &>/dev/null; then
        log_success "User creation verified"
    else
        log_error "User creation failed"
        return 1
    fi
    
    # Check subuid
    if grep -q "^${ROOTLESS_USER}:" /etc/subuid; then
        log_success "Subuid configuration verified"
    else
        log_error "Subuid configuration failed"
        return 1
    fi
    
    # Check directories
    if [ -d "/home/${ROOTLESS_USER}/.config/containers" ]; then
        log_success "Configuration directories verified"
    else
        log_error "Configuration directories failed"
        return 1
    fi
    
    # Test podman as rootless user
    log_info "Testing Podman as rootless user..."
    if su - "$ROOTLESS_USER" -c "podman --version" &>/dev/null; then
        log_success "Podman works as rootless user: $(su - "$ROOTLESS_USER" -c "podman --version")"
    else
        log_error "Podman failed as rootless user"
        return 1
    fi
    
    log_success "All verifications passed"
}

# ============================================================================
# SUMMARY
# ============================================================================

print_summary() {
    log ""
    log_section "ROOTLESS SETUP COMPLETE"
    
    log_success "Summary:"
    log_info "- Rootless user: $ROOTLESS_USER (UID: $ROOTLESS_UID)"
    log_info "- User namespace: $SUBUID_START-$((SUBUID_START + SUBUID_COUNT - 1))"
    log_info "- Config dir: /home/${ROOTLESS_USER}/.config/containers"
    log_info "- Storage dir: /home/${ROOTLESS_USER}/.local/share/containers"
    log_info "- Socket: /run/user/${ROOTLESS_UID}/podman/podman.sock"
    log_info "- Auto-start: Enabled (via loginctl linger)"
    
    log ""
    log_info "Next steps:"
    log_info "1. Switch to rootless user: su - $ROOTLESS_USER"
    log_info "2. Start services: systemctl --user start podman"
    log_info "3. Run containers: podman run hello-world"
    log_info "4. For docker-compose: podman-compose up -d"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_title "NEXTCLOUD DOCKER STACK - ROOTLESS SETUP"
    
    check_requirements
    create_rootless_user
    configure_subuid_subgid
    setup_directories
    configure_podman
    setup_systemd_services
    enable_linger
    verify_installation
    print_summary
}

main "$@"
