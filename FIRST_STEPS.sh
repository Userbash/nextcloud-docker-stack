#!/bin/bash
# Quick Start: First Steps After Deployment
# Run this immediately after deploying Nextcloud

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

printf "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}\n"
printf "${BLUE}║   NEXTCLOUD DOCKER STACK - FIRST STEPS VERIFICATION      ║${NC}\n"
printf "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n\n"

# Step 1: Configuration Check
echo -e "${YELLOW}Step 1: Checking Configuration Files...${NC}"
if [ -f ".env" ]; then
    echo -e "${GREEN}✅ .env found${NC}"
else
    echo -e "${RED}❌ .env not found - copy from .env.example${NC}"
    exit 1
fi

if [ -f "docker-compose.yaml" ]; then
    echo -e "${GREEN}✅ docker-compose.yaml found${NC}"
else
    echo -e "${RED}❌ docker-compose.yaml not found${NC}"
    exit 1
fi

# Step 2: Environment Permissions Check
echo -e "\n${YELLOW}Step 2: Checking Security...${NC}"
PERMS=$(stat -c '%a' .env 2>/dev/null || echo "unknown")
if [ "$PERMS" = "600" ]; then
    echo -e "${GREEN}✅ .env permissions are secure (600)${NC}"
else
    echo -e "${RED}❌ .env permissions are insecure ($PERMS - should be 600)${NC}"
    echo -e "${YELLOW}   Run: chmod 600 .env${NC}"
fi

# Step 3: Container Status Check
echo -e "\n${YELLOW}Step 3: Checking Container Status...${NC}"

# Detect runtime
if command -v docker &> /dev/null; then
    RUNTIME="docker"
    COMPOSE_CMD="docker-compose"
elif command -v podman &> /dev/null; then
    RUNTIME="podman"
    COMPOSE_CMD="podman-compose"
else
    echo -e "${RED}❌ Neither Docker nor Podman found${NC}"
    exit 1
fi

echo -e "Using runtime: ${GREEN}${RUNTIME}${NC}"

# Check if containers are running
if $COMPOSE_CMD ps | grep -q "Up"; then
    RUNNING=$($COMPOSE_CMD ps --services | wc -l)
    echo -e "${GREEN}✅ Containers are running${NC}"
    $COMPOSE_CMD ps
else
    echo -e "${YELLOW}⚠️  No running containers found${NC}"
    echo -e "Starting containers with: ${YELLOW}$COMPOSE_CMD up -d${NC}"
    $COMPOSE_CMD up -d
    sleep 5
    echo -e "\nContainer status:"
    $COMPOSE_CMD ps
fi

# Step 4: Service Connectivity Check
echo -e "\n${YELLOW}Step 4: Testing Service Connectivity...${NC}"

# Check web service
if $COMPOSE_CMD exec -T nextcloud-web-1 curl -sf http://localhost/status.php > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Nextcloud web service responding${NC}"
else
    echo -e "${YELLOW}⚠️  Nextcloud web service not responding yet (may still be starting)${NC}"
fi

# Check database
if $COMPOSE_CMD exec -T nextcloud-db-1 pg_isready -U nextcloud &> /dev/null; then
    echo -e "${GREEN}✅ PostgreSQL database responding${NC}"
else
    echo -e "${RED}❌ PostgreSQL database not responding${NC}"
fi

# Check Redis
if $COMPOSE_CMD exec -T nextcloud-redis-1 redis-cli ping &> /dev/null; then
    echo -e "${GREEN}✅ Redis cache responding${NC}"
else
    echo -e "${RED}❌ Redis cache not responding${NC}"
fi

# Step 5: SSL Certificate Check
echo -e "\n${YELLOW}Step 5: Checking SSL Certificates...${NC}"
if [ -d "config/ssl" ]; then
    CERT_COUNT=$(find config/ssl -name "*.pem" 2>/dev/null | wc -l)
    if [ "$CERT_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✅ SSL certificates found ($CERT_COUNT files)${NC}"
        # Check certificate expiry
        if [ -f "config/ssl/fullchain.pem" ]; then
            EXPIRY=$(openssl x509 -enddate -noout -in config/ssl/fullchain.pem 2>/dev/null | cut -d= -f2)
            echo "   Certificate expires: $EXPIRY"
        fi
    else
        echo -e "${YELLOW}⚠️  SSL directory exists but no certificates found${NC}"
        echo "   Nextcloud will request certificates using Let's Encrypt"
    fi
else
    echo -e "${YELLOW}⚠️  SSL directory not yet created${NC}"
    echo "   It will be created during Certbot initialization"
fi

# Step 6: Disk Space Check
echo -e "\n${YELLOW}Step 6: Checking Disk Space...${NC}"
DISK_USAGE=$(df -h /srv/nextcloud 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    echo -e "${GREEN}✅ Disk space OK (${DISK_USAGE}% used)${NC}"
else
    echo -e "${RED}❌ Low disk space (${DISK_USAGE}% used)${NC}"
fi

# Step 7: Run Test Suite
echo -e "\n${YELLOW}Step 7: Running Full Test Suite...${NC}"
if [ -f "tests/run_tests.sh" ]; then
    echo -e "Execute: ${YELLOW}./tests/run_tests.sh all${NC}"
    # Optionally run it
    read -p "Run full test suite now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        chmod +x tests/run_tests.sh
        ./tests/run_tests.sh all
    fi
else
    echo -e "${YELLOW}⚠️  Test suite not found${NC}"
fi

# Step 8: Next Steps
echo -e "\n${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
printf "${BLUE}║                     NEXT STEPS                            ║${NC}\n"
printf "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}\n\n"

echo -e "${GREEN}1. Access Nextcloud${NC}"
DOMAIN=$(grep NEXTCLOUD_DOMAIN .env | cut -d= -f2 | tr -d ' ')
if [ -z "$DOMAIN" ]; then
    DOMAIN="localhost"
fi
echo "   Open: https://$DOMAIN"
echo "   Default admin created from .env (NEXTCLOUD_ADMIN_USER)"
echo ""

echo -e "${GREEN}2. Monitor Logs${NC}"
echo "   $COMPOSE_CMD logs -f nextcloud-web-1"
echo ""

echo -e "${GREEN}3. Run Tests Regularly${NC}"
echo "   ./tests/run_tests.sh all"
echo ""

echo -e "${GREEN}4. Backup Your Data${NC}"
echo "   ./scripts/backup.sh"
echo ""

echo -e "${GREEN}5. Security Hardening${NC}"
echo "   See: docs/SECURITY_FIXES.md"
echo ""

echo -e "${GREEN}6. Full Documentation${NC}"
echo "   Testing:        TESTING_GUIDE.md"
echo "   Quick Commands: QUICK_REFERENCE.md"
echo "   Troubleshooting: docs/TROUBLESHOOTING.md"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ First steps verification complete!${NC}"
echo ""
