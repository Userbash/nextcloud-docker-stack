#!/usr/bin/env python3

"""
Export Configuration from Local Development to Docker
Purpose: Convert local development config to production-ready Docker config
Author: Nextcloud Docker Stack Team
Date: 2026-03-15
"""

import os
import sys
import json
import shutil
from pathlib import Path
from datetime import datetime

# ANSI Colors
class Color:
    BLUE = '\033[0;34m'
    GREEN = '\033[0;32m'
    RED = '\033[0;31m'
    YELLOW = '\033[1;33m'
    NC = '\033[0m'

def print_header(text):
    print(f"\n{Color.BLUE}╔════════════════════════════════════════════════════════════════╗{Color.NC}")
    print(f"{Color.BLUE}║ {text:<62} ║{Color.NC}")
    print(f"{Color.BLUE}╚════════════════════════════════════════════════════════════════╝{Color.NC}\n")

def print_success(text):
    print(f"  {Color.GREEN}✓{Color.NC} {text}")

def print_error(text):
    print(f"  {Color.RED}✗{Color.NC} {text}")

def print_info(text):
    print(f"  {Color.YELLOW}•{Color.NC} {text}")

def get_project_root():
    """Get project root directory"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(os.path.dirname(script_dir))

def read_local_env():
    """Read local .env file"""
    project_root = get_project_root()
    env_file = os.path.join(project_root, '.env.local')
    
    env_vars = {}
    if os.path.exists(env_file):
        with open(env_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    if '=' in line:
                        key, value = line.split('=', 1)
                        env_vars[key.strip()] = value.strip()
    
    return env_vars

def get_local_config():
    """Get all local configuration files"""
    project_root = get_project_root()
    
    config = {
        'env': read_local_env(),
        'nginx_config': None,
        'php_config': None,
        'redis_config': None,
        'db_schema': None,
    }
    
    # Read config files
    nginx_file = os.path.join(project_root, 'config/local/nginx.conf')
    if os.path.exists(nginx_file):
        with open(nginx_file, 'r') as f:
            config['nginx_config'] = f.read()
    
    php_file = os.path.join(project_root, 'config/local/php-fpm.conf')
    if os.path.exists(php_file):
        with open(php_file, 'r') as f:
            config['php_config'] = f.read()
    
    redis_file = os.path.join(project_root, 'config/local/redis.conf')
    if os.path.exists(redis_file):
        with open(redis_file, 'r') as f:
            config['redis_config'] = f.read()
    
    return config

def create_docker_env(local_config):
    """Create Docker-ready .env from local config"""
    docker_env = {}
    
    # Required variables for Docker
    required_vars = [
        'NEXTCLOUD_DOMAIN',
        'NEXTCLOUD_ADMIN_USER',
        'NEXTCLOUD_ADMIN_PASSWORD',
        'DB_TYPE',
        'DB_HOST',
        'DB_NAME',
        'DB_USER',
        'DB_PASSWORD',
        'REDIS_HOST',
        'REDIS_PORT',
        'REDIS_PASSWORD',
    ]
    
    for var in required_vars:
        if var in local_config['env']:
            docker_env[var] = local_config['env'][var]
        else:
            docker_env[var] = f"CHANGE_ME_{var}"
    
    # Add Docker-specific variables
    docker_env['COMPOSE_PROJECT_NAME'] = 'nextcloud'
    docker_env['SERVICE_RESTART_POLICY'] = 'unless-stopped'
    docker_env['POSTGRES_VERSION'] = '16'
    docker_env['REDIS_VERSION'] = 'latest'
    docker_env['NGINX_VERSION'] = '1.25'
    
    return docker_env

def export_configs(output_dir=None):
    """Export all configurations"""
    if output_dir is None:
        output_dir = get_project_root()
    
    print_header("Exporting Local Configuration")
    
    os.makedirs(output_dir, exist_ok=True)
    
    # Get local configuration
    print_info("Reading local configuration...")
    local_config = get_local_config()
    print_success("Local configuration loaded")
    
    # Create export files
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    
    # 1. Export environment variables
    print_info("Exporting environment variables...")
    env_file = os.path.join(output_dir, f'config-export-{timestamp}.env')
    with open(env_file, 'w') as f:
        f.write("# Nextcloud Docker Stack Configuration Export\n")
        f.write(f"# Exported: {datetime.now().isoformat()}\n")
        f.write("# For production use, update all CHANGE_ME_* values\n\n")
        
        for key, value in sorted(local_config['env'].items()):
            f.write(f"{key}={value}\n")
    
    print_success(f"Environment exported: {os.path.basename(env_file)}")
    
    # 2. Create Docker-ready .env template
    print_info("Creating Docker .env template...")
    docker_env = create_docker_env(local_config)
    docker_env_file = os.path.join(output_dir, f'docker-env-{timestamp}.env')
    with open(docker_env_file, 'w') as f:
        f.write("# Nextcloud Docker Stack - Environment Configuration\n")
        f.write("# Generated from local development environment\n")
        f.write(f"# Date: {datetime.now().isoformat()}\n")
        f.write("# WARNING: Change all passwords before production deployment!\n\n")
        
        for key, value in sorted(docker_env.items()):
            f.write(f"{key}={value}\n")
    
    print_success(f"Docker .env template: {os.path.basename(docker_env_file)}")
    
    # 3. Export configuration files
    print_info("Exporting config files...")
    
    config_export_dir = os.path.join(output_dir, f'config-export-{timestamp}')
    os.makedirs(config_export_dir, exist_ok=True)
    
    if local_config['nginx_config']:
        nginx_export = os.path.join(config_export_dir, 'nginx.conf')
        with open(nginx_export, 'w') as f:
            f.write(local_config['nginx_config'])
        print_success(f"Nginx config exported")
    
    if local_config['php_config']:
        php_export = os.path.join(config_export_dir, 'php-fpm.conf')
        with open(php_export, 'w') as f:
            f.write(local_config['php_config'])
        print_success(f"PHP-FPM config exported")
    
    if local_config['redis_config']:
        redis_export = os.path.join(config_export_dir, 'redis.conf')
        with open(redis_export, 'w') as f:
            f.write(local_config['redis_config'])
        print_success(f"Redis config exported")
    
    # 4. Create checklist for deployment
    print_info("Creating deployment checklist...")
    checklist_file = os.path.join(output_dir, 'DEPLOYMENT_CHECKLIST.md')
    with open(checklist_file, 'w') as f:
        f.write("# Deployment Checklist\n\n")
        f.write("## Pre-Deployment Configuration\n\n")
        f.write("- [ ] Update all CHANGE_ME_* values in .env\n")
        f.write("- [ ] Review docker-compose.yaml for any customizations\n")
        f.write("- [ ] Ensure all SSL certificates are in place\n")
        f.write("- [ ] Backup local database if needed\n\n")
        f.write("## Environment Variables to Update\n\n")
        for var in ['NEXTCLOUD_DOMAIN', 'NEXTCLOUD_ADMIN_PASSWORD', 'DB_PASSWORD', 'REDIS_PASSWORD'][:4]:
            f.write(f"- [ ] `{var}`\n")
        f.write("\n## Deployment Commands\n\n")
        f.write("```bash\n")
        f.write("# 1. Stop local services\n")
        f.write("bash scripts/local-services-mock.sh stop\n\n")
        f.write("# 2. Copy configuration\n")
        f.write("cp docker-env-*.env .env\n\n")
        f.write("# 3. Verify configuration\n")
        f.write("docker-compose config\n\n")
        f.write("# 4. Pull latest images\n")
        f.write("docker-compose pull\n\n")
        f.write("# 5. Start services\n")
        f.write("docker-compose up -d\n\n")
        f.write("# 6. Initialize database\n")
        f.write("docker-compose exec nextcloud occ db:convert-type pgsql\n\n")
        f.write("# 7. Verify deployment\n")
        f.write("docker-compose ps\n")
        f.write("```\n")
    
    print_success(f"Deployment checklist created")
    
    # 5. Create summary report
    print("\n" + "="*70)
    print(f"{Color.BLUE}Export Summary{Color.NC}")
    print("="*70)
    print(f"\n  Files created in: {output_dir}\n")
    print(f"  {Color.GREEN}✓{Color.NC} config-export-{timestamp}.env")
    print(f"  {Color.GREEN}✓{Color.NC} docker-env-{timestamp}.env")
    print(f"  {Color.GREEN}✓{Color.NC} config-export-{timestamp}/ (directory)")
    print(f"  {Color.GREEN}✓{Color.NC} DEPLOYMENT_CHECKLIST.md")
    
    print(f"\n{Color.YELLOW}Next Steps:{Color.NC}")
    print(f"  1. Update passwords in: docker-env-{timestamp}.env")
    print(f"  2. Review: DEPLOYMENT_CHECKLIST.md")
    print(f"  3. Copy to .env: cp docker-env-{timestamp}.env .env")
    print(f"  4. Deploy: docker-compose up -d")
    
    return True

def main():
    try:
        export_configs()
        print(f"\n{Color.GREEN}Export complete!{Color.NC}\n")
        return 0
    except Exception as e:
        print_error(f"Error during export: {str(e)}")
        return 1

if __name__ == '__main__':
    sys.exit(main())
