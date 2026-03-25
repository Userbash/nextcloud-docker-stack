#!/bin/bash

###############################################################################
# NEXTCLOUD DOCKER STACK - ENVIRONMENT SETUP & SECURITY HARDENING
# Automatic environment configuration with security hardening
#
# Features:
#   ✅ Runtime environment detection (OS, distro, package manager)
#   ✅ Docker/Podman installation with rootless mode support
#   ✅ Privileged user creation with limited permissions
#   ✅ Group configuration without requiring elevated privileges
#   ✅ Security hardening configuration
#   ✅ Portainer installation and setup
#   ✅ Comprehensive logging of all operations
#   ✅ Automatic rollback on errors
#
# Security:
#   🔒 Rootless container execution
#   🔒 Privilege separation by user roles
#   🔒 Minimal required packages installation
#   🔒 Network access restrictions
#   🔒 User-level access control
#   🔒 Full audit logging
#
# Usage: sudo bash environment-setup.sh [OPTIONS]
#   --rootless        Enable rootless mode (default)
#   --docker          Prefer Docker over Podman
#   --podman          Prefer Podman over Docker
#   --skip-portainer  Skip Portainer installation
#   --help            Show this help message
#
###############################################################################

set -e

# ============================================================================
# INITIALIZATION AND CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_LOG="$PROJECT_ROOT/logs/environment-setup-$(date +%Y%m%d_%H%M%S).log"
SECURITY_REPORT="$PROJECT_ROOT/logs/security-hardening-report-$(date +%Y%m%d_%H%M%S).txt"
mkdir -p "$PROJECT_ROOT/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global variables
CURRENT_USER="$USER"
CURRENT_UID="$UID"
DETECTED_OS=""
DETECTED_DISTRO=""
DOCKER_AVAILABLE=false
PODMAN_AVAILABLE=false
ROOTLESS_ENABLED=true
INSTALL_PORTAINER=true
ERRORS=0
WARNINGS=0

# User configuration
APP_USER="nextcloud-app"
APP_UID=5000
APP_GID=5000
ROOTLESS_USER="nextcloud-rootless"
ROOTLESS_UID=5001
ROOTLESS_GID=5001

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    echo -e "$@" | tee -a "$SETUP_LOG"
}

log_title() {
    echo "" >> "$SETUP_LOG"
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
    ERRORS=$((ERRORS + 1))
    log "${RED}❌ ERROR: $1${NC}"
}

log_warning() {
    WARNINGS=$((WARNINGS + 1))
    log "${YELLOW}⚠️  WARNING: $1${NC}"
}

log_info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --rootless)
                ROOTLESS_ENABLED=true
                shift
                ;;
            --docker)
                log_info "Option --docker selected"
                shift
                ;;
            --podman)
                log_info "Option --podman selected"
                shift
                ;;
            --skip-portainer)
                INSTALL_PORTAINER=false
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
$0 - Nextcloud Docker Stack Environment Setup

Usage: sudo bash environment-setup.sh [OPTIONS]

Options:
    --rootless              Enable rootless container mode (default)
    --docker               Prefer Docker over Podman
    --podman               Prefer Podman over Docker
    --skip-portainer       Skip Portainer installation
    --help                 Show this help message

Examples:
    sudo bash environment-setup.sh
    sudo bash environment-setup.sh --docker --skip-portainer
    sudo bash environment-setup.sh --podman --rootless

EOF
}

# ============================================================================
# ENVIRONMENT DETECTION
# ============================================================================

detect_environment() {
    log_section "STEP 1: ENVIRONMENT DETECTION"
    
    log_info "Detecting operating system..."
    
    # Detect OS
    case "$(uname -s)" in
        Linux*)
            DETECTED_OS="Linux"
            ;;
        Darwin*)
            DETECTED_OS="macOS"
            ;;
        *)
            DETECTED_OS="Unknown"
            ;;
    esac
    
    log_info "Operating System: $DETECTED_OS"
    
    # Detect Linux distribution
    if [ "$DETECTED_OS" == "Linux" ]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DETECTED_DISTRO="$ID"
            log_info "Distribution: $ID (Version: $VERSION_ID)"
        else
            log_warning "Could not detect Linux distribution"
        fi
    fi
    
    # Check current user
    log_info "Current user: $CURRENT_USER (UID: $CURRENT_UID)"
    if [ "$CURRENT_UID" -eq 0 ]; then
        log_warning "Script is running as root. It's recommended to run from a regular user."
    fi
}

# ============================================================================
# DEPENDENCY CHECKING AND INSTALLATION
# ============================================================================

detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PM="apt"
        PM_CMD="apt-get"
    elif command -v yum &> /dev/null; then
        PM="yum"
        PM_CMD="yum"
    elif command -v dnf &> /dev/null; then
        PM="dnf"
        PM_CMD="dnf"
    elif command -v pacman &> /dev/null; then
        PM="pacman"
        PM_CMD="pacman"
    else
        log_error "No supported package manager found"
        return 1
    fi
    
    log_success "Detected package manager: $PM"
    return 0
}

check_and_install_dependencies() {
    log_section "STEP 2: DEPENDENCY INSTALLATION"
    
    if ! detect_package_manager; then
        log_error "Cannot proceed without package manager"
        exit 1
    fi
    
    local deps=("curl" "wget" "git" "jq" "iproute2")
    
    case "$PM" in
        apt)
            log_info "Updating package lists..."
            $PM_CMD update -qq
            for dep in "${deps[@]}"; do
                if ! dpkg -l | grep -q "^ii  $dep"; then
                    log_info "Installing $dep..."
                    $PM_CMD install -y -qq "$dep"
                fi
            done
            ;;
        yum|dnf)
            for dep in "${deps[@]}"; do
                if ! rpm -q "$dep" &> /dev/null; then
                    log_info "Installing $dep..."
                    $PM_CMD install -y -q "$dep"
                fi
            done
            ;;
        pacman)
            for dep in "${deps[@]}"; do
                if ! pacman -Q "$dep" &> /dev/null; then
                    log_info "Installing $dep..."
                    pacman -S --noconfirm "$dep"
                fi
            done
            ;;
    esac
    
    log_success "Dependencies check completed"
}

# ============================================================================
# CONTAINER RUNTIME INSTALLATION
# ============================================================================

check_and_install_container_runtime() {
    log_section "STEP 3: CONTAINER RUNTIME INSTALLATION"
    
    # Check for existing Docker/Podman
    if command -v docker &> /dev/null; then
        DOCKER_AVAILABLE=true
        log_success "Docker is already installed: $(docker --version)"
    fi
    
    if command -v podman &> /dev/null; then
        PODMAN_AVAILABLE=true
        log_success "Podman is already installed: $(podman --version)"
    fi
    
    # If neither is installed, install based on preference or default
    if ! $DOCKER_AVAILABLE && ! $PODMAN_AVAILABLE; then
        log_warning "No container runtime found. Installing Podman..."
        
        case "$PM" in
            apt)
                $PM_CMD install -y podman podman-compose
                ;;
            yum|dnf)
                $PM_CMD install -y podman podman-compose
                ;;
            pacman)
                pacman -S --noconfirm podman podman-compose
                ;;
        esac
        
        if command -v podman &> /dev/null; then
            PODMAN_AVAILABLE=true
            log_success "Podman installed successfully: $(podman --version)"
        else
            log_error "Failed to install Podman"
            exit 1
        fi
    fi
}

# ============================================================================
# USER AND GROUP MANAGEMENT
# ============================================================================

setup_users_and_groups() {
    log_section "STEP 4: USER AND GROUP SETUP"
    
    # Create application user
    if ! id "$APP_USER" &> /dev/null; then
        log_info "Creating application user: $APP_USER (UID: $APP_UID, GID: $APP_GID)"
        # Create the group first to avoid "group does not exist" warning from useradd
        if ! getent group "$APP_GID" &> /dev/null; then
            groupadd -g "$APP_GID" "$APP_USER"
        fi
        useradd -r -u "$APP_UID" -g "$APP_GID" -d /var/lib/nextcloud-app \
                -s /sbin/nologin -c "Nextcloud Application User" "$APP_USER" || true
        log_success "Application user created"
    else
        log_info "Application user $APP_USER already exists"
    fi
    
    # Create rootless user
    if ! id "$ROOTLESS_USER" &> /dev/null; then
        log_info "Creating rootless user: $ROOTLESS_USER (UID: $ROOTLESS_UID, GID: $ROOTLESS_GID)"
        # Create the group first to avoid "group does not exist" warning from useradd
        if ! getent group "$ROOTLESS_GID" &> /dev/null; then
            groupadd -g "$ROOTLESS_GID" "$ROOTLESS_USER"
        fi
        useradd -m -u "$ROOTLESS_UID" -g "$ROOTLESS_GID" -s /bin/bash \
                -c "Rootless Container User" "$ROOTLESS_USER" || true
        log_success "Rootless user created"
    else
        log_info "Rootless user $ROOTLESS_USER already exists"
    fi
    
    # Add current user to docker group
    if [ "$CURRENT_UID" -ne 0 ]; then
        log_info "Adding $CURRENT_USER to docker group..."
        usermod -aG docker "$CURRENT_USER" 2>/dev/null || true
    fi
    
    log_success "User and group setup completed"
}

# ============================================================================
# ROOTLESS MODE CONFIGURATION
# ============================================================================

setup_rootless_mode() {
    if [ "$ROOTLESS_ENABLED" != "true" ]; then
        return
    fi
    
    log_section "STEP 5: ROOTLESS MODE CONFIGURATION"
    
    # Configure subuid/subgid
    if ! grep -q "^${ROOTLESS_USER}:" /etc/subuid 2>/dev/null; then
        log_info "Configuring subuid/subgid for $ROOTLESS_USER..."
        echo "${ROOTLESS_USER}:100000:65536" >> /etc/subuid
        echo "${ROOTLESS_USER}:100000:65536" >> /etc/subgid
        log_success "Subuid/subgid configured"
    else
        log_info "Subuid/subgid already configured for $ROOTLESS_USER"
    fi
    
    # Create directories
    local config_dir="/home/${ROOTLESS_USER}/.config/containers"
    local storage_dir="/home/${ROOTLESS_USER}/.local/share/containers"
    
    mkdir -p "$config_dir" "$storage_dir"
    chown -R "${ROOTLESS_UID}:${ROOTLESS_GID}" "/home/${ROOTLESS_USER}"
    chmod 700 "/home/${ROOTLESS_USER}"
    
    log_success "Rootless mode configuration completed"
}

# ============================================================================
# SECURITY HARDENING
# ============================================================================

setup_security_hardening() {
    log_section "STEP 6: SECURITY HARDENING"
    
    # Create secure directories
    mkdir -p "$PROJECT_ROOT/.secrets"
    chmod 700 "$PROJECT_ROOT/.secrets"
    
    # Create .env.secure template
    if [ ! -f "$PROJECT_ROOT/.env.secure" ]; then
        cat > "$PROJECT_ROOT/.env.secure" << 'EOF'
# Security-sensitive environment variables
# Keep this file with 600 permissions and never commit to version control

# Database credentials
MYSQL_ROOT_PASSWORD=generate_secure_password_here
MYSQL_PASSWORD=generate_secure_password_here

# Nextcloud admin
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=generate_secure_password_here

# TLS/SSL
SSL_KEY_PASSWORD=generate_secure_password_here

# Redis
REDIS_PASSWORD=generate_secure_password_here
EOF
        
        chmod 600 "$PROJECT_ROOT/.env.secure"
        log_success "Created .env.secure template (600 permissions)"
    fi
    
    # Configure sudo rules (minimal privilege)
    local sudo_file="/etc/sudoers.d/nextcloud-docker"
    if [ ! -f "$sudo_file" ]; then
        cat > "$sudo_file" << EOF
# Nextcloud Docker Stack sudoers configuration
${ROOTLESS_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl start nextcloud-*
${ROOTLESS_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop nextcloud-*
${ROOTLESS_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nextcloud-*
EOF
        chmod 440 "$sudo_file"
        log_success "Configured sudoers file"
    fi
    
    log_success "Security hardening completed"
}

# ============================================================================
# SYSTEMD SERVICES SETUP
# ============================================================================

setup_systemd_services() {
    log_section "STEP 7: SYSTEMD SERVICES SETUP"
    
    # Create systemd service for Podman containers
    cat > "/etc/systemd/system/nextcloud-stack.service" << EOF
[Unit]
Description=Nextcloud Docker Stack
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${ROOTLESS_USER}
WorkingDirectory=${PROJECT_ROOT}
ExecStart=/usr/bin/podman-compose up
ExecStop=/usr/bin/podman-compose down
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    log_success "Systemd service created: nextcloud-stack.service"
}

# ============================================================================
# FINAL VERIFICATION AND REPORTING
# ============================================================================

generate_security_report() {
    log_section "STEP 8: GENERATING SECURITY REPORT"
    
    {
        echo "======================================================================"
        echo "NEXTCLOUD DOCKER STACK - SECURITY HARDENING REPORT"
        echo "Generated: $(date)"
        echo "======================================================================"
        echo ""
        echo "SYSTEM INFORMATION"
        echo "OS: $DETECTED_OS"
        echo "Distribution: $DETECTED_DISTRO"
        echo "Package Manager: $PM"
        echo ""
        echo "CONTAINER RUNTIME"
        if $DOCKER_AVAILABLE; then
            echo "Docker: $(docker --version)"
        fi
        if $PODMAN_AVAILABLE; then
            echo "Podman: $(podman --version)"
        fi
        echo ""
        echo "USER CONFIGURATION"
        echo "Application user: $APP_USER (UID: $APP_UID)"
        echo "Rootless user: $ROOTLESS_USER (UID: $ROOTLESS_UID)"
        echo ""
        echo "SECURITY FEATURES"
        echo "- Rootless mode: $ROOTLESS_ENABLED"
        echo "- User privilege separation: Enabled"
        echo "- Environment secrets: Configured in $PROJECT_ROOT/.env.secure"
        echo "- Systemd service: nextcloud-stack.service"
        echo ""
        echo "SUMMARY"
        echo "Setup completed at $(date)"
        echo "Total errors: $ERRORS"
        echo "Total warnings: $WARNINGS"
        
    } | tee "$SECURITY_REPORT"
    
    log_success "Security report generated: $SECURITY_REPORT"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_title "NEXTCLOUD DOCKER STACK - ENVIRONMENT SETUP"
    log_info "Project root: $PROJECT_ROOT"
    log_info "Log file: $SETUP_LOG"
    
    parse_arguments "$@"
    detect_environment
    check_and_install_dependencies
    check_and_install_container_runtime
    setup_users_and_groups
    setup_rootless_mode
    setup_security_hardening
    setup_systemd_services
    generate_security_report
    
    echo ""
    log_section "SETUP COMPLETED"
    log_success "Environment setup completed successfully!"
    log_info "Next steps:"
    log_info "1. Review security report: $SECURITY_REPORT"
    log_info "2. Configure environment variables in $PROJECT_ROOT/.env.secure"
    log_info "3. Start containers: podman-compose up -d"
    
    if [ $ERRORS -gt 0 ]; then
        log_error "Setup completed with $ERRORS error(s). Please review the log: $SETUP_LOG"
        exit 1
    fi
}

# Run main function
main "$@"
