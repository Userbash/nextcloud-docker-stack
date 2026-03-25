#!/bin/bash
# scripts/setup-rootless-user.sh
# Complete user preparation for Podman rootless mode
# Usage: sudo bash setup-rootless-user.sh [username]

set -euo pipefail

USERNAME="${1:-nextcloud}"
UID_BASE=100000
SUBUID_COUNT=65536

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script requires sudo${NC}"
    exit 1
fi

echo -e "${BLUE}🔒 Podman Rootless User Setup${NC}"
echo -e "${BLUE}=============================${NC}"
echo ""

# ================================================================
# 1. Create user
# ================================================================
echo -e "${BLUE}Step 1: Creating user...${NC}"

if id "$USERNAME" &>/dev/null; then
    echo -e "  ${YELLOW}⚠️  User '$USERNAME' already exists${NC}"
else
    useradd -m -s /bin/bash "$USERNAME"
    echo -e "  ${GREEN}✅ User created${NC}"
fi

# ================================================================
# 2. Configuring subuid/subgid
# ================================================================
echo -e "${BLUE}Step 2: Configuring subuid/subgid...${NC}"

if grep -q "^$USERNAME:" /etc/subuid; then
    echo -e "  ${YELLOW}⚠️  subuid already configured${NC}"
else
    echo "$USERNAME:$UID_BASE:$SUBUID_COUNT" >> /etc/subuid
    echo -e "  ${GREEN}✅ subuid configured${NC}"
fi

if grep -q "^$USERNAME:" /etc/subgid; then
    echo -e "  ${YELLOW}⚠️  subgid already configured${NC}"
else
    echo "$USERNAME:$UID_BASE:$SUBUID_COUNT" >> /etc/subgid
    echo -e "  ${GREEN}✅ subgid configured${NC}"
fi

chmod 644 /etc/subuid /etc/subgid

# ================================================================
# 3. Enable lingering
# ================================================================
echo -e "${BLUE}Step 3: Enabling lingering...${NC}"

loginctl enable-linger "$USERNAME"
echo -e "  ${GREEN}✅ Lingering enabled${NC}"

# ================================================================
# 4. Create project directories with correct ownership
# ================================================================
echo -e "${BLUE}Step 4: Creating project directories...${NC}"

PROJECT_HOME="/home/$USERNAME/projects"
PROJECT_DIR="$PROJECT_HOME/nextcloud-docker-stack"

mkdir -p "$PROJECT_HOME"
mkdir -p "$PROJECT_DIR/config/ssl"
mkdir -p "$PROJECT_DIR/config/webroot"
mkdir -p "$PROJECT_DIR/logs"
mkdir -p "$PROJECT_DIR/backups"

# Set ownership
chown -R "$USERNAME:$USERNAME" /home/"$USERNAME"
chmod 700 /home/"$USERNAME"

echo -e "  ${GREEN}✅ Directories created${NC}"

# ================================================================
# 5. Create .local directory for Podman
# ================================================================
echo -e "${BLUE}Step 5: Creating Podman storage directory...${NC}"

USER_LOCAL="/home/$USERNAME/.local"
mkdir -p "$USER_LOCAL/share/containers"
mkdir -p "$USER_LOCAL/share/podman-volumes"
mkdir -p "$USER_LOCAL/share/podman/libpod"

chown -R "$USERNAME:$USERNAME" "$USER_LOCAL"
chmod 700 "$USER_LOCAL"
chmod 700 "$USER_LOCAL/share/containers"

echo -e "  ${GREEN}✅ Podman storage ready${NC}"

# ================================================================
# 6. Verification
# ================================================================
echo -e "${BLUE}Step 6: Verification...${NC}"

echo ""
echo -e "${BLUE}✅ User Setup Complete!${NC}"
echo ""

echo -e "${BLUE}📋 Configuration Summary:${NC}"
echo "  Username: $USERNAME"
echo "  Home: /home/$USERNAME"
echo "  subuid: $USERNAME:$UID_BASE:$SUBUID_COUNT"
echo "  subgid: $USERNAME:$UID_BASE:$SUBUID_COUNT"
echo ""

echo -e "${BLUE}Configured:${NC}"
grep "^$USERNAME:" /etc/subuid /etc/subgid
echo ""

echo -e "${BLUE}Lingering status:${NC}"
loginctl show-user "$USERNAME" | grep Linger
echo ""

echo -e "${BLUE}🚀 Next steps:${NC}"
echo "  1. Switch to user: sudo su - $USERNAME"
echo "  2. Initialize: cd ~/projects/nextcloud-docker-stack"
echo "  3. Run: bash ./scripts/init-rootless.sh"
echo ""
