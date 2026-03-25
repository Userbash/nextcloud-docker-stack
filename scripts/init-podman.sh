#!/bin/bash
# Podman Initialization Script for Nextcloud Docker Stack
# Initialize Podman environment and prepare the system
# Usage: ./scripts/init-podman.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname "$script_dir")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Podman Environment Initialization${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# ==================================================
# 1. Check Podman installation
# ==================================================
echo -e "${BLUE}📦 Step 1: Checking Podman installation...${NC}"

if ! command -v podman &> /dev/null; then
    echo -e "${RED}❌ Podman not found!${NC}"
    echo -e "${YELLOW}Install with:${NC}"
    echo "  Ubuntu/Debian: sudo apt-get install -y podman podman-compose"
    echo "  RHEL/CentOS:   sudo dnf install -y podman podman-compose"
    echo "  Fedora:        sudo dnf install -y podman podman-compose"
    exit 1
fi

PODMAN_VERSION=$(podman --version | cut -d' ' -f3)
echo -e "${GREEN}✅ Podman found: v${PODMAN_VERSION}${NC}"

if ! command -v podman-compose &> /dev/null; then
    echo -e "${RED}❌ podman-compose not found!${NC}"
    echo -e "${YELLOW}Install with:${NC}"
    echo "  sudo apt-get install -y podman-compose  # Debian/Ubuntu"
    echo "  sudo dnf install -y podman-compose      # RHEL/Fedora"
    exit 1
fi

COMPOSE_VERSION=$(podman-compose --version 2>/dev/null | cut -d' ' -f3 || echo "unknown")
echo -e "${GREEN}✅ podman-compose found: v${COMPOSE_VERSION}${NC}"

# ==================================================
# 2. Check system limits
# ==================================================
echo ""
echo -e "${BLUE}📊 Step 2: Checking system limits...${NC}"

NOFILE_LIMIT=$(ulimit -n)
NPROC_LIMIT=$(ulimit -u)

if [ "$NOFILE_LIMIT" -lt 65536 ]; then
    echo -e "${YELLOW}⚠️  nofile limit is ${NOFILE_LIMIT} (recommended: 65536)${NC}"
    echo -e "${YELLOW}   Fix by editing /etc/security/limits.conf${NC}"
else
    echo -e "${GREEN}✅ nofile limit: ${NOFILE_LIMIT}${NC}"
fi

if [ "$NPROC_LIMIT" -lt 4096 ]; then
    echo -e "${YELLOW}⚠️  nproc limit is ${NPROC_LIMIT} (recommended: 4096)${NC}"
    echo -e "${YELLOW}   Fix by editing /etc/security/limits.conf${NC}"
else
    echo -e "${GREEN}✅ nproc limit: ${NPROC_LIMIT}${NC}"
fi

# ==================================================
# 3. Check user podman group membership
# ==================================================
echo ""
echo -e "${BLUE}👤 Step 3: Checking user podman group...${NC}"

if groups | grep -q podman; then
    echo -e "${GREEN}✅ User is in podman group${NC}"
else
    echo -e "${YELLOW}⚠️  User not in podman group${NC}"
    echo -e "${YELLOW}   Run: sudo usermod -aG podman \$USER${NC}"
    echo -e "${YELLOW}   Then: newgrp podman${NC}"
fi

# ==================================================
# 4. Check Podman socket
# ==================================================
echo ""
echo -e "${BLUE}🔌 Step 4: Checking Podman socket...${NC}"

if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

PODMAN_SOCKET="$XDG_RUNTIME_DIR/podman/podman.sock"

if [ -S "$PODMAN_SOCKET" ]; then
    echo -e "${GREEN}✅ Podman socket found: $PODMAN_SOCKET${NC}"
else
    echo -e "${YELLOW}⚠️  Podman socket not found${NC}"
    echo -e "${YELLOW}   Starting podman service...${NC}"
    systemctl --user start podman.socket || podman system reset --force || true
fi

# Test connectivity
if timeout 5 podman ps &>/dev/null; then
    echo -e "${GREEN}✅ Podman socket is accessible${NC}"
else
    echo -e "${RED}❌ Cannot connect to Podman socket${NC}"
    echo -e "${YELLOW}   Try: systemctl --user start podman${NC}"
    exit 1
fi

# ==================================================
# 5. Set up Podman configuration
# ==================================================
echo ""
echo -e "${BLUE}⚙️  Step 5: Setting up Podman configuration...${NC}"

CONTAINERS_CONF="$HOME/.config/containers/containers.conf"
REGISTRIES_CONF="$HOME/.config/containers/registries.conf"

mkdir -p "$(dirname "$CONTAINERS_CONF")"

# Create containers.conf if not exists
if [ ! -f "$CONTAINERS_CONF" ]; then
    cat > "$CONTAINERS_CONF" << 'EOF'
[containers]
pids_limit = 4096
tz = "local"
dns = ["8.8.8.8", "8.8.4.4", "1.1.1.1"]

[engine]
events_logger = "journald"
active_service = "podman"

[engine.service_destinations]
[engine.service_destinations.podman]
uri = "$XDG_RUNTIME_DIR/podman/podman.sock"
EOF
    echo -e "${GREEN}✅ Created containers.conf${NC}"
else
    echo -e "${GREEN}✅ containers.conf already exists${NC}"
fi

# Create registries.conf if not exists
if [ ! -f "$REGISTRIES_CONF" ]; then
    cat > "$REGISTRIES_CONF" << 'EOF'
unqualified-search-registries = ["docker.io"]

[[registry]]
location = "docker.io"
insecure = false
EOF
    echo -e "${GREEN}✅ Created registries.conf${NC}"
else
    echo -e "${GREEN}✅ registries.conf already exists${NC}"
fi

# ==================================================
# 6. Check/create Podman network
# ==================================================
echo ""
echo -e "${BLUE}🔗 Step 6: Setting up Podman network...${NC}"

if podman network inspect nextcloud_network &>/dev/null; then
    echo -e "${GREEN}✅ nextcloud_network exists${NC}"
else
    if podman network create nextcloud_network &>/dev/null; then
        echo -e "${GREEN}✅ Created nextcloud_network${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not create network (may already exist)${NC}"
    fi
fi

# ==================================================
# 7. Run standard initialization
# ==================================================
echo ""
echo -e "${BLUE}📋 Step 7: Running standard initialization...${NC}"

cd "$project_dir"
bash "$script_dir/init.sh"

# ==================================================
# 8. Check storage availability
# ==================================================
echo ""
echo -e "${BLUE}💾 Step 8: Checking storage...${NC}"

STORAGE_DIR="$HOME/.local/share/containers"
mkdir -p "$STORAGE_DIR"

AVAILABLE_SPACE=$(df "$STORAGE_DIR" | awk 'NR==2 {print $4}')

if [ "$AVAILABLE_SPACE" -lt 20971520 ]; then  # 20GB in KB
    echo -e "${YELLOW}⚠️  Warning: Less than 20GB available${NC}"
else
    echo -e "${GREEN}✅ Sufficient storage available${NC}"
fi

# ==================================================
# 9. Prepare .env for Podman
# ==================================================
echo ""
echo -e "${BLUE}🔐 Step 9: Updating .env for Podman...${NC}"

ENV_FILE="$project_dir/.env"

if [ -f "$ENV_FILE" ]; then
    # Add Podman-specific settings if not present
    if ! grep -q "PODMAN_USERNS_MODE" "$ENV_FILE"; then
        echo "" >> "$ENV_FILE"
        echo "# Podman settings" >> "$ENV_FILE"
        echo "PODMAN_USERNS_MODE=auto" >> "$ENV_FILE"
        echo -e "${GREEN}✅ Added Podman settings to .env${NC}"
    else
        echo -e "${GREEN}✅ .env already prepared for Podman${NC}"
    fi
else
    echo -e "${RED}❌ .env file not found${NC}"
    exit 1
fi

# ==================================================
# 10. Final diagnostics
# ==================================================
echo ""
echo -e "${BLUE}🏥 Step 10: Final diagnostics...${NC}"

echo ""
echo -e "${BLUE}System Information:${NC}"
echo "  User: $(whoami)"
echo "  Podman Version: ${PODMAN_VERSION}"
echo "  podman-compose Version: ${COMPOSE_VERSION}"
echo "  XDG_RUNTIME_DIR: ${XDG_RUNTIME_DIR}"
echo "  nofile limit: ${NOFILE_LIMIT}"
echo "  nproc limit: ${NPROC_LIMIT}"

echo ""
echo -e "${BLUE}Podman Images Count:${NC}"
IMAGES_COUNT=$(podman images -q 2>/dev/null | wc -l)
echo "  Available images: ${IMAGES_COUNT}"

echo ""
echo -e "${BLUE}Podman Networks:${NC}"
podman network ls

# ==================================================
# 11. Finalization
# ==================================================
echo ""
echo -e "${GREEN}✅ Podman initialization complete!${NC}"
echo ""
echo -e "${BLUE}📋 Next steps:${NC}"
echo "  1. Edit configuration: vi $ENV_FILE"
echo ""
echo "  2. Start services:"
echo "     podman-compose up -d"
echo ""
echo "  3. Check status:"
echo "     podman ps"
echo "     podman-compose logs -f"
echo ""
echo "  4. Run health check:"
echo "     ./scripts/health-check.sh"
echo ""
echo -e "${YELLOW}⚠️  Important:${NC}"
echo "  - Ensure all secrets in .env are changed from defaults"
echo "  - DNS resolution may need adjustment in some environments"
echo "  - For SSL, ensure domain is accessible on port 443"
echo ""

exit 0
