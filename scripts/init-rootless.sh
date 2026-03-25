#!/bin/bash
# scripts/init-rootless.sh
# Initialize Podman rootless mode (WITHOUT SUDO!)
# Usage: bash scripts/init-rootless.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_dir="$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔒 Podman Rootless Initialization${NC}"
echo -e "${BLUE}==================================${NC}"
echo ""

# ================================================================
# 1. Check that we are NOT root
# ================================================================
echo -e "${BLUE}Step 1: Checking execution privileges...${NC}"

if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}❌ ERROR: This script must NOT run as root or with sudo!${NC}"
    echo -e "${YELLOW}Run as regular user: bash scripts/init-rootless.sh${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Running as unprivileged user: $(whoami)${NC}"
echo -e "${GREEN}✅ UID: $(id -u)${NC}"
echo ""

# ================================================================
# 2. Check Podman installation
# ================================================================
echo -e "${BLUE}Step 2: Checking Podman installation...${NC}"

if ! command -v podman &> /dev/null; then
    echo -e "${RED}❌ Podman not found${NC}"
    echo -e "${YELLOW}Install: sudo apt-get install -y podman podman-compose${NC}"
    exit 1
fi

PODMAN_VERSION=$(podman --version | cut -d' ' -f3)
echo -e "${GREEN}✅ Podman v${PODMAN_VERSION}${NC}"

if ! command -v podman-compose &> /dev/null; then
    echo -e "${RED}❌ podman-compose not found${NC}"
    exit 1
fi

echo -e "${GREEN}✅ podman-compose installed${NC}"
echo ""

# ================================================================
# 3. Check XDG_RUNTIME_DIR
# ================================================================
echo -e "${BLUE}Step 3: Checking XDG_RUNTIME_DIR...${NC}"

if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

echo "  Path: $XDG_RUNTIME_DIR"

if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    echo -e "${RED}❌ XDG_RUNTIME_DIR does not exist${NC}"
    exit 1
fi

if [ ! -w "$XDG_RUNTIME_DIR" ]; then
    echo -e "${RED}❌ No write permission to XDG_RUNTIME_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}✅ XDG_RUNTIME_DIR ready${NC}"
echo ""

# ================================================================
# 4. Check Podman socket
# ================================================================
echo -e "${BLUE}Step 4: Checking Podman socket...${NC}"

PODMAN_SOCKET="$XDG_RUNTIME_DIR/podman/podman.sock"

if ! timeout 5 podman ps &>/dev/null; then
    echo -e "${YELLOW}⚠️  Podman socket not responsive, starting podman.socket...${NC}"
    systemctl --user start podman.socket 2>/dev/null || true
    sleep 2
fi

if ! timeout 5 podman ps &>/dev/null; then
    echo -e "${RED}❌ Cannot connect to Podman${NC}"
    echo -e "${YELLOW}Try to run: systemctl --user start podman.socket${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Podman socket accessible${NC}"
echo ""

# ================================================================
# 5. Create project directories
# ================================================================
echo -e "${BLUE}Step 5: Creating project directories...${NC}"

mkdir -p "$PROJECT_DIR/config/ssl"
mkdir -p "$PROJECT_DIR/config/webroot"
mkdir -p "$PROJECT_DIR/logs"
mkdir -p "$PROJECT_DIR/backups"
mkdir -p "$HOME/.local/share/podman-volumes"

chmod 700 "$PROJECT_DIR/logs"
chmod 700 "$PROJECT_DIR/backups"

echo -e "${GREEN}✅ Directories created${NC}"
echo ""

# ================================================================
# 6. Prepare .env file
# ================================================================
echo -e "${BLUE}Step 6: Preparing .env file...${NC}"

if [ ! -f "$PROJECT_DIR/.env" ]; then
    if [ ! -f "$PROJECT_DIR/.env.example" ]; then
        echo -e "${RED}❌ .env.example not found${NC}"
        exit 1
    fi
    
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    chmod 600 "$PROJECT_DIR/.env"
    echo -e "${GREEN}✅ Created .env (600 permissions)${NC}"
else
    echo -e "${YELLOW}⚠️  .env already exists${NC}"
fi

echo ""

# ================================================================
# 7. Create Podman network
# ================================================================
echo -e "${BLUE}Step 7: Creating Podman network...${NC}"

if podman network inspect nextcloud_network &>/dev/null; then
    echo -e "${GREEN}✅ Network already exists${NC}"
else
    if podman network create nextcloud_network &>/dev/null; then
        echo -e "${GREEN}✅ Network created${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not create network (may exist)${NC}"
    fi
fi

echo ""

# ================================================================
# 8. Configure Podman
# ================================================================
echo -e "${BLUE}Step 8: Configuring Podman for rootless...${NC}"

mkdir -p ~/.config/containers

if [ ! -f ~/.config/containers/containers.conf ]; then
    cat > ~/.config/containers/containers.conf << 'EOF'
[containers]
tz = "local"
pids_limit = 4096
dns = ["8.8.8.8", "8.8.4.4", "1.1.1.1"]

[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"

[network]
network_backend = "cni"

[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
EOF
    echo -e "${GREEN}✅ Created containers.conf${NC}"
else
    echo -e "${YELLOW}⚠️  containers.conf already exists${NC}"
fi

echo ""

# ================================================================
# 9. Start user dbus
# ================================================================
echo -e "${BLUE}Step 9: Starting user dbus...${NC}"

systemctl --user start dbus 2>/dev/null || true
systemctl --user enable dbus 2>/dev/null || true

if systemctl --user is-active dbus &>/dev/null; then
    echo -e "${GREEN}✅ User dbus running${NC}"
else
    echo -e "${YELLOW}⚠️  Could not start dbus (may not be needed)${NC}"
fi

echo ""

# ================================================================
# 10. Final diagnostics
# ================================================================
echo -e "${BLUE}Step 10: Final diagnostics...${NC}"

echo -e "${GREEN}✅ Rootless initialization complete!${NC}"
echo ""

echo -e "${BLUE}📊 System Information:${NC}"
echo "  User: $(whoami)"
echo "  UID: $(id -u)"
echo "  Podman Version: $(podman --version | cut -d' ' -f3)"
echo "  XDG_RUNTIME_DIR: $XDG_RUNTIME_DIR"
echo ""

# Check podman info
PODMAN_STORAGE=$(podman info --format '{{.Store.DriverOptions}}' 2>/dev/null || echo "unknown")
echo -e "${BLUE}📦 Podman Storage:${NC}"
podman info --format '{{.Store.RunRoot}}' 2>/dev/null || echo "  Using default storage"
echo ""

echo -e "${BLUE}🚀 Next steps:${NC}"
echo "  1. Edit configuration:"
echo "     nano $PROJECT_DIR/.env"
echo ""
echo "  2. Set REQUIRED values:"
echo "     - POSTGRES_PASSWORD (min 16 chars)"
echo "     - NEXTCLOUD_ADMIN_PASSWORD (min 16 chars)"  
echo "     - NEXTCLOUD_DOMAIN (your domain)"
echo "     - LETSENCRYPT_EMAIL (for SSL)"
echo ""
echo "  3. Choose how to start:"
echo ""
echo "     METHOD 1 - Manual (testing):"
echo "     podman-compose -f docker-compose.rootless.yaml up -d"
echo ""
echo "     METHOD 2 - SystemD Auto-Start (recommended for production):"
echo "     bash $PROJECT_DIR/scripts/setup-systemd-services.sh"
echo "     systemctl --user enable podman-nextcloud.service"
echo "     systemctl --user start podman-nextcloud.service"
echo ""
echo "  4. Check status:"
echo "     podman ps"
echo "     systemctl --user status podman-nextcloud.service"
echo ""
echo "  5. View logs:"
echo "     journalctl --user-unit=podman-nextcloud.service -f"
echo ""
