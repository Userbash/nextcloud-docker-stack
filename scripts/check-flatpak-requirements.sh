#!/bin/bash

###############################################################################
# Check Flatpak Requirements
# Purpose: Verify all necessary tools are available in flatpak environment
# Author: Nextcloud Docker Stack Team
###############################################################################

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Nextcloud Stack - Flatpak IDE Requirements Check        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

check_tool() {
    local tool=$1
    local display_name=${2:-$tool}
    
    if command -v "$tool" &> /dev/null; then
        version=$(command -v "$tool" &> /dev/null && eval "${tool} --version 2>&1 | head -1" || echo "installed")
        echo -e "${GREEN}✓${NC} $display_name: $version"
        return 0
    else
        echo -e "${RED}✗${NC} $display_name: ${RED}NOT FOUND${NC}"
        return 1
    fi
}

echo -e "${YELLOW}REQUIRED TOOLS:${NC}"
missing=0

check_tool "python3" "Python 3" || missing=$((missing+1))
check_tool "bash" "Bash" || missing=$((missing+1))
check_tool "git" "Git" || missing=$((missing+1))

echo ""
echo -e "${YELLOW}OPTIONAL SERVICES (for full functionality):${NC}"

check_tool "nginx" "Nginx (Web Server)" || echo -e "${YELLOW}  ⚠ Optional: use PHP dev server instead${NC}"
check_tool "php-fpm" "PHP-FPM" || echo -e "${YELLOW}  ⚠ Optional: PHP-FPM for production-like setup${NC}"
check_tool "redis-cli" "Redis CLI" || echo -e "${YELLOW}  ⚠ Optional: for caching${NC}"
check_tool "psql" "PostgreSQL CLI" || echo -e "${YELLOW}  ⚠ Optional: for database access${NC}"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

if [ $missing -eq 0 ]; then
    echo -e "${GREEN}✓ All required tools are available!${NC}"
    echo ""
    echo "You can now run:"
    echo "  bash scripts/setup-local-dev.sh"
    exit 0
else
    echo -e "${RED}✗ Missing $missing required tool(s)${NC}"
    echo ""
    echo -e "${YELLOW}To install on Ubuntu/Debian:${NC}"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install python3 bash git"
    echo ""
    echo -e "${YELLOW}To install on Fedora/CentOS:${NC}"
    echo "  sudo dnf install python3 bash git"
    echo ""
    exit 1
fi
