#!/bin/bash

###############################################################################
# Local Services Mock for Flatpak Development
# Purpose: Start/stop local services (Redis, PostgreSQL CLI, Nginx, PHP-FPM)
# Author: Nextcloud Docker Stack Team
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Services state file
SERVICES_STATE="$PROJECT_ROOT/.services.state"

###############################################################################
# Function: Service startup wrapper
###############################################################################
start_service() {
    local service_name=$1
    local start_cmd=$2
    local check_cmd=$3
    
    echo -ne "  Starting $service_name... "
    
    if eval "$start_cmd" &>/dev/null; then
        sleep 1
        if eval "$check_cmd" &>/dev/null; then
            echo -e "${GREEN}✓${NC}"
            echo "$service_name=running" >> "$SERVICES_STATE"
            return 0
        else
            echo -e "${RED}✗ (startup check failed)${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ (startup failed)${NC}"
        return 1
    fi
}

###############################################################################
# Function: Service stop wrapper
###############################################################################
stop_service() {
    local service_name=$1
    local stop_cmd=$2
    
    echo -ne "  Stopping $service_name... "
    
    if eval "$stop_cmd" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} (may not be running)"
        return 0
    fi
}

###############################################################################
# Function: Start all services
###############################################################################
start_all() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Starting Local Services for Development                ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    rm -f "$SERVICES_STATE"
    touch "$SERVICES_STATE"
    
    cd "$PROJECT_ROOT"
    
    # Create necessary directories
    mkdir -p run logs data/redis data/postgresql
    
    # Ensure PHP-FPM socket directory exists
    mkdir -p /run/php 2>/dev/null || true
    
    # Start Redis
    if command -v redis-server &>/dev/null; then
        start_service "Redis (port 6379)" \
            "redis-server $PROJECT_ROOT/config/local/redis.conf --daemonize yes" \
            "redis-cli ping | grep -q PONG"
    else
        echo -e "  ${YELLOW}⊗${NC} Redis not installed (skipped)"
    fi
    
    # Start PHP-FPM
    if command -v php-fpm &>/dev/null; then
        start_service "PHP-FPM (unix socket)" \
            "php-fpm --fpm-config $PROJECT_ROOT/config/local/php-fpm.conf -d" \
            "ps aux | grep -q '[p]hp-fpm'"
    else
        echo -e "  ${YELLOW}⊗${NC} PHP-FPM not installed (skipped)"
    fi
    
    # Start Nginx
    if command -v nginx &>/dev/null; then
        start_service "Nginx (port 8080)" \
            "nginx -c $PROJECT_ROOT/config/local/nginx.conf -p $PROJECT_ROOT" \
            "ps aux | grep -q '[n]ginx'"
    else
        echo -e "  ${YELLOW}⊗${NC} Nginx not installed (skipped)"
    fi
    
    echo ""
    echo -e "${GREEN}Services configuration:${NC}"
    echo "  Redis:      redis-cli -p 6379"
    echo "  PostgreSQL: psql -U nextcloud -d nextcloud -h localhost"
    echo "  Nginx:      http://127.0.0.1:8080"
    echo "  PHP Dev:    php -S 127.0.0.1:8000 -t nextcloud/"
    echo ""
    echo -e "${BLUE}To develop:${NC}"
    echo "  1. In another terminal: cd $PROJECT_ROOT"
    echo "  2. Run: php -S 127.0.0.1:8000 -t nextcloud/"
    echo "  3. Open: http://127.0.0.1:8000"
    echo ""
}

###############################################################################
# Function: Stop all services
###############################################################################
stop_all() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Stopping Local Services                                ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    cd "$PROJECT_ROOT"
    
    # Stop Nginx
    if command -v nginx &>/dev/null; then
        stop_service "Nginx" "nginx -c $PROJECT_ROOT/config/local/nginx.conf -p $PROJECT_ROOT -s stop"
    fi
    
    # Stop PHP-FPM
    if command -v php-fpm &>/dev/null; then
        stop_service "PHP-FPM" "pkill -9 -f 'php-fpm.*$PROJECT_ROOT'"
    fi
    
    # Stop Redis
    if command -v redis-server &>/dev/null; then
        stop_service "Redis" "redis-cli shutdown 2>/dev/null || pkill -9 redis-server"
    fi
    
    echo ""
    rm -f "$SERVICES_STATE"
    echo -e "${GREEN}All services stopped${NC}"
    echo ""
}

###############################################################################
# Function: Show status
###############################################################################
status() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         Local Services Status                                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Check Redis
    if command -v redis-cli &>/dev/null; then
        if redis-cli ping &>/dev/null | grep -q PONG; then
            echo -e "  ${GREEN}✓${NC} Redis is ${GREEN}running${NC} (port 6379)"
            redis-cli info stats 2>/dev/null | grep -E "connected_clients|used_memory_human" | \
                sed 's/^/    /'
        else
            echo -e "  ${RED}✗${NC} Redis is ${RED}not running${NC}"
        fi
    fi
    
    # Check PHP-FPM
    if command -v php-fpm &>/dev/null; then
        if ps aux | grep -q "[p]hp-fpm"; then
            echo -e "  ${GREEN}✓${NC} PHP-FPM is ${GREEN}running${NC}"
        else
            echo -e "  ${RED}✗${NC} PHP-FPM is ${RED}not running${NC}"
        fi
    fi
    
    # Check Nginx
    if command -v nginx &>/dev/null; then
        if ps aux | grep -q "[n]ginx"; then
            echo -e "  ${GREEN}✓${NC} Nginx is ${GREEN}running${NC} (port 8080)"
        else
            echo -e "  ${RED}✗${NC} Nginx is ${RED}not running${NC}"
        fi
    fi
    
    # Check PostgreSQL connectivity
    if command -v psql &>/dev/null; then
        if pg_isready -h localhost -p 5432 2>/dev/null | grep -q "accepting"; then
            echo -e "  ${GREEN}✓${NC} PostgreSQL is ${GREEN}available${NC}"
        else
            echo -e "  ${YELLOW}⚠${NC} PostgreSQL needs to be ${YELLOW}started separately${NC}"
            echo -e "     (it's not managed by this script)"
        fi
    fi
    
    echo ""
    echo -e "${BLUE}Nextcloud Access Points:${NC}"
    echo "  • PHP Dev Server: http://127.0.0.1:8000"
    echo "  • Nginx Server:   http://127.0.0.1:8080"
    echo ""
}

###############################################################################
# Function: Show logs
###############################################################################
show_logs() {
    local service=$1
    
    case "$service" in
        redis)
            if [ -f "$PROJECT_ROOT/logs/redis.log" ]; then
                tail -f "$PROJECT_ROOT/logs/redis.log"
            else
                echo "Redis log not found"
            fi
            ;;
        nginx)
            echo "Nginx Error Log:"
            tail -f "$PROJECT_ROOT/logs/nginx-error.log"
            ;;
        php)
            if [ -f "$PROJECT_ROOT/logs/php-fpm.log" ]; then
                tail -f "$PROJECT_ROOT/logs/php-fpm.log"
            else
                echo "PHP-FPM log not found"
            fi
            ;;
        *)
            echo "Available logs:"
            ls -lh "$PROJECT_ROOT/logs" 2>/dev/null | tail -n +2 | \
                awk '{print "  " $NF " (" $5 ")"}'
            ;;
    esac
}

###############################################################################
# Function: Restart a service
###############################################################################
restart_service() {
    local service=$1
    
    echo -e "${YELLOW}Restarting $service...${NC}"
    
    case "$service" in
        nginx)
            nginx -c "$PROJECT_ROOT/config/local/nginx.conf" -p "$PROJECT_ROOT" -s stop 2>/dev/null || true
            sleep 1
            start_all | grep Nginx
            ;;
        php|php-fpm)
            pkill -9 -f 'php-fpm.*'"$PROJECT_ROOT" 2>/dev/null || true
            sleep 1
            start_all | grep PHP
            ;;
        redis)
            redis-cli shutdown 2>/dev/null || pkill -9 redis-server || true
            sleep 1
            start_all | grep Redis
            ;;
        *)
            echo "Unknown service: $service"
            ;;
    esac
}

###############################################################################
# Function: Show help
###############################################################################
show_help() {
    cat << EOF
${BLUE}Local Services Manager for Flatpak Development${NC}

Usage: $0 <command> [options]

Commands:
  start              Start all local services
  stop               Stop all local services
  restart <service> Restart a specific service (nginx|php|redis)
  status             Show status of all services
  logs [service]     Show service logs (redis|nginx|php|all)
  help               Show this help message

Examples:
  # Start development
  bash $0 start
  
  # Check status
  bash $0 status
  
  # View logs
  bash $0 logs nginx
  
  # Restart Nginx
  bash $0 restart nginx
  
  # Stop services
  bash $0 stop

${YELLOW}Environment Variables:${NC}
  PROJECT_ROOT       Project root directory (auto-detected)
  SERVICES_STATE     Services state file location

${BLUE}Service Details:${NC}
  Redis:     Port 6379, accessed via 'redis-cli'
  PHP-FPM:   Unix socket '/run/php/php-fpm.sock'
  Nginx:     Port 8080, configured at 'config/local/nginx.conf'

For more information, see: FLATPAK_SETUP.md

EOF
}

###############################################################################
# Main
###############################################################################
main() {
    case "${1:-help}" in
        start)
            start_all
            ;;
        stop)
            stop_all
            ;;
        status)
            status
            ;;
        logs)
            show_logs "${2:-all}"
            ;;
        restart)
            restart_service "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown command: $1${NC}"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
