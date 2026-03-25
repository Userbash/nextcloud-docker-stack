#!/bin/bash
# scripts/setup-systemd-services.sh
# Create systemd user services for auto-start
# Usage: bash scripts/setup-systemd-services.sh

set -euo pipefail

if [ "$EUID" -eq 0 ]; then
    echo "❌ Do NOT run this as root!"
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p ~/.config/systemd/user

echo "📡 Setting up systemd user services..."
echo ""

# ============================================================
# 1. Main service
# ============================================================
echo "1️⃣  Creating podman-nextcloud.service..."

cat > ~/.config/systemd/user/podman-nextcloud.service << EOF
[Unit]
Description=Nextcloud Stack with Podman Compose (Rootless)
Documentation=https://podman.io
After=network-online.target podman.socket
Wants=podman.socket network-online.target

[Service]
Type=exec
Environment="PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin"
Environment="XDG_RUNTIME_DIR=%t"
Delegate=yes

WorkingDirectory=$PROJECT_DIR

ExecStart=podman-compose -f docker-compose.rootless.yaml up --no-build
ExecStop=podman-compose -f docker-compose.rootless.yaml down

Restart=on-failure
RestartSec=10s

StandardOutput=journal
StandardError=journal
StandardOutputAdditionalFD=1

TimeoutStopSec=60s
TimeoutStartSec=90s

[Install]
WantedBy=default.target
EOF

echo "   ✅ Created podman-nextcloud.service"

# ============================================================
# 2. Backup service and timer
# ============================================================
echo "2️⃣  Creating backup service and timer..."

cat > ~/.config/systemd/user/podman-nextcloud-backup.service << EOF
[Unit]
Description=Nextcloud Podman Backup
After=podman-nextcloud.service
PartOf=podman-nextcloud.service

[Service]
Type=oneshot
Environment="PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin"
Environment="XDG_RUNTIME_DIR=%t"

WorkingDirectory=$PROJECT_DIR
ExecStart=bash ./scripts/backup.sh

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

cat > ~/.config/systemd/user/podman-nextcloud-backup.timer << EOF
[Unit]
Description=Daily Nextcloud Backup Timer
Requires=podman-nextcloud-backup.service

[Timer]
OnBootSec=10min
OnUnitActiveSec=1d
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo "   ✅ Created backup service and timer"

# ============================================================
# 3. Health check service and timer
# ============================================================
echo "3️⃣  Creating health check service and timer..."

cat > ~/.config/systemd/user/podman-nextcloud-health.service << EOF
[Unit]
Description=Nextcloud Health Check
After=podman-nextcloud.service
PartOf=podman-nextcloud.service

[Service]
Type=oneshot
Environment="PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin"
Environment="XDG_RUNTIME_DIR=%t"

WorkingDirectory=$PROJECT_DIR
ExecStart=bash ./scripts/health-check.sh

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

cat > ~/.config/systemd/user/podman-nextcloud-health.timer << EOF
[Unit]
Description=Hourly Nextcloud Health Check
Requires=podman-nextcloud-health.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo "   ✅ Created health check service and timer"

# ============================================================
# 4. Reload and enable services
# ============================================================
echo ""
echo "⚙️  Reloading systemd user daemon..."

systemctl --user daemon-reload

echo "✅ Daemon reloaded"
echo ""

echo "📋 Enabling services..."

systemctl --user enable podman-nextcloud.service
systemctl --user enable podman-nextcloud-backup.timer
systemctl --user enable podman-nextcloud-health.timer

echo "✅ Services enabled"
echo ""

# ============================================================
# 5. Display status and next steps
# ============================================================
echo "📊 Status:"
echo ""

systemctl --user list-unit-files | grep podman-nextcloud || true

echo ""
echo "🚀 To start services now:"
echo "  systemctl --user start podman-nextcloud.service"
echo ""
echo "📋 To check status:"
echo "  systemctl --user status podman-nextcloud.service"
echo "  systemctl --user status podman-nextcloud-backup.timer"
echo "  systemctl --user status podman-nextcloud-health.timer"
echo ""
echo "📊 To view logs:"
echo "  journalctl --user-unit=podman-nextcloud.service -f"
echo "  journalctl --user-unit=podman-nextcloud-backup.timer -n 20"
echo ""
echo "ℹ️  Services will auto-start on system reboot"
echo ""
