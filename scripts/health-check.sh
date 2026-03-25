#!/bin/bash
# Health check for all Nextcloud services
# Usage: ./scripts/health-check.sh

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(dirname "$script_dir")"

CHECKS_PASSED=0
CHECKS_FAILED=0

check_service() {
    local service=$1
    local cmd=$2
    echo -n "Checking $service... "
    
    if eval "$cmd" &>/dev/null; then
        echo "✅"
        ((CHECKS_PASSED++))
    else
        echo "❌"
        ((CHECKS_FAILED++))
    fi
}

echo "🏥 Nextcloud Health Check"
echo "========================="
echo ""

cd "$project_dir"

# Service checks
check_service "PostgreSQL" "docker-compose exec -T db pg_isready -U postgres 2>/dev/null"
check_service "Redis" "docker-compose exec -T redis redis-cli ping 2>/dev/null"
check_service "Nextcloud" "docker-compose ps app 2>/dev/null | grep -q Up"
check_service "Nginx" "docker-compose ps nginx 2>/dev/null | grep -q Up"

echo ""
echo "📊 Summary"
echo "=========="
echo "Passed: $CHECKS_PASSED"
echo "Failed: $CHECKS_FAILED"

if [ $CHECKS_FAILED -eq 0 ]; then
    echo "✅ All checks passed!"
    exit 0
else
    echo "❌ Some checks failed. Run: docker-compose logs [service]"
    exit 1
fi
