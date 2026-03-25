#!/bin/bash
# scripts/manage-rootless.sh
# Manage Nextcloud containers in Podman rootless mode (NO SUDO!)
# Examples: ./manage-rootless.sh start
#           ./manage-rootless.sh logs app
#           ./manage-rootless.sh systemd-up

set -euo pipefail

if [ "$EUID" -eq 0 ]; then
    echo "❌ Do NOT run this as root!"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.rootless.yaml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Help message
# ============================================================
show_help() {
    cat << EOF
${BLUE}📱 Nextcloud Podman Rootless Manager${NC}

Usage: $(basename "$0") <command> [options]

${BLUE}CONTAINER MANAGEMENT:${NC}
  start         Start containers (manual, no systemd)
  stop          Stop containers
  restart       Restart containers
  ps            List containers
  status        Show container status
  stats         Show resource usage

${BLUE}LOGS:${NC}
  logs          Show all logs (follow mode)
  logs <name>   Show logs for service (db, redis, app, nginx, certbot)

${BLUE}OPERATIONS:${NC}
  backup        Run backup manually
  health        Run health check
  shell <name>  Open shell in container
  clean         Remove all containers and volumes (DESTRUCTIVE!)

${BLUE}SYSTEMD SERVICES (for auto-start):${NC}
  systemd-up    Enable systemd auto-start services
  systemd-down  Disable systemd services
  systemd-logs  View systemd service logs
  systemd-status Check systemd services status

${YELLOW}SECURITY:${NC}
  - Never use sudo with this script
  - All operations run as current user
  - Uses Podman rootless mode (no root privileges)

${BLUE}EXAMPLES:${NC}
  $(basename "$0") start
  $(basename "$0") logs app
  $(basename "$0") backup
  $(basename "$0") systemd-up

EOF
}

# ============================================================
# Check compose file
# ============================================================
if [ ! -f "$COMPOSE_FILE" ]; then
    echo -e "${RED}❌ Compose file not found: $COMPOSE_FILE${NC}"
    exit 1
fi

# ============================================================
# Commands
# ============================================================
case "${1:-help}" in
    start)
        echo -e "${BLUE}🚀 Starting containers...${NC}"
        podman-compose -f "$COMPOSE_FILE" up -d
        sleep 3
        echo -e "${GREEN}✅ Containers started${NC}"
        echo ""
        podman ps
        ;;
    
    stop)
        echo -e "${BLUE}🛑 Stopping containers...${NC}"
        podman-compose -f "$COMPOSE_FILE" down
        echo -e "${GREEN}✅ Containers stopped${NC}"
        ;;
    
    restart)
        echo -e "${BLUE}🔄 Restarting containers...${NC}"
        podman-compose -f "$COMPOSE_FILE" restart
        echo -e "${GREEN}✅ Containers restarted${NC}"
        ;;
    
    ps)
        echo -e "${BLUE}📦 Podman Containers:${NC}"
        podman ps -a
        ;;
    
    status)
        echo -e "${BLUE}📊 Container Status:${NC}"
        podman ps
        echo ""
        echo -e "${BLUE}🌐 Networks:${NC}"
        podman network ls
        ;;
    
    stats)
        echo -e "${BLUE}💻 Resource Usage:${NC}"
        podman stats --no-stream
        ;;
    
    logs)
        if [ -z "${2:-}" ]; then
            echo -e "${BLUE}📜 All Container Logs:${NC}"
            podman-compose -f "$COMPOSE_FILE" logs -f
        else
            SERVICE_NAME="${2}"
            echo -e "${BLUE}📜 Logs for $SERVICE_NAME:${NC}"
            podman logs -f "nextcloud-$SERVICE_NAME-rootless" 2>/dev/null || \
                podman logs -f "$SERVICE_NAME" 2>/dev/null || \
                echo -e "${RED}❌ Container not found: $SERVICE_NAME${NC}"
        fi
        ;;
    
    backup)
        echo -e "${BLUE}💾 Running backup...${NC}"
        cd "$PROJECT_DIR"
        bash ./scripts/backup.sh
        ;;
    
    health)
        echo -e "${BLUE}🏥 Running health check...${NC}"
        cd "$PROJECT_DIR"
        bash ./scripts/health-check.sh
        ;;
    
    shell)
        if [ -z "${2:-}" ]; then
            echo -e "${RED}❌ Specify container: db, redis, app, or nginx${NC}"
            exit 1
        fi
        SERVICE="${2}"
        echo -e "${BLUE}🐚 Opening shell in nextcloud-$SERVICE-rootless...${NC}"
        podman exec -it "nextcloud-$SERVICE-rootless" sh 2>/dev/null || \
            podman exec -it "$SERVICE" sh 2>/dev/null || \
            echo -e "${RED}❌ Container not found${NC}"
        ;;
    
    clean)
        echo -e "${YELLOW}⚠️  WARNING: This will DELETE all containers and volumes!${NC}"
        read -r -p "Type 'yes' to confirm: " confirm
        if [ "$confirm" = "yes" ]; then
            echo -e "${RED}Removing containers and volumes...${NC}"
            podman-compose -f "$COMPOSE_FILE" down -v
            echo -e "${GREEN}✅ Cleaned${NC}"
        else
            echo "Cancelled"
        fi
        ;;
    
    systemd-up)
        echo -e "${BLUE}⚙️  Setting up systemd services...${NC}"
        bash "$PROJECT_DIR/scripts/setup-systemd-services.sh"
        echo ""
        echo -e "${BLUE}🚀 Start now with:${NC}"
        echo "  systemctl --user start podman-nextcloud.service"
        ;;
    
    systemd-down)
        echo -e "${BLUE}🔌 Disabling systemd services...${NC}"
        systemctl --user stop podman-nextcloud.service podman-nextcloud-backup.timer podman-nextcloud-health.timer 2>/dev/null || true
        systemctl --user disable podman-nextcloud.service podman-nextcloud-backup.timer podman-nextcloud-health.timer 2>/dev/null || true
        echo -e "${GREEN}✅ Systemd services disabled${NC}"
        ;;
    
    systemd-logs)
        echo -e "${BLUE}📋 Systemd Service Logs:${NC}"
        journalctl --user-unit=podman-nextcloud.service -n 50 -f
        ;;
    
    systemd-status)
        echo -e "${BLUE}📊 Systemd Services Status:${NC}"
        systemctl --user status podman-nextcloud.service podman-nextcloud-backup.timer podman-nextcloud-health.timer 2>/dev/null || true
        ;;
    
    help|-h|--help)
        show_help
        ;;
    
    *)
        echo -e "${RED}❌ Unknown command: ${1}${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac
