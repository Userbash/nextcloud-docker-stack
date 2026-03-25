# Nextcloud Docker Stack — Quick Reference

All the commands you need day-to-day, in one place.

---

## Setup and Launch

| Task | Command |
|------|---------|
| One-click local dev setup | `bash setup.sh --dev` |
| One-click production setup | `bash setup.sh --domain my.site --email me@site.com` |
| Manual setup — copy config | `cp .env.example .env && chmod 600 .env` |
| Start all services | `docker-compose up -d` |
| Start with rootless Podman | `bash setup.sh --rootless --dev` |
| Re-start after config change | `docker-compose down && docker-compose up -d` |

---

## Daily Operations

| Task | Command |
|------|---------|
| Check container status | `docker-compose ps` |
| View all logs (live) | `docker-compose logs -f` |
| View one service logs | `docker-compose logs -f app` |
| Stop all containers | `docker-compose down` |
| Stop without removing volumes | `docker-compose stop` |
| Restart one service | `docker-compose restart app` |
| Pull latest images + redeploy | `docker-compose pull && docker-compose up -d` |

---

## Maintenance

| Task | Command |
|------|---------|
| Backup database and files | `bash scripts/backup.sh` |
| Update images and restart | `bash scripts/update.sh` |
| Health check all services | `bash scripts/health-check.sh` |
| Post-deploy verification | `bash FIRST_STEPS.sh` |
| Run full test suite | `./tests/run_tests.sh all` |
| Run security audit | `bash scripts/security-audit.sh` |

---

## Diagnostics

| Task | Command |
|------|---------|
| Container resource usage | `docker stats` |
| Disk usage (host) | `df -h` |
| Disk usage (Docker volumes) | `docker system df` |
| List all containers (inc. stopped) | `docker ps -a` |
| Check what's on port 80 | `sudo lsof -i :80` |
| Check what's on port 5432 | `sudo lsof -i :5432` |
| Network connectivity test | `docker-compose exec app nc -zv db 5432` |
| Container inspect | `docker inspect nextcloud-app` |

---

## Database

| Task | Command |
|------|---------|
| Open psql prompt | `docker-compose exec db psql -U "$POSTGRES_USER" "$POSTGRES_DB"` |
| Check DB is ready | `docker-compose exec db pg_isready -U "$POSTGRES_USER"` |
| Check database size | `docker-compose exec db psql -U "$POSTGRES_USER" -c "SELECT pg_size_pretty(pg_database_size('$POSTGRES_DB'));"` |
| Manual DB dump | `docker-compose exec -T db pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > backup.sql` |
| Restore from dump | `docker-compose exec -T db psql -U "$POSTGRES_USER" "$POSTGRES_DB" < backup.sql` |
| Vacuum database | `docker-compose exec db vacuumdb -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f` |

---

## Redis

| Task | Command |
|------|---------|
| Ping Redis | `docker-compose exec redis redis-cli ping` |
| Redis info | `docker-compose exec redis redis-cli info` |
| Flush cache (use with care) | `docker-compose exec redis redis-cli FLUSHALL` |

---

## Nextcloud (occ CLI)

| Task | Command |
|------|---------|
| Nextcloud version | `docker-compose exec app occ -V` |
| Run upgrade | `docker-compose exec app occ upgrade` |
| Run maintenance mode | `docker-compose exec app occ maintenance:mode --on` |
| Disable maintenance mode | `docker-compose exec app occ maintenance:mode --off` |
| List background jobs | `docker-compose exec app occ background:queue:status` |
| Scan files | `docker-compose exec app occ files:scan --all` |
| List apps | `docker-compose exec app occ app:list` |
| Disable an app | `docker-compose exec app occ app:disable <appname>` |

---

## SSL / Certificates

| Task | Command |
|------|---------|
| Check certificate expiry | `openssl x509 -enddate -noout -in config/ssl/fullchain.pem` |
| Check certificate details | `openssl x509 -text -noout -in config/ssl/fullchain.pem` |
| Test HTTPS | `curl -v https://your-domain.com` |
| Renew (Certbot container) | `docker-compose exec certbot certbot renew --force-renewal` |
| Renew (host certbot) | `sudo certbot renew --nginx` |
| Generate self-signed cert | `openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout config/ssl/privkey.pem -out config/ssl/fullchain.pem -subj "/CN=localhost"` |

---

## Security

| Task | Command |
|------|---------|
| Fix .env permissions | `chmod 600 .env` |
| Fix data dir permissions | `sudo chown -R 33:33 /srv/nextcloud/data && chmod -R 770 /srv/nextcloud/data` |
| Generate strong password | `openssl rand -base64 32` |
| Check world-writable files | `find . -perm -002 -type f -not -path './.git/*'` |
| Check open ports | `sudo netstat -tuln | grep LISTEN` |
| Run security audit | `bash scripts/security-audit.sh` |

---

## Firewall (Ubuntu/Debian — ufw)

```bash
sudo ufw default deny incoming
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP (Let's Encrypt)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
sudo ufw status
```

---

## Recovery

| Task | Command |
|------|---------|
| Remove all containers and volumes | `docker-compose down -v` |
| Remove all unused Docker data | `docker system prune -a` |
| Fresh start (destructive) | `docker-compose down -v && cp .env.example .env && docker-compose up -d` |
| Check all logs for errors | `docker-compose logs | grep -i error` |
| Save debug bundle | See [README.md Troubleshooting](../README.md#troubleshooting) |

---

## Environment Variables Reference

See `.env.example` for all variables with comments.
The most important ones to change before going live:

```bash
POSTGRES_PASSWORD=<strong-random-password>
NEXTCLOUD_ADMIN_PASSWORD=<strong-random-password>
NEXTCLOUD_DOMAIN=<your-domain>
LETSENCRYPT_EMAIL=<your-email>
```

---

*For detailed troubleshooting, see [docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md).*  
*For security guidance, see [docs/SECURITY_HARDENING_GUIDE.md](SECURITY_HARDENING_GUIDE.md).*
