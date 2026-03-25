#!/bin/bash

###############################################################################
# Setup Local Development Environment for Flatpak IDE
# Purpose: Configure local development without Docker
# Author: Nextcloud Docker Stack Team
# Date: 2026-03-15
###############################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Local Development Environment Setup for Flatpak IDE        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

###############################################################################
# Function: Check Requirements
###############################################################################
check_requirements() {
    echo -e "${YELLOW}[1/6]${NC} Checking requirements..."
    
    local missing_tools=()
    
    # Check Python 3
    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    else
        echo -e "  ${GREEN}✓${NC} Python 3: $(python3 --version)"
    fi
    
    # Check Bash
    if ! command -v bash &> /dev/null; then
        missing_tools+=("bash")
    else
        echo -e "  ${GREEN}✓${NC} Bash: $(bash --version | head -1)"
    fi
    
    # Check Nginx
    if ! command -v nginx &> /dev/null; then
        missing_tools+=("nginx")
    else
        echo -e "  ${GREEN}✓${NC} Nginx: $(nginx -v 2>&1)"
    fi
    
    # Check PHP-FPM
    if ! command -v php-fpm &> /dev/null; then
        missing_tools+=("php-fpm")
    else
        echo -e "  ${GREEN}✓${NC} PHP-FPM: $(php-fpm -v | head -1)"
    fi
    
    # Check Redis CLI
    if ! command -v redis-cli &> /dev/null; then
        missing_tools+=("redis-cli")
    else
        echo -e "  ${GREEN}✓${NC} Redis CLI: $(redis-cli --version)"
    fi
    
    # Check PostgreSQL CLI
    if ! command -v psql &> /dev/null; then
        missing_tools+=("psql")
    else
        echo -e "  ${GREEN}✓${NC} PostgreSQL CLI: $(psql --version)"
    fi
    
    # Check Git
    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    else
        echo -e "  ${GREEN}✓${NC} Git: $(git --version)"
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e ""
        echo -e "${RED}✗ Missing tools:${NC} ${missing_tools[*]}"
        echo -e "${YELLOW}  Install them to continue:${NC}"
        echo -e "  Ubuntu/Debian: sudo apt-get install ${missing_tools[*]}"
        echo -e "  Fedora: sudo dnf install ${missing_tools[*]}"
        return 1
    fi
    
    echo ""
    return 0
}

###############################################################################
# Function: Create Directory Structure
###############################################################################
create_directories() {
    echo -e "${YELLOW}[2/6]${NC} Creating directory structure..."
    
    local dirs=(
        "data/nextcloud"
        "data/postgresql"
        "data/redis"
        "data/tmp"
        "data/sessions"
        "data/cache"
        "logs"
        "config/local"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$PROJECT_ROOT/$dir" ]; then
            mkdir -p "$PROJECT_ROOT/$dir"
            echo -e "  ${GREEN}✓${NC} Created: $dir"
        else
            echo -e "  ${BLUE}~${NC} Exists: $dir"
        fi
    done
    
    # Set permissions
    chmod 755 "$PROJECT_ROOT/data"
    chmod 755 "$PROJECT_ROOT/logs"
    chmod 755 "$PROJECT_ROOT/config/local"
    
    echo ""
}

###############################################################################
# Function: Create Configuration Files
###############################################################################
create_configs() {
    echo -e "${YELLOW}[3/6]${NC} Creating configuration files..."
    
    # Create .env.local
    if [ ! -f "$PROJECT_ROOT/.env.local" ]; then
        cat > "$PROJECT_ROOT/.env.local" << 'EOF'
# Local Development Environment Variables
# Do NOT use in production

# Application Settings
NEXTCLOUD_DOMAIN=localhost:8000
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=admin123
NEXTCLOUD_TRUSTED_DOMAINS=127.0.0.1,localhost

# Database Configuration (Local)
DB_TYPE=sqlite
DB_HOST=localhost
DB_PORT=5432
DB_NAME=nextcloud
DB_USER=nextcloud
DB_PASSWORD=nextcloud

# Redis Configuration (Local Mock)
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=

# PHP Configuration
PHP_UPLOAD_MAX_FILESIZE=10G
PHP_POST_MAX_SIZE=10G
PHP_MEMORY_LIMIT=512M
PHP_MAX_EXECUTION_TIME=3600

# Logging
LOG_LEVEL=debug
LOG_FILE=logs/nextcloud.log

# Development Settings
DEBUG=true
ENV=local
EOF
        echo -e "  ${GREEN}✓${NC} Created: .env.local"
    else
        echo -e "  ${BLUE}~${NC} Exists: .env.local"
    fi
    
    # Create local Nginx configuration
    cat > "$PROJECT_ROOT/config/local/nginx.conf" << 'EOF'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log logs/nginx-access.log main;
    error_log logs/nginx-error.log;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 10G;

    # Local Nextcloud server
    server {
        listen 8080;
        server_name localhost 127.0.0.1;
        
        root nextcloud;
        index index.php index.html index.htm;

        # PHP-FPM backend
        location ~ [^/]\.php(/|$) {
            fastcgi_pass unix:/run/php/php-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            include fastcgi_params;
        }

        # Cache static files
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
        }

        # Deny access to sensitive files
        location ~ /\. {
            deny all;
        }

        location ~ ^/config/ {
            deny all;
        }

        location ~ ^/\.well-known/acme-challenge/ {
            allow all;
        }
    }
}
EOF
    echo -e "  ${GREEN}✓${NC} Created: config/local/nginx.conf"
    
    # Create local PHP-FPM configuration
    cat > "$PROJECT_ROOT/config/local/php-fpm.conf" << 'EOF'
[global]
pid = run/php-fpm.pid
error_log = logs/php-fpm.log
log_level = warning

[www]
user = nobody
group = nobody
listen = /run/php/php-fpm.sock
listen.owner = nobody
listen.group = nobody
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 5
pm.process_idle_timeout = 15s
pm.status_path = /status
ping.path = /ping
EOF
    echo -e "  ${GREEN}✓${NC} Created: config/local/php-fpm.conf"
    
    # Create Redis mock configuration
    cat > "$PROJECT_ROOT/config/local/redis.conf" << 'EOF'
port 6379
logfile "logs/redis.log"
databases 16
dir data/redis
dbfilename dump.rdb
save 900 1
save 300 10
save 60 10000
EOF
    echo -e "  ${GREEN}✓${NC} Created: config/local/redis.conf"
    
    echo ""
}

###############################################################################
# Function: Initialize Database
###############################################################################
init_database() {
    echo -e "${YELLOW}[4/6]${NC} Initializing database..."
    
    # Create SQLite DB for development
    sqlite3 "$PROJECT_ROOT/data/nextcloud/nextcloud.db" << EOF
CREATE TABLE IF NOT EXISTS oc_appconfig (
    appid TEXT NOT NULL DEFAULT '',
    configkey TEXT NOT NULL DEFAULT '',
    configvalue LONGTEXT,
    PRIMARY KEY (appid, configkey)
);

CREATE TABLE IF NOT EXISTS oc_users (
    uid TEXT NOT NULL DEFAULT '',
    password TEXT NOT NULL DEFAULT '',
    displayname TEXT DEFAULT '',
    PRIMARY KEY (uid)
);

CREATE TABLE IF NOT EXISTS oc_preferences (
    userid TEXT NOT NULL DEFAULT '',
    appid TEXT NOT NULL DEFAULT 'files',
    configkey TEXT NOT NULL DEFAULT '',
    configvalue LONGTEXT,
    PRIMARY KEY (userid, appid, configkey)
);
EOF
    
    echo -e "  ${GREEN}✓${NC} Created: data/nextcloud/nextcloud.db"
    
    # Create directories for user data
    if [ ! -d "$PROJECT_ROOT/data/nextcloud/files" ]; then
        mkdir -p "$PROJECT_ROOT/data/nextcloud/files"
        mkdir -p "$PROJECT_ROOT/data/nextcloud/files_trashbin"
        mkdir -p "$PROJECT_ROOT/data/nextcloud/versions"
        echo -e "  ${GREEN}✓${NC} Created: User data directories"
    fi
    
    echo ""
}

###############################################################################
# Function: Create Helper Scripts
###############################################################################
create_helpers() {
    echo -e "${YELLOW}[5/6]${NC} Creating helper scripts..."
    
    # Start services script
    cat > "$PROJECT_ROOT/scripts/local-services-start.sh" << 'EOF'
#!/bin/bash
# Start local services for Flatpak development

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "Starting local services..."

# Start Redis
if command -v redis-server &> /dev/null; then
    echo "Starting Redis..."
    redis-server config/local/redis.conf --daemonize yes --logfile logs/redis.log
    sleep 1
    redis-cli ping && echo "Redis started ✓" || echo "Redis failed ✗"
fi

# Start PHP-FPM (if available)
if command -v php-fpm &> /dev/null; then
    echo "Starting PHP-FPM..."
    php-fpm --fpm-config config/local/php-fpm.conf -d
    sleep 1
    ps aux | grep -q "[p]hp-fpm" && echo "PHP-FPM started ✓" || echo "PHP-FPM failed ✗"
fi

# Start Nginx (if available)
if command -v nginx &> /dev/null; then
    echo "Starting Nginx..."
    mkdir -p "$PROJECT_ROOT/run"
    nginx -c "$PROJECT_ROOT/config/local/nginx.conf" -p "$PROJECT_ROOT"
    sleep 1
    ps aux | grep -q "[n]ginx" && echo "Nginx started ✓" || echo "Nginx failed ✗"
fi

echo ""
echo "Services started. Access Nextcloud at: http://127.0.0.1:8080"
EOF
    chmod +x "$PROJECT_ROOT/scripts/local-services-start.sh"
    echo -e "  ${GREEN}✓${NC} Created: scripts/local-services-start.sh"
    
    # Stop services script
    cat > "$PROJECT_ROOT/scripts/local-services-stop.sh" << 'EOF'
#!/bin/bash
# Stop local services

echo "Stopping local services..."

# Stop Nginx
if command -v nginx &> /dev/null; then
    echo "Stopping Nginx..."
    nginx -s stop 2>/dev/null || pkill -f nginx || true
fi

# Stop PHP-FPM
if command -v php-fpm &> /dev/null; then
    echo "Stopping PHP-FPM..."
    pkill -f php-fpm || true
fi

# Stop Redis
if command -v redis-server &> /dev/null; then
    echo "Stopping Redis..."
    redis-cli shutdown 2>/dev/null || pkill -f redis-server || true
fi

sleep 1
echo "Services stopped ✓"
EOF
    chmod +x "$PROJECT_ROOT/scripts/local-services-stop.sh"
    echo -e "  ${GREEN}✓${NC} Created: scripts/local-services-stop.sh"
    
    echo ""
}

###############################################################################
# Function: Create Summary
###############################################################################
create_summary() {
    echo -e "${YELLOW}[6/6]${NC} Creating summary..."
    
    cat > "$PROJECT_ROOT/.FLATPAK_SETUP_SUMMARY.txt" << EOF
╔════════════════════════════════════════════════════════════════╗
║     Local Development Environment Setup Complete               ║
╚════════════════════════════════════════════════════════════════╝

Setup Date: $(date)
Environment: Flatpak IDE (no Docker)

✓ CREATED DIRECTORIES:
  - data/nextcloud/     (user files and database)
  - data/postgresql/    (database data)
  - data/redis/         (cache data)
  - data/tmp/           (temporary files)
  - logs/               (service logs)

✓ CREATED CONFIGURATION FILES:
  - .env.local                      (environment variables)
  - config/local/nginx.conf         (web server)
  - config/local/php-fpm.conf       (PHP processor)
  - config/local/redis.conf         (cache server)

✓ CREATED HELPER SCRIPTS:
  - scripts/local-services-start.sh (start all services)
  - scripts/local-services-stop.sh  (stop all services)

✓ INITIALIZED DATABASE:
  - data/nextcloud/nextcloud.db     (SQLite development DB)
  - User data directories
  - Tables for AppConfig, Users, Preferences

╔════════════════════════════════════════════════════════════════╗
║                    NEXT STEPS                                  ║
╚════════════════════════════════════════════════════════════════╝

1. Start local services:
   bash scripts/local-services-start.sh

2. Start PHP development server:
   cd $PROJECT_ROOT
   php -S 127.0.0.1:8000 -t nextcloud/

3. Access Nextcloud:
   http://127.0.0.1:8000
   or via Nginx at:
   http://127.0.0.1:8080

4. Run tests:
   bash tests/local-environment-tests.sh run

5. Stop services:
   bash scripts/local-services-stop.sh

╔════════════════════════════════════════════════════════════════╗
║              CONFIGURATION DETAILS                             ║
╚════════════════════════════════════════════════════════════════╝

Admin User: admin
Admin Password: admin123
Database: SQLite (data/nextcloud/nextcloud.db)
Redis Port: 6379
Nginx Port: 8080
PHP Dev Server Port: 8000

For full documentation, see: FLATPAK_SETUP.md

EOF
    cat "$PROJECT_ROOT/.FLATPAK_SETUP_SUMMARY.txt"
    echo ""
}

###############################################################################
# Main Execution
###############################################################################
main() {
    if ! check_requirements; then
        echo -e "${RED}Setup failed: Missing required tools${NC}"
        exit 1
    fi
    
    create_directories
    create_configs
    init_database
    create_helpers
    create_summary
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     ✓ Local Development Environment Ready                      ║${NC}"
    echo -e "${GREEN}║     Run: bash scripts/local-services-start.sh                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
}

main "$@"
