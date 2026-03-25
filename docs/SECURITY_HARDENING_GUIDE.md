# Security Guide

Nextcloud setup with proper security configuration. Nothing fancy, just the basics that actually matter.

## The approach

We use a model where services run with minimal permissions. There's a user for the app (UID 5000), a user for rootless containers (UID 5001), and root mostly stays out of the picture. Secrets go in a file with 600 permissions so only the owner can read them. Networks are isolated, filesystem is mostly read-only where it makes sense.

## Users and permissions

The setup creates these accounts:

- `root` (UID 0) - handles system stuff only
- `nextcloud-app` (UID 5000) - runs the app
- `nextcloud-rootless` (UID 5001) - runs rootless containers if you're using that

If you're doing rootless (which you should, it's more secure), UIDs/GIDs map like this:

```
Host UIDs 100000-165535 map to container UIDs 0-65535
So container UID 0 (root-in-container) is actually UID 100000 (unprivileged) on the host
```

File permissions should be:

- `.env.secure` → 600 (only owner reads)
- `.secrets/` → 700 (only owner accesses)
- `config/ssl/` → 644 (readable by all, writable by owner)
- `data/` → 750 (owner and group access)
- `scripts/` → 755 (executable by all)

## Getting started

Run this in order:

```bash
# 1. Initial setup
sudo bash scripts/environment-setup.sh

# 2. If you want rootless (recommended)
sudo bash scripts/rootless-setup.sh

# 3. Check for obvious problems
bash scripts/security-audit.sh

# 4. Read what it found
cat logs/security-audit-report-*.txt
```

## Firewall

You need to let traffic through to ports 80 and 443.

Ubuntu/Debian:

```bash
sudo ufw default deny incoming
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Check it worked:

```bash
sudo ufw status verbose
```

CentOS/RHEL:

```bash
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

## Best practices

### Passwords

- Store them in `.env.secure` with 600 permissions (mode is important)
- Use something that looks like `Tr#$mK9@pL2&vQx5!zN1yW8bC3dJ6fH4` (32+ characters, mix of everything)
- Don't use the same password for everything
- Don't commit `.env.secure` to git

Generate decent passwords with:

```bash
pwgen -s -y 32
```

### Access control

- Use rootless mode if you can (containers run as unprivileged user)
- Limit sudo access - add only what's needed to `/etc/sudoers` via `visudo`
- Don't run containers as root
- Avoid privileged mode

### Network

- Use HTTPS/TLS (Let's Encrypt is free)
- Block HTTP if you're not using it
- Don't expose ports to 0.0.0.0 if you don't need to
- If possible, restrict to 127.0.0.1 for management APIs

```bash
# Good - only from localhost
ports: ["127.0.0.1:5432:5432"]

# Bad - exposed to the world
ports: ["0.0.0.0:5432:5432"]
```

### Container images

- Use specific versions: `nextcloud:28-fpm-alpine` (not `latest`)
- Run as non-root user when possible
- Use read-only filesystem if the app supports it
- Don't use `privileged: true` unless you really need it

### Logging

```bash
# Check logs
docker-compose logs -f nextcloud

# Archive old logs to save space
find logs/ -name "*.log" -mtime +30 -exec gzip {} \;

# Search for problems
docker-compose logs | grep ERROR
```

### Keep things updated

Run these occasionally:

```bash
# Check for updates
docker-compose pull

# Apply updates
docker-compose up -d

# Backup before updating
bash scripts/backup.sh
bash scripts/update.sh

# Run security audit after changes
bash scripts/security-audit.sh
```

## Verifying everything

```bash
# Check who's running
ps aux | grep nextcloud
ps aux | grep docker

# Check file permissions on secrets
ls -la .env.secure   # Should be -rw------- 
ls -la .env.local    # Should be -rw------- 

# Check for world-writable files (bad)
find /opt/nextcloud-docker-stack -perm -002 -type f

# Check what ports are listening
sudo netstat -tuln | grep LISTEN
```

## When things go wrong

### Can't read .env.secure?

```bash
# Check permissions
ls -la .env.secure

# Should show: -rw------- (600)
# If not:
chmod 600 .env.secure
```

### Database connection fails

```bash
# Check if it's running
docker-compose ps postgres

# See what the error is
docker-compose logs postgres

# Try connecting manually
docker-compose exec postgres psql -U nextcloud -d nextcloud -c "SELECT 1;"
```

### SSL/TLS problems

```bash
# Check the certificate
openssl x509 -in config/ssl/fullchain.pem -noout -enddate

# Make sure domain matches
openssl x509 -in config/ssl/fullchain.pem -noout -subject

# Restart to reload
docker-compose restart nginx
```

### Rootless isn't working

```bash
# Check if the kernel supports it
cat /proc/sys/kernel/unprivileged_userns_clone

# If it says 0, enable it:
echo "kernel.unprivileged_userns_clone = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Test it
su - nextcloud-rootless
podman --version
```

## Useful resources

- Nextcloud docs: https://docs.nextcloud.com/server/latest/admin_manual/
- Docker security: https://docs.docker.com/engine/security/
- Podman: https://github.com/containers/podman
- Linux security basics: https://wiki.ubuntu.com/Security
