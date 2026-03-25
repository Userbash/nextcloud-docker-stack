#!/bin/bash
# Update and maintenance script
# Usage: ./scripts/update.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname "$script_dir")"

echo "🔄 Nextcloud Update & Maintenance"
echo "=================================="
echo ""

cd "$project_dir"

# Pull latest images
echo "📥 Pulling latest images..."
if docker-compose pull; then
    echo "✅ Images updated"
else
    echo "❌ Failed to pull images"
    exit 1
fi

# Backup before update
echo "💾 Creating backup..."
if bash "$script_dir/backup.sh"; then
    echo "✅ Backup created"
else
    echo "⚠️  Backup creation had issues"
fi

# Update containers
echo "🔄 Updating containers..."
if docker-compose up -d; then
    echo "✅ Containers updated"
else
    echo "❌ Failed to update containers"
    exit 1
fi

# Wait for services
echo "⏳ Waiting for services (30s)..."
sleep 5

# Run health check
echo ""
echo "🏥 Running health check..."
if bash "$script_dir/health-check.sh"; then
    echo "✅ All services healthy"
else
    echo "⚠️  Some services not yet ready"
fi

echo ""
echo "✅ Update complete!"
echo ""
echo "📋 Next steps:"
echo "1. Check Nextcloud admin panel: https://${NEXTCLOUD_DOMAIN}"
echo "2. Review: docker-compose logs -f app"
echo "3. Verify: docker-compose exec app php occ status"
