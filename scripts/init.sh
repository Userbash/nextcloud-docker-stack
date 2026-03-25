#!/bin/bash
# Initialize Nextcloud Docker Stack project
# Usage: ./scripts/init.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname "$script_dir")"

echo "🚀 Initializing Nextcloud Docker Stack..."
echo ""

# Check if .env exists
if [ ! -f "$project_dir/.env" ]; then
    echo "⚠️  .env file not found. Creating from .env.example..."
    
    if [ ! -f "$project_dir/.env.example" ]; then
        echo "❌ Error: .env.example not found!"
        exit 1
    fi
    
    cp "$project_dir/.env.example" "$project_dir/.env"
    chmod 600 "$project_dir/.env"
    echo "✅ Created .env file (read-only: 600)"
else
    echo "✅ .env file already exists"
fi

# Create required directories
echo "📦 Creating required directories..."
mkdir -p "$project_dir/config/ssl"
mkdir -p "$project_dir/config/webroot"
mkdir -p "$project_dir/backups"

echo "✅ Directories created"

# Make all scripts executable
echo "🔧 Making scripts executable..."
find "$project_dir/scripts" -maxdepth 1 -name "*.sh" -type f -exec chmod +x {} \;
echo "✅ Scripts are now executable"

echo ""
echo "📋 Next steps:"
echo "1. Edit your configuration: vi $project_dir/.env"
echo "2. Update these required values:"
echo "   - POSTGRES_PASSWORD"
echo "   - NEXTCLOUD_ADMIN_PASSWORD"
echo "   - NEXTCLOUD_DOMAIN"
echo "   - LETSENCRYPT_EMAIL"
echo ""
echo "3. Start services: docker-compose up -d"
echo "4. Check status: $script_dir/health-check.sh"
echo "5. View logs: docker-compose logs -f"
echo ""
echo "✅ Initialization complete!"
