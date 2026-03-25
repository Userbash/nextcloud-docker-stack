# Nextcloud Docker Stack - Comprehensive Troubleshooting Guide

Complete troubleshooting guide for the Nextcloud Docker Stack deployment including diagnosis tools, common issues, and solutions.

## Table of Contents

1. [Getting Help](#getting-help)
2. [Diagnosis Tools](#diagnosis-tools)
3. [Common Issues & Solutions](#common-issues--solutions)
4. [Database Troubleshooting](#database-troubleshooting)
5. [SSL/TLS Issues](#ssltls-issues)
6. [Performance Problems](#performance-problems)
7. [Security Issues](#security-issues)
8. [Networking Problems](#networking-problems)
9. [Container-Specific Issues](#container-specific-issues)
10. [Disaster Recovery](#disaster-recovery)
11. [Podman-Specific Issues](#issue-podman--short-name-did-not-resolve-to-an-alias)

## Getting Help

### Before Seeking Help

Always collect diagnostic information first:

```bash
# Full diagnostics
./tests/run_tests.sh all

# Check logs
./tests/run_tests.sh logs 6  # Last 6 hours

# Save reports for reference
mkdir -p debug-reports
cp test-reports/* debug-reports/
```

### When Reporting Issues

Include:
1. Output from `./tests/run_tests.sh all`
2. Relevant log excerpts from test-reports/
3. Docker/Podman version: `docker --version` or `podman --version`
4. OS information: `uname -a`
5. Your `.env` file (sanitized of passwords)
6. Error message and steps to reproduce

## Diagnosis Tools

### Test Suite

```bash
# Run comprehensive tests
./tests/run_tests.sh all

# Result: Shows configuration issues, missing files, permission problems
```

### Log Analysis

```bash
# Analyze recent logs for issues
./tests/run_tests.sh logs 1

# Result: Identifies critical errors with suggestions
```

### Container Status Check

```bash
# View container status
docker ps -a
docker stats

# Alternative with Podman
podman ps -a
podman stats
```

### Manual Log Inspection

```bash
# Watch logs in real-time
docker-compose logs -f

# View specific container logs
docker logs -f nextcloud-web-1
docker logs -f nextcloud-db-1

# View logs from specific time
docker logs --since 2024-01-15T10:00:00 nextcloud-web-1
```

### System Resource Checking

```bash
# Disk usage
df -h
du -sh /srv/nextcloud
du -sh /var/lib/postgresql

# Memory and CPU
top -b -n 1 | head -20
free -h
vmstat 1 5

# Network connections
netstat -tlnp | grep -E "9000|80|443|5432"
ss -tlnp
```

## Common Issues & Solutions

### Issue: Container Fails to Start

**Symptoms**: Container exits immediately or shows "unhealthy"

**Diagnosis**:
```bash
# Check container logs
docker logs nextcloud-web-1

# Check container status
docker ps -a

# Inspect container details
docker inspect nextcloud-web-1
```

**Solutions**:

1. **Missing .env file**
   ```bash
   cp .env.example .env
   nano .env  # Configure required variables
   docker-compose up -d
   ```

2. **Invalid environment variables**
   ```bash
   # Check .env syntax
   grep -E "^[A-Z_]+=" .env
   
   # Look for special characters that need escaping
   grep '[$`]' .env
   ```

3. **Out of disk space**
   ```bash
   df -h
   du -sh /srv/nextcloud
   docker run --rm -v /root:/mnt alpine du -sh /mnt
   ```

4. **Port already in use**
   ```bash
   # Check what's using port 80, 443, 9000
   netstat -tlnp | grep -E "80|443|9000"
   lsof -iTCP -sTCP:LISTEN -P -n | grep -E "80|443|9000"
   ```

### Issue: "Connection refused" Errors

**Symptoms**: 
- Nextcloud can't connect to database or Redis
- Logs show "connection refused" on port 5432 or 6379

**Diagnosis**:
```bash
# Test connectivity between containers
docker exec nextcloud-web-1 nc -zv nextcloud-db-1 5432
docker exec nextcloud-web-1 nc -zv nextcloud-redis-1 6379

# Check if containers are running
docker ps | grep -E "db|redis"

# View database logs
docker logs nextcloud-db-1 | tail -20

# Check network connectivity
docker network inspect nextcloud_default
```

**Solutions**:

1. **Database container crashed**
   ```bash
   docker-compose logs nextcloud-db-1
   docker-compose restart nextcloud-db-1
   docker exec nextcloud-db-1 pg_isready -U nextcloud
   ```

2. **Wrong connection credentials**
   ```bash
   # Check .env variables
   grep -E "DATABASE|POSTGRES" .env
   
   # Verify in container environment
   docker exec nextcloud-web-1 env | grep POSTGRES
   ```

3. **Network issues**
   ```bash
   # Recreate network
   docker-compose down
   docker network rm nextcloud_default
   docker-compose up -d
   ```

### Issue: Nextcloud Web Interface Unavailable

**Symptoms**:
- Nginx shows error or blank page
- Browser times out or shows 502/503
- HTTPS certificate warnings

**Diagnosis**:
```bash
# Test Nginx
docker exec nextcloud-web-1 nginx -t

# Test PHP-FPM
docker exec nextcloud-web-1 php-fpm -t

# Check Nextcloud logs
docker exec nextcloud-web-1 cat /var/www/html/data/nextcloud.log | tail -50

# Test web connectivity
docker exec nextcloud-web-1 curl -v http://localhost/status.php
```

**Solutions**:

1. **Nginx configuration error**
   ```bash
   docker exec nextcloud-web-1 nginx -t
   docker logs nextcloud-web-1
   docker-compose restart nextcloud-web-1
   ```

2. **PHP-FPM not responding**
   ```bash
   docker ps | grep php
   docker restart nextcloud-web-1
   docker exec nextcloud-web-1 php -v
   ```

3. **Nextcloud data directory permissions**
   ```bash
   # Check permissions
   ls -la /srv/nextcloud/data/
   
   # Fix permissions
   sudo chown -R 33:33 /srv/nextcloud/data/
   chmod 770 /srv/nextcloud/data/
   ```

4. **Sufficient disk space**
   ```bash
   df -h /srv/nextcloud
   du -sh /srv/nextcloud/*
   ```

## Database Troubleshooting

### Issue: "SQLSTATE[HY000]: General error: server has gone away"

**Causes**: Database crashed, ran out of memory, lost connection

**Solutions**:

1. **Check database status**
   ```bash
   docker exec nextcloud-db-1 pg_isready -U nextcloud
   docker logs nextcloud-db-1 | tail -50
   ```

2. **Increase max_connections**
   ```bash
   # In .env
   POSTGRES_INITDB_ARGS="-c max_connections=200"
   
   # Restart database
   docker-compose down
   docker volume rm nextcloud_postgresql
   docker-compose up -d
   ```

3. **Increase shared_buffers**
   ```bash
   # In .env
   POSTGRES_INITDB_ARGS="-c shared_buffers=256MB"
   ```

4. **Check available memory**
   ```bash
   free -h
   docker stats nextcloud-db-1
   
   # Increase container memory in docker-compose.yaml
   ```

### Issue: Database Corruption

**Symptoms**: PostgreSQL won't start, persistent errors

**Recovery**:

```bash
# 1. Stop services
docker-compose down

# 2. Backup corrupted data
mv /var/lib/postgresql /var/lib/postgresql.bak

# 3. Rebuild database
docker-compose up -d nextcloud-db-1

# 4. Wait for initialization
sleep 10
docker exec nextcloud-db-1 pg_isready -U nextcloud

# 5. Restore from backup if available
docker exec -i nextcloud-db-1 psql -U nextcloud nextcloud < backup.sql

# 6. Start all services
docker-compose up -d
```

### Issue: Database Full / Out of Space

**Diagnosis**:
```bash
# Check database size
docker exec nextcloud-db-1 psql -U nextcloud -c \
  "SELECT pg_size_pretty(pg_database_size('nextcloud'));"

# Check table sizes
docker exec nextcloud-db-1 psql -U nextcloud -c \
  "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) 
   FROM pg_tables ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"
```

**Solutions**:

1. **Increase disk space**
   ```bash
   # Add more space to partition
   # Check with: df -h /var/lib/postgresql
   ```

2. **Clean old logs and sessions**
   ```bash
   # PostgreSQL logs
   docker exec nextcloud-db-1 find /var/log/postgresql -name "*.log" -delete
   
   # Session files
   find /var/lib/php/sessions -type f -mtime +30 -delete
   ```

3. **Vacuum database** (offline maintenance)
   ```bash
   docker-compose stop
   docker exec -i nextcloud-db-1 vacuumdb -U nextcloud -d nextcloud -f
   docker-compose start
   ```

## SSL/TLS Issues

### Issue: SSL Certificate Verification Failed

**Symptoms**: HTTPS not working, browser warnings, "certificate verify failed"

**Diagnosis**:
```bash
# Check certificate file
ls -la config/ssl/
openssl x509 -text -in config/ssl/fullchain.pem

# Check expiry date
openssl x509 -enddate -noout -in config/ssl/fullchain.pem

# Test certificate validity
echo | openssl s_client -servername nextcloud.example.com -connect localhost:443
```

**Solutions**:

1. **Certificate expired**
   ```bash
   # Check expiry
   openssl x509 -enddate -noout -in config/ssl/fullchain.pem
   
   # Renew with Certbot
   docker exec certbot certbot renew --force-renewal
   ```

2. **Certificate not found**
   ```bash
   # Check config/ssl directory
   ls -la config/ssl/
   
   # Generate self-signed for testing
   mkdir -p config/ssl
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
     -keyout config/ssl/privkey.pem \
     -out config/ssl/fullchain.pem \
     -subj "/CN=nextcloud.local"
   ```

3. **Private key has wrong permissions**
   ```bash
   # Fix permissions (CRITICAL)
   chmod 600 config/ssl/privkey.pem
   
   # Restart services
   docker-compose restart
   ```

### Issue: Certbot Renewal Failed

**Symptoms**: Certificate renewal fails, "renewal skipped" messages

**Causes**:
- Domain DNS misconfigured
- Rate limits exceeded
- Permission issues
- WebRoot path incorrect

**Solutions**:

1. **Test renewal (dry-run)**
   ```bash
   docker exec certbot certbot renew --dry-run
   docker logs certbot | tail -50
   ```

2. **Check domain configuration**
   ```bash
   # Verify domain resolves
   nslookup nextcloud.example.com
   
   # Check DNS propagation
   dig nextcloud.example.com
   
   # Verify from container
   docker exec certbot nslookup nextcloud.example.com
   ```

3. **Check rate limits**
   - Let's Encrypt limit: 50 renewals per domain per week
   - Solution: Wait if limit exceeded, or use different domain

4. **Verify .well-known directory**
   ```bash
   # Check WebRoot path
   ls -la /srv/nextcloud/.well-known/acme-challenge/
   
   # Should be writable
   touch /srv/nextcloud/.well-known/acme-challenge/test
   rm /srv/nextcloud/.well-known/acme-challenge/test
   ```

5. **Manual renewal**
   ```bash
   docker exec certbot certbot certonly --webroot \
     -w /var/www/html \
     -d nextcloud.example.com \
     --force-renewal
   ```

## Performance Problems

### Issue: High CPU Usage

**Diagnosis**:
```bash
# See per-container CPU
docker stats

# Find CPU-heavy processes
docker exec nextcloud-web-1 top -b -n 1 | head -20

# Check Nextcloud logs for issues
docker exec nextcloud-web-1 tail -f /var/www/html/data/nextcloud.log
```

**Solutions**:

1. **Disable intensive operations**
   ```bash
   # Check running Cron jobs
   docker exec nextcloud-web-1 occ background:queue:status
   
   # Stop background jobs
   docker exec nextcloud-web-1 occ background:mode manual
   ```

2. **Optimize PHP settings** (edit php/php.ini):
   ```ini
   [PHP]
   memory_limit = 512M
   max_input_time = 300
   
   [opcache]
   opcache.enable = 1
   opcache.memory_consumption = 128
   opcache.interned_strings_buffer = 16
   ```

3. **Check for concurrent file scans**
   ```bash
   docker exec nextcloud-web-1 ps aux | grep -i scan
   docker exec nextcloud-web-1 ps aux | grep -i upgrade
   ```

### Issue: High Memory Usage

**Diagnosis**:
```bash
# See per-container memory
docker stats

# Check detailed memory
docker exec nextcloud-web-1 free -h
docker exec nextcloud-db-1 free -h
```

**Solutions**:

1. **Increase memory limits** in docker-compose.yaml:
   ```yaml
   services:
     nextcloud-web:
       deploy:
         resources:
           limits:
             memory: 2G
     nextcloud-db:
       deploy:
         resources:
           limits:
             memory: 1G
   ```

2. **Optimize PHP memory** in php/php.ini:
   ```ini
   memory_limit = 512M
   ```

3. **Check for memory leaks**
   ```bash
   docker logs nextcloud-web-1 | grep -i "exhausted\|fatal"
   ```

### Issue: Slow Response Times / Timeouts

**Diagnosis**:
```bash
# Check response time
time curl http://nextcloud.example.com/

# Monitor in real-time
docker stats
docker logs -f nextcloud-web-1

# Check database query times
docker exec nextcloud-db-1 tail -f /var/log/postgresql/postgresql.log | grep SLOW
```

**Solutions**:

1. **Verify Redis is working**
   ```bash
   docker exec nextcloud-redis-1 redis-cli ping
   docker exec nextcloud-redis-1 redis-cli info stats
   ```

2. **Enable Redis in config**
   ```bash
   # In .env
   NEXTCLOUD_REDIS_HOST=nextcloud-redis-1
   NEXTCLOUD_REDIS_PORT=6379
   
   # Or in Nextcloud config
   docker exec nextcloud-web-1 occ config:set --value redis \
     --type string system memcache.locking Predis
   ```

3. **Optimize database**
   ```bash
   # Analyze queries
   docker exec nextcloud-db-1 psql -U nextcloud -c \
     "SELECT query, count, mean_exec_time FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 10;"
   ```

## Security Issues

### Issue: Permission Denied Errors

**Symptoms**: Files can't be modified, uploads fail, "permission denied"

**Diagnosis**:
```bash
# Check file permissions
ls -la /srv/nextcloud/data/
stat /srv/nextcloud/data/

# Check user/group
docker exec nextcloud-web-1 id
```

**Solutions**:

1. **Fix directory ownership** (Docker):
   ```bash
   sudo chown -R 33:33 /srv/nextcloud
   sudo chmod -R 770 /srv/nextcloud/data
   ```

2. **Fix directory ownership** (Rootless Podman):
   ```bash
   podman unshare chown -R 33:33 /srv/nextcloud
   podman unshare chmod -R 770 /srv/nextcloud/data
   ```

3. **Fix .env file permissions**
   ```bash
   chmod 600 .env
   chmod 600 config/ssl/privkey.pem
   ```

### Issue: Insecure .env File

**Diagnosis**:
```bash
# Check .env permissions
ls -la .env

# Check if exposed
git log -p | grep POSTGRES_PASSWORD
grep CHANGE_ME .env
```

**Solutions**:

1. **Fix .env permissions**
   ```bash
   chmod 600 .env
   chmod 600 .env.example
   ```

2. **Verify .gitignore**
   ```bash
   cat .gitignore | grep "\.env"
   ```

3. **Regenerate exposed passwords** (if committed to git):
   ```bash
   # Generate new secure passwords
   openssl rand -base64 32
   
   # Update .env
   nano .env
   
   # Restart containers
   docker-compose restart
   ```

## Networking Problems

### Issue: Can't Access Nextcloud from Network

**Symptoms**: Localhost works but external IP doesn't, connection refused

**Diagnosis**:
```bash
# Test local access
curl -v http://localhost/

# Test from another machine
curl -v http://YOUR_SERVER_IP/

# Check listening ports
netstat -tlnp | grep -E "80|443"

# Check DNS
nslookup nextcloud.example.com
```

**Solutions**:

1. **Check firewall**
   ```bash
   # UFW (Ubuntu)
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw status
   
   # iptables
   sudo iptables -L -n | grep -E "80|443"
   ```

2. **Check port forwarding**
   ```bash
   # Show port mappings
   docker ps --format "table {{.Names}}\t{{.Ports}}"
   
   # Test ports
   telnet YOUR_SERVER_IP 80
   telnet YOUR_SERVER_IP 443
   ```

3. **Configure nginx properly**
   ```bash
   # Check nginx config
   docker exec nextcloud-web-1 nginx -t
   
   # Review server_name in config
   grep "server_name" nginx/nginx.conf
   ```

### Issue: DNS Resolution Fails

**Symptoms**: nslookup works but Docker can't resolve, "name resolution failed"

**Diagnosis**:
```bash
# From host
nslookup nextcloud.example.com

# From container
docker exec nextcloud-web-1 nslookup nextcloud.example.com
docker exec nextcloud-web-1 cat /etc/resolv.conf
```

**Solutions**:

1. **Restart networking**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

2. **Check Docker DNS settings**
   ```bash
   cat /etc/docker/daemon.json
   
   # Configure DNS in daemon.json
   {
     "dns": ["8.8.8.8", "8.8.4.4"]
   }
   ```

## Container-Specific Issues

### Nextcloud Container Issues

**Nextcloud won't start**:
```bash
docker logs nextcloud-web-1
docker exec nextcloud-web-1 php -v
docker exec nextcloud-web-1 php -m  # Check extensions
```

**Upgrade problems**:
```bash
# Check current version
docker exec nextcloud-web-1 occ -v

# Run upgrade
docker exec nextcloud-web-1 occ upgrade

# Disable apps if upgrade fails
docker exec nextcloud-web-1 occ app:disable problematic_app
```

### PHP-FPM Issues

**PHP slow processing**:
```bash
docker exec nextcloud-web-1 php-fpm -t
docker exec nextcloud-web-1 ps aux | grep php-fpm
docker stats nextcloud-web-1
```

**Fix PHP-FPM**:
```bash
docker-compose restart nextcloud-web-1
docker exec nextcloud-web-1 php-fpm -t
```

### Nginx Issues

**Nginx errors**:
```bash
docker logs nextcloud-web-1
docker exec nextcloud-web-1 nginx -t
docker exec nextcloud-web-1 curl -v http://localhost
```

**Fix Nginx**:
```bash
# Reload config
docker exec nextcloud-web-1 nginx -s reload

# Restart if needed
docker-compose restart nextcloud-web-1
```

### PostgreSQL Issues

**Database startup problems**:
```bash
docker logs nextcloud-db-1
docker exec nextcloud-db-1 pg_isready
docker exec nextcloud-db-1 psql -U nextcloud \
  -c "SELECT version();"
```

**PostgreSQL won't start after crash**:
```bash
# Verify integrity
docker exec nextcloud-db-1 pg_resetwal -D /var/lib/postgresql/data

# Or reset database
docker-compose down
docker volume remove nextcloud_postgresql
docker-compose up -d
```

### Redis Issues

**Redis connection problems**:
```bash
docker exec nextcloud-redis-1 redis-cli ping
docker exec nextcloud-redis-1 redis-cli info
docker logs nextcloud-redis-1
```

**Clear Redis cache**:
```bash
docker exec nextcloud-redis-1 redis-cli FLUSHALL
```

## Disaster Recovery

### Complete System Restore

```bash
# 1. Backup current state
tar -czf nextcloud_backup.tar.gz /srv/nextcloud/ /var/lib/postgresql/

# 2. Stop services
docker-compose down

# 3. Restore from backup
tar -xzf nextcloud_backup_OLD.tar.gz -C /

# 4. Start services
docker-compose up -d

# 5. Verify operation
./tests/run_tests.sh health
```

### Database Restore

```bash
# 1. Stop application
docker-compose stop nextcloud-web-1

# 2. Restore database
docker exec -i nextcloud-db-1 psql -U nextcloud nextcloud < backup.sql

# 3. Start application
docker-compose start nextcloud-web-1

# 4. Verify
docker exec nextcloud-web-1 occ check
```

### Rebuild from Backup

```bash
# 1. New directory
mkdir -p /srv/nextcloud-recovery

# 2. Extract backup
tar -xzf nextcloud_backup.tar.gz -C /srv/nextcloud-recovery/

# 3. Update docker-compose to use recovery path
# Edit docker-compose.yaml and point volumes to recovery directory

# 4. Start
docker-compose up -d

# 5. Verify
./tests/run_tests.sh all
```

## When All Else Fails

### Start Fresh

```bash
# 1. Stop everything
docker-compose down -v  # -v removes all volumes

# 2. Remove containers and images
docker system prune -a

# 3. Clean directories
rm -rf /srv/nextcloud /var/lib/postgresql /var/lib/redis

# 4. Start fresh
cp .env.example .env
nano .env
docker-compose up -d

# 5. Run tests
./tests/run_tests.sh all
```

### Collect Debug Information for Support

```bash
# Create debug bundle
mkdir -p debug-bundle
docker ps -a > debug-bundle/containers.txt
docker images > debug-bundle/images.txt
docker network ls > debug-bundle/networks.txt
docker volume ls > debug-bundle/volumes.txt
docker-compose config > debug-bundle/docker-compose-expanded.yml
./tests/run_tests.sh all > debug-bundle/tests.txt 2>&1
cp test-reports/* debug-bundle/

# Sanitize .env
grep -v PASSWORD .env > debug-bundle/.env.sanitized

# Pack it up
tar -czf debug-bundle.tar.gz debug-bundle/
```

## First-Run / Setup Problems

### Issue: `setup.sh` Fails with "Docker daemon is not running"

**Cause**: Docker is installed but the service is not started.

**Fix**:
```bash
sudo systemctl start docker
sudo systemctl enable docker    # Start automatically on boot
sudo systemctl status docker
```

If you just added your user to the `docker` group:
```bash
newgrp docker                   # Apply group change without logging out
# Or log out and back in
```

### Issue: `setup.sh` Fails with "Neither Docker nor Podman found"

**Fix**: Install Docker:
```bash
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker $USER
# Log out and back in, then retry
```

Install Docker Compose v2 separately if needed:
```bash
sudo apt-get install docker-compose-plugin   # Debian/Ubuntu
# or
sudo dnf install docker-compose-plugin       # Fedora/RHEL
```

### Issue: `.env` Variables Not Applied

**Symptoms**: Nextcloud starts with wrong domain, wrong credentials, or old values.

**Cause**: Environment variables are only read at `docker-compose up` time. Changing `.env` after containers start has no effect until you restart.

**Fix**:
```bash
docker-compose down
docker-compose up -d
```

### Issue: First Login Fails ("Invalid credentials")

**Cause**: Admin password in `.env` still has the default `CHANGE_ME` value, or was changed after the Nextcloud container already ran its first-time setup (which writes credentials to the volume).

**Fix** — Option A (fresh start, loses data):
```bash
docker-compose down -v           # Remove volumes
nano .env                        # Fix NEXTCLOUD_ADMIN_PASSWORD
docker-compose up -d             # Re-initialise from scratch
```

**Fix** — Option B (keep data, reset password via occ):
```bash
docker-compose exec app occ user:resetpassword admin
```

### Issue: Nextcloud Installation Page Appears Instead of Login

**Cause**: The Nextcloud volume was wiped, or this is a fresh deployment.

This is normal on first run. Complete the setup wizard, or pre-configure by setting all the `NEXTCLOUD_*` variables in `.env` before the first `docker-compose up`.

### Issue: "Trusted domain" Error After Accessing via IP or Different Hostname

**Symptoms**: "Access through untrusted domain" error page.

**Fix**:
```bash
# Update .env
NEXTCLOUD_TRUSTED_DOMAINS=your-domain.com,192.168.1.10,localhost

# Restart app container
docker-compose restart app

# Or add domain directly via occ
docker-compose exec app occ config:system:set trusted_domains 2 --value=192.168.1.10
```

### Issue: HTTPS Port Not Accessible After `setup.sh --dev`

**Cause**: The self-signed certificate is not trusted by the browser.

**Fix**: Accept the browser security warning (click "Advanced" → "Proceed"), or import the certificate into your OS/browser trust store.

For `curl` tests, use `-k` to skip verification:
```bash
curl -k https://localhost:8443/status.php
```

### Issue: Certbot Container Keeps Restarting

**Cause**: Let's Encrypt cannot reach your server on port 80 (required for HTTP-01 challenge).

**Diagnosis**:
```bash
docker-compose logs certbot
```

Common causes:
- Port 80 is blocked by a cloud security group or firewall
- The domain does not resolve to this server's IP
- Another process is using port 80

**Fix**:
```bash
# Check DNS resolves correctly
nslookup your-domain.com

# Check port 80 is reachable
curl -v http://your-domain.com/.well-known/acme-challenge/test

# Open port 80 in firewall (Ubuntu)
sudo ufw allow 80/tcp
```

### Issue: Containers Start But Nextcloud Shows a Blank Page or "Internal Server Error"

**Diagnosis**:
```bash
docker-compose logs app | tail -50
docker-compose exec app cat /var/www/html/data/nextcloud.log | tail -50
```

Common causes and fixes:

1. **PHP memory limit too low**
   ```bash
   # In .env:
   PHP_MEMORY_LIMIT=1024M
   docker-compose restart app
   ```

2. **Database not ready yet** (race condition on first start)
   ```bash
   docker-compose restart app      # Wait 30 s for DB to finish initialising
   ```

3. **Missing or wrong `NEXTCLOUD_TRUSTED_DOMAINS`**
   ```bash
   grep NEXTCLOUD_TRUSTED_DOMAINS .env
   docker-compose restart app
   ```

4. **OPcache stale cache after update**
   ```bash
   docker-compose restart app
   ```

### Issue: Backup Script Fails with "service might not be ready"

**Cause**: The database container is not running when `backup.sh` is invoked.

**Fix**:
```bash
docker-compose ps db              # Should show "Up"
docker-compose start db           # Start if stopped
bash scripts/backup.sh            # Retry
```

### Issue: `docker stats` Shows 100% Memory, Containers Killing Each Other

**Cause**: Total memory limits exceed available RAM.

**Fix**: Reduce limits in `docker-compose.yaml` or add swap:
```bash
# Add 4 GB swap on Linux
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
```

---

### Issue: Podman — "short-name did not resolve to an alias"

**Full error**:
```
Error: short-name "postgres:16-alpine" did not resolve to an alias and
no unqualified-search-registries are defined in "/etc/containers/registries.conf"
exit code: 125
```

**Root cause**: Unlike Docker, Podman enforces explicit registry resolution for
security reasons. When no `unqualified-search-registries` are configured, Podman
refuses to guess which registry (Docker Hub, Quay, etc.) a short image name
such as `postgres:16-alpine` should be pulled from.

**Solution A — system-level fix** (recommended for shared/production hosts):

```bash
# Append docker.io as the default search registry
echo 'unqualified-search-registries = ["docker.io"]' \
  | sudo tee -a /etc/containers/registries.conf

# Verify
grep unqualified-search-registries /etc/containers/registries.conf
```

For a per-user (rootless) fix instead of system-wide:
```bash
mkdir -p ~/.config/containers
cat > ~/.config/containers/registries.conf << 'EOF'
unqualified-search-registries = ["docker.io"]

[[registry]]
location = "docker.io"
insecure = false
EOF
```

**Solution B — project-level fix** (already applied in this repository):

All image names in `docker-compose.yaml` and `docker-compose.rootless.yaml` now
use Fully Qualified Image Names (FQIN) that include the registry prefix, so
Podman never needs to guess:

| Short name (old) | FQIN (current) |
|---|---|
| `postgres:16-alpine` | `docker.io/library/postgres:16-alpine` |
| `redis:7-alpine` | `docker.io/library/redis:7-alpine` |
| `nextcloud:27-fpm-alpine` | `docker.io/library/nextcloud:27-fpm-alpine` |
| `nginx:1.25-alpine` | `docker.io/library/nginx:1.25-alpine` |
| `certbot/certbot:latest` | `docker.io/certbot/certbot:latest` |

**Security note**: Do **not** work around this error by running containers with
`--privileged`, disabling SELinux/AppArmor, or using `chmod 777` on data
directories. These actions introduce serious security vulnerabilities and are
unnecessary to fix registry resolution.

---

## See Also

- [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - All commands in one place
- [SECURITY_HARDENING_GUIDE.md](SECURITY_HARDENING_GUIDE.md) - Security setup
- [SECURITY.md](SECURITY.md) - Security basics
- [README.md](../README.md) - Full project documentation
