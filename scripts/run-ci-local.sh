#!/usr/bin/env bash
# scripts/run-ci-local.sh
# Fully automated local CI runner using 'act'.
# No user input required.

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

ACT_CMD="act"

# Prints a single-line script header.
print_header() {
    echo -e "${BLUE}=== Automated Local CI Pipeline ===${NC}"
}

# Ensures 'act' is present. If missing, installs it into ~/.local/bin.
ensure_act_installed() {
    if command -v act >/dev/null 2>&1; then
        ACT_CMD="act"
        return
    fi

    if [ -x "$HOME/.local/bin/act" ]; then
        ACT_CMD="$HOME/.local/bin/act"
        return
    fi

    echo -e "${BLUE}[*] 'act' not found. Installing locally...${NC}"
    mkdir -p "$HOME/.local/bin"

    # Install using official installer script.
    python3 -c "import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/nektos/act/master/install.sh', '/tmp/install_act.sh')"
    bash /tmp/install_act.sh -b "$HOME/.local/bin" >/dev/null 2>&1
    rm -f /tmp/install_act.sh

    ACT_CMD="$HOME/.local/bin/act"
    echo -e "${GREEN}[+] 'act' successfully installed.${NC}"
}

# Tries to ensure at least one container engine socket is available.
ensure_engine_socket() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] systemctl not found, skipping socket status check.${NC}"
        return
    fi

    if systemctl --user is-active --quiet podman.socket 2>/dev/null; then
        return
    fi

    if systemctl is-active --quiet docker 2>/dev/null; then
        return
    fi

    echo -e "${YELLOW}[!] WARNING: No container engine socket detected (Docker or Podman).${NC}"
    echo -e "    Attempting to start user podman socket..."
    systemctl --user start podman.socket || echo -e "${YELLOW}    Could not start systemd socket, ignoring...${NC}"
}

# Runs the lint job from GitHub Actions via act.
run_lint_job() {
    echo -e "\n${BLUE}[*] Running GitHub Action: lint${NC}"
    "$ACT_CMD" -j lint --bind --container-architecture linux/amd64
}

# Entry point for local CI execution.
main() {
    print_header
    ensure_act_installed
    ensure_engine_socket
    run_lint_job
    echo -e "\n${GREEN}=== Local CI Completed Successfully ===${NC}"
}

main "$@"