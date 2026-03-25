#!/bin/bash

###############################################################################
# Local Environment Tests for Flatpak Development
# Purpose: Test configuration and services without Docker
# Author: Nextcloud Docker Stack Team
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_REPORT="$PROJECT_ROOT/test-reports/local-env-report-$(date +%Y%m%d_%H%M%S).txt"

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

mkdir -p "$PROJECT_ROOT/test-reports"

###############################################################################
# Test Framework Functions
###############################################################################

test_start() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -ne "  [$TESTS_RUN] $test_name... "
    echo "[TEST $TESTS_RUN] $test_name" >> "$TEST_REPORT"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC}"
    echo "  Result: PASS" >> "$TEST_REPORT"
}

test_fail() {
    local reason="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC}"
    echo "  Result: FAIL - $reason" >> "$TEST_REPORT"
}

test_skip() {
    echo -e "${YELLOW}⊗${NC} (skipped)"
    echo "  Result: SKIP" >> "$TEST_REPORT"
}

###############################################################################
# Test: Environment Requirements
###############################################################################
test_environment_requirements() {
    echo -e "${BLUE}Environment Requirements${NC}"
    echo "" >> "$TEST_REPORT"
    echo "=== Environment Requirements ===" >> "$TEST_REPORT"
    echo ""
    
    # Python 3
    test_start "Python 3 available"
    if command -v python3 &>/dev/null; then
        local py_version=$(python3 --version 2>&1 | awk '{print $2}')
        echo "  Version: $py_version" >> "$TEST_REPORT"
        test_pass
    else
        test_fail "Python 3 not found"
    fi
    
    # Bash
    test_start "Bash available"
    if command -v bash &>/dev/null; then
        local bash_version=$(bash --version | head -1 | awk '{print $4}' | cut -d- -f1)
        echo "  Version: $bash_version" >> "$TEST_REPORT"
        test_pass
    else
        test_fail "Bash not found"
    fi
    
    # Nginx
    test_start "Nginx available"
    if command -v nginx &>/dev/null; then
        local nginx_version=$(nginx -v 2>&1 | awk '{print $3}')
        echo "  Version: $nginx_version" >> "$TEST_REPORT"
        test_pass
    else
        test_fail "Nginx not found"
    fi
    
    # PHP-FPM
    test_start "PHP-FPM available"
    if command -v php-fpm &>/dev/null; then
        local php_version=$(php-fpm -v | head -1 | awk '{print $2}')
        echo "  Version: $php_version" >> "$TEST_REPORT"
        test_pass
    else
        test_fail "PHP-FPM not found"
    fi
    
    # Redis CLI
    test_start "Redis CLI available"
    if command -v redis-cli &>/dev/null; then
        local redis_version=$(redis-cli --version | awk '{print $NF}')
        echo "  Version: $redis_version" >> "$TEST_REPORT"
        test_pass
    else
        test_fail "Redis CLI not found"
    fi
    
    # PostgreSQL CLI
    test_start "PostgreSQL CLI available"
    if command -v psql &>/dev/null; then
        local psql_version=$(psql --version | awk '{print $NF}')
        echo "  Version: $psql_version" >> "$TEST_REPORT"
        test_pass
    else
        test_fail "PostgreSQL CLI not found"
    fi
    
    # Git
    test_start "Git available"
    if command -v git &>/dev/null; then
        local git_version=$(git --version | awk '{print $3}')
        echo "  Version: $git_version" >> "$TEST_REPORT"
        test_pass
    else
        test_fail "Git not found"
    fi
    
    echo ""
}

###############################################################################
# Test: Directory Structure
###############################################################################
test_directory_structure() {
    echo -e "${BLUE}Directory Structure${NC}"
    echo "" >> "$TEST_REPORT"
    echo "=== Directory Structure ===" >> "$TEST_REPORT"
    echo ""
    
    local dirs=(
        "data/nextcloud"
        "data/postgresql"
        "data/redis"
        "data/tmp"
        "logs"
        "config/local"
        "tests"
        "scripts"
    )
    
    for dir in "${dirs[@]}"; do
        test_start "Directory: $dir"
        if [ -d "$PROJECT_ROOT/$dir" ]; then
            echo "  Path: $PROJECT_ROOT/$dir" >> "$TEST_REPORT"
            test_pass
        else
            test_fail "Directory not found (run setup-local-dev.sh)"
        fi
    done
    
    echo ""
}

###############################################################################
# Test: Configuration Files
###############################################################################
test_configuration_files() {
    echo -e "${BLUE}Configuration Files${NC}"
    echo "" >> "$TEST_REPORT"
    echo "=== Configuration Files ===" >> "$TEST_REPORT"
    echo ""
    
    # .env.local
    test_start "File: .env.local"
    if [ -f "$PROJECT_ROOT/.env.local" ]; then
        local size=$(wc -c < "$PROJECT_ROOT/.env.local")
        echo "  Size: $size bytes" >> "$TEST_REPORT"
        test_pass
    else
        test_fail "Not found"
    fi
    
    # nginx.conf
    test_start "File: nginx.conf (local)"
    if [ -f "$PROJECT_ROOT/config/local/nginx.conf" ]; then
        test_pass
    else
        test_fail "Not found"
    fi
    
    # php-fpm.conf
    test_start "File: php-fpm.conf (local)"
    if [ -f "$PROJECT_ROOT/config/local/php-fpm.conf" ]; then
        test_pass
    else
        test_fail "Not found"
    fi
    
    # redis.conf
    test_start "File: redis.conf (local)"
    if [ -f "$PROJECT_ROOT/config/local/redis.conf" ]; then
        test_pass
    else
        test_fail "Not found"
    fi
    
    ## docker-compose.yaml
    test_start "File: docker-compose.yaml (reference)"
    if [ -f "$PROJECT_ROOT/docker-compose.yaml" ]; then
        test_pass
    else
        test_fail "Not found"
    fi
    
    echo ""
}

###############################################################################
# Test: Configuration Validation
###############################################################################
test_config_validation() {
    echo -e "${BLUE}Configuration Validation${NC}"
    echo "" >> "$TEST_REPORT"
    echo "=== Configuration Validation ===" >> "$TEST_REPORT"
    echo ""
    
    # Validate Nginx config
    test_start "Validate: nginx.conf syntax"
    if command -v nginx &>/dev/null; then
        if nginx -t -c "$PROJECT_ROOT/config/local/nginx.conf" -p "$PROJECT_ROOT" 2>&1 | grep -q "successful"; then
            test_pass
        else
            test_fail "Syntax error in nginx.conf"
        fi
    else
        test_skip
    fi
    
    # Validate PHP syntax
    test_start "Validate: php.ini syntax"
    if command -v php &>/dev/null; then
        if php -l "$PROJECT_ROOT/php/php.ini" &>/dev/null; then
            test_pass
        else
            test_fail "Syntax error in php.ini"
        fi
    else
        test_skip
    fi
    
    # Validate .env.local format
    test_start "Validate: .env.local format"
    local invalid_lines=$(grep -v "^[A-Z_].*=.*$" "$PROJECT_ROOT/.env.local" 2>/dev/null | grep -v "^#" | grep -v "^$" | wc -l)
    if [ "$invalid_lines" -eq 0 ]; then
        test_pass
    else
        test_fail "Invalid lines found"
    fi
    
    # Validate YAML
    test_start "Validate: docker-compose.yaml YAML format"
    if command -v python3 &>/dev/null; then
        if python3 -c "import yaml; yaml.safe_load(open('$PROJECT_ROOT/docker-compose.yaml'))" 2>/dev/null; then
            test_pass
        else
            test_fail "Invalid YAML format"
        fi
    else
        test_skip
    fi
    
    echo ""
}

###############################################################################
# Test: Service Connectivity
###############################################################################
test_service_connectivity() {
    echo -e "${BLUE}Service Connectivity${NC}"
    echo "" >> "$TEST_REPORT"
    echo "=== Service Connectivity ===" >> "$TEST_REPORT"
    echo ""
    
    # Redis connectivity
    test_start "Connect: Redis on port 6379"
    if command -v redis-cli &>/dev/null; then
        if redis-cli ping 2>/dev/null | grep -q PONG; then
            test_pass
        else
            test_fail "Cannot connect to Redis"
        fi
    else
        test_skip
    fi
    
    # PostgreSQL connectivity
    test_start "Connect: PostgreSQL on port 5432"
    if command -v pg_isready &>/dev/null; then
        if pg_isready -h localhost -p 5432 2>/dev/null | grep -q "accepting"; then
            test_pass
        else
            test_fail "PostgreSQL not accepting connections"
        fi
    else
        test_skip
    fi
    
    # Nginx status
    test_start "Process: Nginx running"
    if ps aux | grep -q "[n]ginx"; then
        test_pass
    else
        test_fail "Nginx not running"
    fi
    
    # PHP-FPM status
    test_start "Process: PHP-FPM running"
    if ps aux | grep -q "[p]hp-fpm"; then
        test_pass
    else
        test_fail "PHP-FPM not running"
    fi
    
    echo ""
}

###############################################################################
# Test: Database
###############################################################################
test_database() {
    echo -e "${BLUE}Database Tests${NC}"
    echo "" >> "$TEST_REPORT"
    echo "=== Database Tests ===" >> "$TEST_REPORT"
    echo ""
    
    # SQLite DB exists
    test_start "Database: SQLite DB exists"
    if [ -f "$PROJECT_ROOT/data/nextcloud/nextcloud.db" ]; then
        local db_size=$(ls -lh "$PROJECT_ROOT/data/nextcloud/nextcloud.db" | awk '{print $5}')
        echo "  Size: $db_size" >> "$TEST_REPORT"
        test_pass
    else
        test_fail "SQLite DB not found"
    fi
    
    # SQLite tables
    test_start "Database: Tables exist"
    if command -v sqlite3 &>/dev/null; then
        local table_count=$(sqlite3 "$PROJECT_ROOT/data/nextcloud/nextcloud.db" ".tables" | wc -w)
        if [ "$table_count" -gt 0 ]; then
            echo "  Tables count: $table_count" >> "$TEST_REPORT"
            test_pass
        else
            test_fail "No tables found"
        fi
    else
        test_skip
    fi
    
    # User data directories
    test_start "Database: User data directories exist"
    local user_dirs=(
        "$PROJECT_ROOT/data/nextcloud/files"
        "$PROJECT_ROOT/data/nextcloud/files_trashbin"
        "$PROJECT_ROOT/data/nextcloud/versions"
    )
    local all_exist=true
    for dir in "${user_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            all_exist=false
            break
        fi
    done
    if $all_exist; then
        test_pass
    else
        test_fail "Some user directories missing"
    fi
    
    echo ""
}

###############################################################################
# Test: Scripts
###############################################################################
test_scripts() {
    echo -e "${BLUE}Script Tests${NC}"
    echo "" >> "$TEST_REPORT"
    echo "=== Script Tests ===" >> "$TEST_REPORT"
    echo ""
    
    local scripts=(
        "scripts/setup-local-dev.sh"
        "scripts/local-services-mock.sh"
        "scripts/backup.sh"
        "scripts/health-check.sh"
        "scripts/init.sh"
        "scripts/update.sh"
    )
    
    for script in "${scripts[@]}"; do
        test_start "Script: $script executable"
        if [ -f "$PROJECT_ROOT/$script" ] && [ -x "$PROJECT_ROOT/$script" ]; then
            test_pass
        else
            test_fail "Not executable"
        fi
    done
    
    # Bash syntax check
    for script in scripts/*.sh; do
        test_start "Syntax: $(basename $script)"
        if bash -n "$PROJECT_ROOT/$script" 2>/dev/null; then
            test_pass
        else
            test_fail "Syntax error"
        fi
    done
    
    echo ""
}

###############################################################################
# Test: Port Availability
###############################################################################
test_ports() {
    echo -e "${BLUE}Port Availability${NC}"
    echo "" >> "$TEST_REPORT"
    echo "=== Port Availability ===" >> "$TEST_REPORT"
    echo ""
    
    # Port 6379 (Redis)
    test_start "Port: 6379 (Redis)"
    if ! netstat -tlnp 2>/dev/null | grep -q ":6379 "; then
        test_pass
    else
        test_fail "Port already in use"
    fi
    
    # Port 5432 (PostgreSQL)
    test_start "Port: 5432 (PostgreSQL)"
    if ! netstat -tlnp 2>/dev/null | grep -q ":5432 "; then
        test_pass
    else
        test_fail "Port already in use"
    fi
    
    # Port 8080 (Nginx)
    test_start "Port: 8080 (Nginx)"
    if ! netstat -tlnp 2>/dev/null | grep -q ":8080 "; then
        test_pass
    else
        test_fail "Port already in use"
    fi
    
    # Port 8000 (PHP Dev Server)
    test_start "Port: 8000 (PHP Dev Server)"
    if ! netstat -tlnp 2>/dev/null | grep -q ":8000 "; then
        test_pass
    else
        test_fail "Port already in use"
    fi
    
    echo ""
}

###############################################################################
# Test: Permissions
###############################################################################
test_permissions() {
    echo -e "${BLUE}File Permissions${NC}"
    echo "" >> "$TEST_REPORT"
    echo "=== File Permissions ===" >> "$TEST_REPORT"
    echo ""
    
    # .env.local permissions
    test_start "Permissions: .env.local (should be 600)"
    local env_perms=$(stat -f '%OLp' "$PROJECT_ROOT/.env.local" 2>/dev/null || stat -c '%a' "$PROJECT_ROOT/.env.local")
    if [ "$env_perms" = "600" ] || [ "$env_perms" = "660" ]; then
        test_pass
    else
        test_fail "Permissions are $env_perms (should be 600)"
    fi
    
    # data directories readable/writable
    test_start "Permissions: data directories writable"
    if [ -w "$PROJECT_ROOT/data" ] && [ -w "$PROJECT_ROOT/logs" ]; then
        test_pass
    else
        test_fail "Cannot write to data/logs directories"
    fi
    
    echo ""
}

###############################################################################
# Test Summary
###############################################################################
test_summary() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    Test Summary                                 ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Total Tests:   $TESTS_RUN"
    
    local pass_percent=$((TESTS_PASSED * 100 / TESTS_RUN))
    
    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "  Passed:        ${GREEN}$TESTS_PASSED${NC}"
        echo -e "  Failed:        $TESTS_FAILED"
        echo -e "  Success Rate:  ${GREEN}$pass_percent%${NC}"
    else
        echo -e "  Passed:        $TESTS_PASSED"
        echo -e "  Failed:        ${RED}$TESTS_FAILED${NC}"
        echo -e "  Success Rate:  $pass_percent%"
    fi
    
    echo ""
    echo "  Report saved: $TEST_REPORT"
    echo ""
    
    # Append summary to report
    echo "" >> "$TEST_REPORT"
    echo "=== SUMMARY ===" >> "$TEST_REPORT"
    echo "Total Tests: $TESTS_RUN" >> "$TEST_REPORT"
    echo "Passed: $TESTS_PASSED" >> "$TEST_REPORT"
    echo "Failed: $TESTS_FAILED" >> "$TEST_REPORT"
    echo "Success Rate: $pass_percent%" >> "$TEST_REPORT"
    echo "Test Date: $(date)" >> "$TEST_REPORT"
}

###############################################################################
# Main
###############################################################################
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Local Environment Tests for Flatpak Development        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    test_environment_requirements
    test_directory_structure
    test_configuration_files
    test_config_validation
    test_service_connectivity
    test_database
    test_scripts
    test_ports
    test_permissions
    test_summary
    
    # Return proper exit code
    if [ "$TESTS_FAILED" -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
