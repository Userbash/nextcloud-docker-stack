#!/bin/bash
# Backup Nextcloud databases and files
# Usage: ./scripts/backup.sh
# Supports both Docker and Podman

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname "$script_dir")"

BACKUP_DIR="$project_dir/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

# Detect if using Podman or Docker
CONTAINER_CMD="docker"
if command -v podman &> /dev/null && [ -n "${PODMAN_USERNS_MODE:-}" ]; then
    CONTAINER_CMD="podman"
fi

COMPOSE_CMD="${CONTAINER_CMD}-compose"

mkdir -p "$BACKUP_DIR"

echo "📦 Backing up Nextcloud (using $CONTAINER_CMD)..."
echo ""

# Verify environment
if [ ! -f "$project_dir/.env" ]; then
    echo "❌ Error: .env file not found!"
    exit 1
fi

set -a
# shellcheck source=/dev/null
source "$project_dir/.env"
set +a

# ==============================================
# Backup Database
# ==============================================
echo "  → Database backup..."
BACKUP_FILE="$BACKUP_DIR/db_${TIMESTAMP}.sql.gz"

if cd "$project_dir" && $COMPOSE_CMD exec -T db \
    pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" 2>/dev/null | \
    gzip > "$BACKUP_FILE"; then
    DB_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "    ✅ Database backed up (${DB_SIZE})"
    # Create checksum for integrity verification
    sha256sum "$BACKUP_FILE" > "${BACKUP_FILE}.sha256"
else
    echo "    ⚠️  Database backup failed - service might not be ready"
    rm -f "$BACKUP_FILE"
fi

# ==============================================
# Backup Nextcloud data and config
# ==============================================
echo "  → Data and config backup..."
BACKUP_ARCHIVE="$BACKUP_DIR/data_${TIMESTAMP}.tar.gz"

# Method 1: Using volumes directly (modern approach)
if $CONTAINER_CMD volume inspect nextcloud_html &>/dev/null && \
   $CONTAINER_CMD volume inspect nextcloud_data &>/dev/null; then

    if $CONTAINER_CMD run --rm \
        --volume nextcloud_html:/backup/html:ro \
        --volume nextcloud_data:/backup/data:ro \
        --volume nextcloud_config:/backup/config:ro \
        --volume "$BACKUP_DIR:/output" \
        alpine tar czf "/output/${BACKUP_ARCHIVE##*/}" \
        -C /backup html data config 2>/dev/null; then
        
        DATA_SIZE=$(du -h "$BACKUP_ARCHIVE" | cut -f1)
        echo "    ✅ Data backed up (${DATA_SIZE})"
        sha256sum "$BACKUP_ARCHIVE" > "${BACKUP_ARCHIVE}.sha256"
    else
        echo "    ⚠️  Data backup failed using volume method"
    fi
else
    echo "    ⚠️  Named volumes not found - skipping data backup"
fi

# ==============================================
# Cleanup old backups
# ==============================================
echo "  → Cleaning old backups (>$RETENTION_DAYS days)..."

OLD_BACKUPS=$(find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -name "*.sql.gz" -o -name "*.tar.gz" 2>/dev/null | wc -l)

if find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete 2>/dev/null; then
    if [ "$OLD_BACKUPS" -gt 0 ]; then
        echo "    ✅ Removed $OLD_BACKUPS old backup(s)"
    fi
else
    echo "    ⚠️  Could not remove old backups"
fi

# ==============================================
# Summary and verification
# ==============================================
echo ""
echo "✅ Backup complete!"
echo ""
echo "📋 Backup directory contents:"
find "$BACKUP_DIR" -maxdepth 1 -type f -printf '%f (%s bytes)\n' | tail -n 6

echo ""
echo "🔐 Integrity check (if checksums exist):"
cd "$BACKUP_DIR"
shopt -s nullglob
for checksum_file in ./*.sha256; do
    checksum_file="${checksum_file#./}"
    if sha256sum -c "$checksum_file" &>/dev/null; then
        echo "  ✅ $checksum_file: OK"
    else
        echo "  ❌ $checksum_file: FAILED"
    fi
done
shopt -u nullglob

echo ""
echo "💾 Backup disk usage:"
du -sh "$BACKUP_DIR"

# Optional: Compress and encrypt backup for archival
echo ""
echo "📝 To create encrypted backup archive:"
echo "  tar czf - $BACKUP_DIR | openssl enc -aes-256-cbc -out backups_encrypted_${TIMESTAMP}.tar.gz.enc"
