#!/bin/bash

###############################################################################
# NEXTCLOUD DOCKER STACK - SECURITY AUDIT & HARDENING VERIFICATION
# Comprehensive security audit and vulnerability detection
#
# Features:
#   ✅ User and group verification
#   ✅ File permissions audit (SUID, world-writable)
#   ✅ Network ports and sockets verification
#   ✅ Firewall configuration audit
#   ✅ Logging and auditd verification
#   ✅ SSL certificate validation
#   ✅ Sudo configuration audit
#   ✅ Package vulnerability checking
#   ✅ Container security verification
#
# Usage: bash security-audit.sh
#
###############################################################################

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDIT_LOG="$PROJECT_ROOT/logs/security-audit-$(date +%Y%m%d_%H%M%S).log"
AUDIT_REPORT="$PROJECT_ROOT/logs/security-audit-report-$(date +%Y%m%d_%H%M%S).txt"
mkdir -p "$PROJECT_ROOT/logs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
PASS=0
FAIL=0
WARN=0
INFO=0

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    echo -e "$@" | tee -a "$AUDIT_LOG"
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

log_pass() {
    PASS=$((PASS + 1))
    log "${GREEN}✅ PASS: $1${NC}"
}

log_fail() {
    FAIL=$((FAIL + 1))
    log "${RED}❌ FAIL: $1${NC}"
}

log_warn() {
    WARN=$((WARN + 1))
    log "${YELLOW}⚠️  WARN: $1${NC}"
}

log_info() {
    INFO=$((INFO + 1))
    log "${BLUE}ℹ️  INFO: $1${NC}"
}

# ============================================================================
# AUDIT FUNCTIONS
# ============================================================================

audit_users_and_groups() {
    log_section "AUDIT 1: USERS AND GROUPS"
    
    # Check for root user
    local root_count=$(getent passwd | awk -F: '$3==0' | wc -l)
    if [ "$root_count" -eq 1 ]; then
        log_pass "Only one user with UID 0 (root)"
    else
        log_fail "Multiple users with UID 0 found (count: $root_count)"
    fi
    
    # Check for users with empty passwords
    if ! grep '^[^:]*::' /etc/shadow &>/dev/null; then
        log_pass "No users with empty passwords"
    else
        log_fail "Users with empty passwords detected"
    fi
    
    # Check for nextcloud users
    if id nextcloud-app &>/dev/null; then
        log_info "Application user found: $(id -u nextcloud-app)"
    else
        log_warn "Application user (nextcloud-app) not found"
    fi
    
    if id nextcloud-rootless &>/dev/null; then
        log_info "Rootless user found: $(id -u nextcloud-rootless)"
    else
        log_warn "Rootless user (nextcloud-rootless) not found"
    fi
}

audit_file_permissions() {
    log_section "AUDIT 2: FILE PERMISSIONS"
    
    # Check for SUID/SGID binaries
    local suid_count=$(find / -perm -4000 2>/dev/null | wc -l)
    if [ "$suid_count" -lt 50 ]; then
        log_pass "SUID binaries count reasonable: $suid_count"
    else
        log_warn "Many SUID binaries found: $suid_count"
    fi
    
    # Check for world-writable files
    local world_write=$(find "$PROJECT_ROOT" -type f -perm -002 2>/dev/null | wc -l)
    if [ "$world_write" -eq 0 ]; then
        log_pass "No world-writable files in project"
    else
        log_fail "World-writable files found: $world_write"
    fi
    
    # Check .env.secure permissions
    if [ -f "$PROJECT_ROOT/.env.secure" ]; then
        local perms=$(stat -c %a "$PROJECT_ROOT/.env.secure" 2>/dev/null || stat -f %OLp "$PROJECT_ROOT/.env.secure" 2>/dev/null)
        if [ "$perms" = "600" ]; then
            log_pass ".env.secure has correct permissions (600)"
        else
            log_fail ".env.secure has incorrect permissions: $perms"
        fi
    else
        log_info ".env.secure not found"
    fi
    
    # Check secrets directory
    if [ -d "$PROJECT_ROOT/.secrets" ]; then
        local secrets_perms=$(stat -c %a "$PROJECT_ROOT/.secrets" 2>/dev/null || stat -f %OLp "$PROJECT_ROOT/.secrets" 2>/dev/null)
        if [ "$secrets_perms" = "700" ]; then
            log_pass ".secrets directory has correct permissions (700)"
        else
            log_warn ".secrets directory permissions: $secrets_perms"
        fi
    fi
}

audit_network_security() {
    log_section "AUDIT 3: NETWORK SECURITY"
    
    # Check listening ports
    local listening_ports=$(netstat -tuln 2>/dev/null | grep LISTEN | wc -l || ss -tuln 2>/dev/null | grep LISTEN | wc -l)
    log_info "Listening ports count: $listening_ports"
    
    # Check for common vulnerable ports
    local vulnerable_ports=("23" "69" "135" "139" "445")
    for port in "${vulnerable_ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep ":$port " &>/dev/null || ss -tuln 2>/dev/null | grep ":$port " &>/dev/null; then
            log_warn "Vulnerable port $port is listening"
        fi
    done
    
    # Check Docker socket permissions
    if [ -S "/var/run/docker.sock" ]; then
        local docker_perms=$(stat -c %a /var/run/docker.sock 2>/dev/null || stat -f %OLp /var/run/docker.sock 2>/dev/null)
        log_info "Docker socket permissions: $docker_perms"
    fi
}

audit_firewall_configuration() {
    log_section "AUDIT 4: FIREWALL CONFIGURATION"
    
    # Check UFW status
    if command -v ufw &>/dev/null; then
        if ufw status &>/dev/null; then
            log_info "UFW firewall: $(ufw status | head -1)"
        fi
    fi
    
    # Check iptables status
    if command -v iptables &>/dev/null; then
        local rules_count=$(iptables -L | grep Chain | wc -l)
        log_info "IPtables rules count: $rules_count"
    fi
    
    # Check fail2ban status
    if systemctl is-active fail2ban &>/dev/null; then
        log_pass "Fail2ban is active"
    else
        log_info "Fail2ban is not active"
    fi
}

audit_logging_configuration() {
    log_section "AUDIT 5: LOGGING CONFIGURATION"
    
    # Check rsyslog
    if systemctl is-active rsyslog &>/dev/null; then
        log_pass "Rsyslog is active"
    else
        log_warn "Rsyslog is not active"
    fi
    
    # Check auditd
    if systemctl is-active auditd &>/dev/null; then
        log_pass "Auditd is active"
    else
        log_info "Auditd is not active (optional)"
    fi
    
    # Check log rotation
    if [ -f /etc/logrotate.conf ]; then
        log_pass "Log rotation configured"
    fi
}

audit_ssl_certificates() {
    log_section "AUDIT 6: SSL CERTIFICATES"
    
    # Check for certificate files
    if [ -d "$PROJECT_ROOT/config/ssl" ]; then
        local cert_count=$(find "$PROJECT_ROOT/config/ssl" -name "*.crt" -o -name "*.pem" 2>/dev/null | wc -l)
        if [ "$cert_count" -gt 0 ]; then
            log_info "Found $cert_count certificate files"
            
            # Check certificate expiration
            for cert in "$PROJECT_ROOT/config/ssl"/*.crt "$PROJECT_ROOT/config/ssl"/*.pem; do
                if [ -f "$cert" ]; then
                    local expires=$(openssl x509 -in "$cert" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "unknown")
                    log_info "Certificate: $(basename "$cert") expires: $expires"
                fi
            done
        fi
    fi
}

audit_sudo_configuration() {
    log_section "AUDIT 7: SUDO CONFIGURATION"
    
    # Check sudoers file syntax
    if visudo -c &>/dev/null; then
        log_pass "Sudoers file syntax is correct"
    else
        log_fail "Sudoers file has syntax errors"
    fi
    
    # Check for NOPASSWD rules
    if grep -q "NOPASSWD" /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
        local nopass_rules=$(grep -r "NOPASSWD" /etc/sudoers /etc/sudoers.d/* 2>/dev/null | wc -l)
        log_warn "Found $nopass_rules NOPASSWD rules (use with caution)"
    else
        log_pass "No NOPASSWD rules found"
    fi
}

audit_package_vulnerability() {
    log_section "AUDIT 8: PACKAGE VULNERABILITY"
    
    # Check for security updates
    if command -v apt &>/dev/null; then
        local updates=$(apt list --upgradable 2>/dev/null | wc -l || echo "0")
        if [ "$updates" -gt 1 ]; then
            log_warn "Security updates available: $((updates - 1))"
        else
            log_pass "System is up to date"
        fi
    elif command -v yum &>/dev/null; then
        if yum check-update -q &>/dev/null; then
            log_warn "System updates available"
        else
            log_pass "System is up to date"
        fi
    fi
    
    # Check critical packages
    local critical_packages=("openssl" "openssh-server" "sudo")
    for pkg in "${critical_packages[@]}"; do
        if dpkg -l "$pkg" 2>/dev/null || rpm -q "$pkg" 2>/dev/null; then
            log_info "Critical package installed: $pkg"
        fi
    done
}

audit_container_security() {
    log_section "AUDIT 9: CONTAINER SECURITY"
    
    # Check Docker
    if command -v docker &>/dev/null; then
        if docker ps &>/dev/null 2>&1; then
            log_pass "Docker daemon is running"
            local docker_version=$(docker --version)
            log_info "$docker_version"
        fi
    fi
    
    # Check Podman
    if command -v podman &>/dev/null; then
        local podman_version=$(podman --version)
        log_info "Podman: $podman_version"
        
        # Check for running containers
        if podman ps &>/dev/null 2>&1; then
            local container_count=$(podman ps -q 2>/dev/null | wc -l)
            log_info "Running containers: $container_count"
        fi
    fi
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

generate_report() {
    log_section "GENERATING COMPREHENSIVE SECURITY AUDIT REPORT"
    
    {
        echo "======================================================================"
        echo "NEXTCLOUD DOCKER STACK - SECURITY AUDIT REPORT"
        echo "Generated: $(date)"
        echo "======================================================================"
        echo ""
        echo "AUDIT SUMMARY"
        echo "Passed checks:   $PASS"
        echo "Failed checks:   $FAIL"
        echo "Warnings:        $WARN"
        echo "Info messages:   $INFO"
        echo ""
        echo "SUMMARY STATUS"
        if [ $FAIL -eq 0 ]; then
            echo "Status: ✅ SECURE"
        elif [ $FAIL -lt 5 ]; then
            echo "Status: ⚠️  ACCEPTABLE (minor issues)"
        else
            echo "Status: ❌ NEEDS ATTENTION (critical issues)"
        fi
        echo ""
        echo "RECOMMENDATIONS"
        if [ $FAIL -gt 0 ]; then
            echo "- Review failed security checks above"
            echo "- Address critical vulnerabilities immediately"
        fi
        if [ $WARN -gt 0 ]; then
            echo "- Review warning messages for optimization opportunities"
        fi
        echo ""
        echo "For full details, see: $AUDIT_LOG"
        
    } | tee "$AUDIT_REPORT"
    
    log "Security report generated: $AUDIT_REPORT"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_title "NEXTCLOUD DOCKER STACK - SECURITY AUDIT"
    log_info "Audit started at $(date)"
    log_info "Log file: $AUDIT_LOG"
    
    audit_users_and_groups
    audit_file_permissions
    audit_network_security
    audit_firewall_configuration
    audit_logging_configuration
    audit_ssl_certificates
    audit_sudo_configuration
    audit_package_vulnerability
    audit_container_security
    
    generate_report
    
    echo ""
    log_section "AUDIT COMPLETED"
    log_info "Total passed: $PASS"
    log_info "Total failed: $FAIL"
    log_info "Total warnings: $WARN"
}

main "$@"
