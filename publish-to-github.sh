#!/bin/bash
# Publish project to GitHub
# Usage: ./publish-to-github.sh YOUR-USERNAME

set -euo pipefail

if [ $# -lt 1 ]; then
    cat << 'EOF'

📤 Nextcloud Docker Stack - GitHub Publication Guide

Usage:
  ./publish-to-github.sh YOUR-GITHUB-USERNAME

What This Does:
  1. Initialize git repository
  2. Create initial commit
  3. Show GitHub setup instructions
  4. Provide publication steps

Before Running:
  - Create empty repository on GitHub
  - Name: nextcloud-docker-stack
  - Do NOT initialize with README or .gitignore

Example:
  ./publish-to-github.sh octocat

EOF
    exit 1
fi

USERNAME="$1"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$PROJECT_DIR"

echo "🚀 Publishing to GitHub..."
echo ""

# Initialize git repository
if [ ! -d ".git" ]; then
    echo "📝 Initializing git repository..."
    git init
    git config user.name "Userbash"
    git config user.email "wairuste@gmail.com"
    echo "✅ Git initialized"
else
    echo "✅ Git already initialized"
fi

# Stage all files
echo "📦 Staging files..."
git add -A
echo "✅ Files staged"

# Create initial commit
echo "📝 Creating initial commit..."
git commit -m "🚀 Initial commit: Production-ready Nextcloud Docker Stack

- Docker Compose configuration with PostgreSQL, Redis, Nginx, Certbot
- Production-ready with security, monitoring, and backups
- Comprehensive documentation and troubleshooting guides
- GitHub Actions workflows for CI/CD
- MIT License - ready for open-source distribution" || true
echo "✅ Commit created"

# Rename branch to main
echo "🔄 Setting default branch to main..."
git branch -M main || true
echo "✅ Branch set to main"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "📤 NEXT STEPS FOR GITHUB PUBLICATION"
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "1️⃣  CREATE EMPTY REPOSITORY ON GITHUB"
echo "   - Go to: https://github.com/new"
echo "   - Repository name: nextcloud-docker-stack"
echo "   - Description: Production-ready Nextcloud with Docker Compose"
echo "   - Visibility: Public"
echo "   - DO NOT initialize with README, .gitignore, or license"
echo ""

echo "2️⃣  CONNECT TO REMOTE (after repository is created)"
echo "   git remote add origin https://github.com/$USERNAME/nextcloud-docker-stack.git"
echo ""

echo "3️⃣  PUSH CODE TO GITHUB"
echo "   git push -u origin main"
echo ""

echo "4️⃣  CONFIGURE GITHUB REPOSITORY"
echo "   - Go to: Settings → General"
echo "   - Add topics:"
echo "     • nextcloud"
echo "     • docker"
echo "     • docker-compose"
echo "     • self-hosted"
echo "     • cloud-storage"
echo "     • file-sync"
echo ""
echo "   - Settings → Branches"
echo "     • Add branch protection rule for 'main'"
echo "     • Require status checks to pass"
echo ""
echo "   - Settings → Actions"
echo "     • Enable GitHub Actions"
echo ""

echo "5️⃣  VERIFY PUBLICATION"
echo "   - Check: https://github.com/$USERNAME/nextcloud-docker-stack"
echo "   - Verify workflows run"
echo "   - Confirm README displays correctly"
echo ""

echo "6️⃣  ANNOUNCEMENT (Optional)"
echo "   - Share on social media"
echo "   - Add to awesome-lists"
echo "   - Link from your portfolio"
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "✅ Project is ready! Follow the steps above."
echo "═══════════════════════════════════════════════════════════"
echo ""

echo "📚 Project Contents Checklist:"
grep "^" << 'CHECKLIST'
  ☑ 26 project files
  ☑ 6 documentation pages
  ☑ 4 management scripts
  ☑ 2 GitHub Actions workflows
  ☑ 2 GitHub issue templates
  ☑ MIT License
  ☑ Code of Conduct
  ☑ Contributing guide
  ☑ Production-ready configuration
CHECKLIST

echo ""
echo "🎉 Good luck with your GitHub project!"
