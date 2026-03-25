#!/usr/bin/env bash
# scripts/run-ci-local.sh
# Fully automated local CI runner using 'act'.
# No user input required.

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== Automated Local CI Pipeline ===${NC}"

# ==============================================================================
# 1. Ensure 'act' is installed
# ==============================================================================
ACT_CMD="act"

if ! command -v act >/dev/null 2>&1; then
    if [ -x "$HOME/.local/bin/act" ]; then
        ACT_CMD="$HOME/.local/bin/act"
    else
        echo -e "${BLUE}[*] 'act' not found. Installing locally...${NC}"
        mkdir -p "$HOME/.local/bin"
        
        # Download and install act silently
        python3 -c "import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/nektos/act/master/install.sh', '/tmp/install_act.sh')"
        bash /tmp/install_act.sh -b "$HOME/.local/bin" > /dev/null 2>&1
        rm -f /tmp/install_act.sh
        
        ACT_CMD="$HOME/.local/bin/act"
        echo -e "${GREEN}[+] 'act' successfully installed.${NC}"
    fi
fi

# ==============================================================================
# 2. Check Podman/Docker socket gracefully
# ==============================================================================
if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl --user is-active --quiet podman.socket 2>/dev/null && ! systemctl is-active --quiet docker 2>/dev/null; then
        echo -e "${YELLOW}[!] WARNING: No container engine socket detected (Docker or Podman).${NC}"
        echo -e "    Attempting to start user podman socket..."
        systemctl --user start podman.socket || echo -e "${YELLOW}    Could not start systemd socket, ignoring...${NC}"
    fi
else
    echo -e "${YELLOW}[*] systemctl not found, skipping socket status check.${NC}"
fi

# ==============================================================================
# 3. Run Github Actions
# ==============================================================================
echo -e "\n${BLUE}[*] Running GitHub Action: lint${NC}"
$ACT_CMD -j lint --bind --container-architecture linux/amd64

# To run other jobs, uncomment the following line:
# echo -e "\n${BLUE}[*] Running GitHub Action: shell-check${NC}"
# $ACT_CMD -j shell-check --container-architecture linux/amd64 || echo "Shell check failed, but moving on..."

echo -e "\n${GREEN}=== Local CI Completed Successfully ===${NC}"