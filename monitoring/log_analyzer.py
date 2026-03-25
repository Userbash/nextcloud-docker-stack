#!/usr/bin/env python3
"""
Log Analyzer for Nextcloud Docker Stack
Collects and analyzes Docker/Podman container logs for troubleshooting
"""

import json
import subprocess
import sys
import re
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from enum import Enum
import logging

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SeverityLevel(Enum):
    """Error severity classification"""
    CRITICAL = "CRITICAL"
    ERROR = "ERROR"
    WARNING = "WARNING"
    INFO = "INFO"
    DEBUG = "DEBUG"


@dataclass
class LogEntry:
    """Single log entry with parsed information"""
    timestamp: str
    container: str
    level: str
    message: str
    raw_line: str
    severity: SeverityLevel = SeverityLevel.INFO


@dataclass
class DiagnosticIssue:
    """Identified issue with severity and suggestion"""
    id: str
    container: str
    severity: SeverityLevel
    title: str
    description: str
    found_count: int
    first_occurrence: str
    suggestions: List[str]
    related_docs: List[str]


class LogAnalyzer:
    """Main log analyzer class"""

    # Error patterns and their severity/fixes
    ERROR_PATTERNS = {
        # Database errors
        r'connection refused.*5432': {
            'severity': SeverityLevel.CRITICAL,
            'title': 'PostgreSQL Connection Failed',
            'suggestions': [
                'Check if PostgreSQL container is running: docker ps | grep postgres',
                'Verify DATABASE_HOST in .env matches service name',
                'Check PostgreSQL logs: docker logs <postgres-container>',
                'Ensure proper network configuration in docker-compose.yaml',
            ],
            'docs': ['TROUBLESHOOTING.md', 'docs/SECURITY.md']
        },
        r'SQLSTATE\[HY000\].*server has gone away': {
            'severity': SeverityLevel.ERROR,
            'title': 'Database Connection Lost',
            'suggestions': [
                'Check database container health: docker inspect <postgres-container>',
                'Review PostgreSQL memory limits and available resources',
                'Check for database restarts in logs',
                'Increase max_connections if high concurrency',
            ],
            'docs': ['docs/TROUBLESHOOTING.md']
        },

        # Redis errors
        r'redis.*connection.*refused': {
            'severity': SeverityLevel.ERROR,
            'title': 'Redis Connection Failed',
            'suggestions': [
                'Verify Redis container is running: docker ps | grep redis',
                'Check REDIS_HOST in .env configuration',
                'Check Redis port exposure and networking',
                'Review Redis memory settings',
            ],
            'docs': ['TROUBLESHOOTING.md']
        },

        # SSL/TLS errors
        r'certificate verify failed': {
            'severity': SeverityLevel.ERROR,
            'title': 'SSL Certificate Verification Failed',
            'suggestions': [
                'Verify SSL certificate files exist in config/ssl/',
                'Check certificate permissions: ls -la config/ssl/',
                'Ensure certificate is not expired: openssl x509 -text -in config/ssl/cert.pem',
                'Check nginx SSL configuration in nginx/nginx.conf',
            ],
            'docs': ['SECURITY_FIXES.md', 'docs/SECURITY.md']
        },
        r'certbot.*renewal.*failed|renewal.*skipped': {
            'severity': SeverityLevel.WARNING,
            'title': 'Certbot SSL Renewal Failed',
            'suggestions': [
                'Check Certbot container logs: docker logs <certbot-container>',
                'Verify domain DNS is properly configured',
                'Check Let\'s Encrypt rate limits (50 per domain/week)',
                'Ensure webroot path is correct for WebRoot validation',
                'Run manual renewal: docker exec <certbot> certbot renew --dry-run',
            ],
            'docs': ['SECURITY_FIXES.md']
        },

        # Nginx errors
        r'nginx.*upstream.*connect\(\) failed': {
            'severity': SeverityLevel.ERROR,
            'title': 'Nginx Backend Connection Failed',
            'suggestions': [
                'Verify PHP-FPM container is running: docker ps | grep php',
                'Check nginx upstream configuration',
                'Review PHP-FPM socket or TCP port settings',
                'Check Docker network connectivity',
            ],
            'docs': ['TROUBLESHOOTING.md']
        },
        r'nginx.*permission denied': {
            'severity': SeverityLevel.ERROR,
            'title': 'Nginx Permission Denied',
            'suggestions': [
                'Check file permissions in volumes: ls -la /srv/nextcloud',
                'Verify nginx user has correct permissions (www-data/nginx)',
                'Check docker-compose volume permissions and ownership',
            ],
            'docs': ['PROJECT_CLEANUP_REPORT.md']
        },

        # PHP errors
        r'PHP.*Fatal error|PHP.*Parse error': {
            'severity': SeverityLevel.ERROR,
            'title': 'PHP Fatal Error',
            'suggestions': [
                'Check PHP error logs: docker logs <php-container>',
                'Verify PHP configuration in php/php.ini',
                'Check for syntax errors in custom code/apps',
                'Review PHP-FPM status',
            ],
            'docs': ['TROUBLESHOOTING.md']
        },
        r'PHP.*allowed memory.*exhausted': {
            'severity': SeverityLevel.ERROR,
            'title': 'PHP Memory Limit Exceeded',
            'suggestions': [
                'Increase memory_limit in php/php.ini (current: 512M)',
                'Check for memory leaks in custom apps',
                'Monitor PHP-FPM process count',
                'Consider increasing container memory allocation',
            ],
            'docs': ['docs/TROUBLESHOOTING.md']
        },

        # Nextcloud warnings
        r'Recommended|in maintenance mode': {
            'severity': SeverityLevel.WARNING,
            'title': 'Nextcloud Maintenance Issue',
            'suggestions': [
                'Exit maintenance mode: docker exec <nextcloud> occ maintenance:mode --off',
                'Review Nextcloud recommendations: docker exec <nextcloud> occ check',
                'Check available disk space: df -h /srv/nextcloud',
            ],
            'docs': ['TROUBLESHOOTING.md']
        },

        # Permission issues
        r'permission denied.*/.+/config': {
            'severity': SeverityLevel.CRITICAL,
            'title': 'Config Directory Permission Issue',
            'suggestions': [
                'Fix permissions: sudo chown -R nobody:nogroup /srv/nextcloud/config',
                'Check volume mount options in docker-compose.yaml',
                'Verify SELinux/AppArmor restrictions if enabled',
            ],
            'docs': ['PROJECT_CLEANUP_REPORT.md']
        },

        # Out of disk space
        r'no space left on device|Disk quota exceeded': {
            'severity': SeverityLevel.CRITICAL,
            'title': 'Out of Disk Space',
            'suggestions': [
                'Check disk usage: df -h',
                'Find large files: du -sh /srv/nextcloud/*',
                'Remove old backups or logs',
                'Review PostgreSQL data size: du -sh /var/lib/postgresql',
            ],
            'docs': ['TROUBLESHOOTING.md']
        },

        # General connectivity
        r'Connection refused|Could not connect': {
            'severity': SeverityLevel.ERROR,
            'title': 'Service Connection Failed',
            'suggestions': [
                'Verify all containers are running: docker-compose ps',
                'Check service network configuration',
                'Review firewall rules if running on remote host',
                'Test connectivity: docker exec <container> curl http://<service>:<port>',
            ],
            'docs': ['TROUBLESHOOTING.md', 'docs/SECURITY.md']
        },
    }

    def __init__(self, project_root: str = "."):
        """Initialize analyzer"""
        self.project_root = Path(project_root)
        self.containers: Dict[str, str] = {}
        self._detect_runtime()

    def _detect_runtime(self) -> None:
        """Detect Docker or Podman runtime"""
        try:
            subprocess.run(['docker', 'ps'], capture_output=True, check=True)
            self.runtime = 'docker'
            logger.info("Using Docker runtime")
        except (subprocess.CalledProcessError, FileNotFoundError):
            try:
                subprocess.run(['podman', 'ps'], capture_output=True, check=True)
                self.runtime = 'podman'
                logger.info("Using Podman runtime")
            except (subprocess.CalledProcessError, FileNotFoundError):
                logger.error("Neither Docker nor Podman found")
                sys.exit(1)

    def collect_logs(self, hours: int = 1) -> List[LogEntry]:
        """Collect logs from all containers"""
        entries = []

        try:
            # Get list of running containers
            cmd = [self.runtime, 'ps', '--format', 'json']
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            containers = json.loads(result.stdout)

            for container in containers:
                container_name = container.get('Names', 'unknown')
                logger.info(f"Collecting logs from {container_name}")

                # Get logs
                cmd = [
                    self.runtime, 'logs',
                    '--timestamps',
                    '--since', f'{hours}h',
                    container['ID'][:12]
                ]

                result = subprocess.run(cmd, capture_output=True, text=True)

                for line in result.stdout.split('\n'):
                    if not line.strip():
                        continue

                    entry = self._parse_log_line(line, container_name)
                    if entry:
                        entries.append(entry)

        except Exception as e:
            logger.error(f"Error collecting logs: {e}")

        return entries

    def _parse_log_line(self, line: str, container: str) -> Optional[LogEntry]:
        """Parse single log line"""
        try:
            # Extract timestamp and message
            parts = line.split(' ', 1)
            if len(parts) >= 2:
                return LogEntry(
                    timestamp=parts[0],
                    container=container,
                    level=self._detect_level(line),
                    message=parts[1] if len(parts) > 1 else '',
                    raw_line=line,
                    severity=self._detect_severity(line)
                )
        except Exception as e:
            logger.debug(f"Error parsing line: {e}")

        return None

    def _detect_level(self, line: str) -> str:
        """Detect log level from line"""
        line_lower = line.lower()
        if 'error' in line_lower or 'exception' in line_lower:
            return 'ERROR'
        elif 'warning' in line_lower or 'warn' in line_lower:
            return 'WARNING'
        elif 'debug' in line_lower:
            return 'DEBUG'
        elif 'info' in line_lower:
            return 'INFO'
        return 'INFO'

    def _detect_severity(self, line: str) -> SeverityLevel:
        """Detect message severity"""
        line_lower = line.lower()

        if any(word in line_lower for word in ['fatal', 'critical', 'emergency']):
            return SeverityLevel.CRITICAL
        elif 'error' in line_lower or 'exception' in line_lower:
            return SeverityLevel.ERROR
        elif 'warning' in line_lower or 'warn' in line_lower:
            return SeverityLevel.WARNING

        return SeverityLevel.INFO

    def analyze_logs(self, entries: List[LogEntry]) -> List[DiagnosticIssue]:
        """Analyze logs for known issues"""
        issues: Dict[str, DiagnosticIssue] = {}

        for entry in entries:
            for pattern, details in self.ERROR_PATTERNS.items():
                if re.search(pattern, entry.message, re.IGNORECASE):
                    pattern_id = pattern.replace('[', '').replace(']', '')[:20]
                    issue_id = f"{entry.container}_{pattern_id}"

                    if issue_id not in issues:
                        issues[issue_id] = DiagnosticIssue(
                            id=issue_id,
                            container=entry.container,
                            severity=details['severity'],
                            title=details['title'],
                            description=entry.message[:200],
                            found_count=1,
                            first_occurrence=entry.timestamp,
                            suggestions=details['suggestions'],
                            related_docs=details['docs']
                        )
                    else:
                        issues[issue_id].found_count += 1

        return sorted(
            issues.values(),
            key=lambda x: (x.severity.value, -x.found_count),
            reverse=True
        )

    def generate_report(self, issues: List[DiagnosticIssue], output_file: Optional[str] = None) -> str:
        """Generate diagnostic report"""
        report = []
        report.append("=" * 70)
        report.append("NEXTCLOUD DOCKER STACK - LOG ANALYSIS REPORT")
        report.append("=" * 70)
        report.append(f"Generated: {datetime.now().isoformat()}")
        report.append(f"Total Issues Found: {len(issues)}")
        report.append("")

        # Group by severity
        for severity in [SeverityLevel.CRITICAL, SeverityLevel.ERROR, SeverityLevel.WARNING]:
            severity_issues = [i for i in issues if i.severity == severity]

            if not severity_issues:
                continue

            report.append(f"\n{'=' * 70}")
            report.append(f"{severity.value} ISSUES ({len(severity_issues)})")
            report.append(f"{'=' * 70}")

            for issue in severity_issues:
                report.append(f"\n🔴 {issue.title} [{issue.container}]")
                report.append(f"   Occurrences: {issue.found_count}")
                report.append(f"   First Seen: {issue.first_occurrence}")
                report.append(f"   Description: {issue.description}")

                report.append(f"\n   📋 Suggestions:")
                for i, suggestion in enumerate(issue.suggestions, 1):
                    report.append(f"      {i}. {suggestion}")

                if issue.related_docs:
                    report.append(f"\n   📖 Related Documentation:")
                    for doc in issue.related_docs:
                        report.append(f"      - {doc}")

        report_text = "\n".join(report)

        if output_file:
            Path(output_file).parent.mkdir(parents=True, exist_ok=True)
            Path(output_file).write_text(report_text)
            logger.info(f"Report saved to: {output_file}")

        return report_text

    def generate_json_report(self, issues: List[DiagnosticIssue], output_file: Optional[str] = None) -> str:
        """Generate JSON diagnostic report"""
        report = {
            'timestamp': datetime.now().isoformat(),
            'total_issues': len(issues),
            'issues': [
                {
                    'id': issue.id,
                    'container': issue.container,
                    'severity': issue.severity.value,
                    'title': issue.title,
                    'description': issue.description,
                    'occurrences': issue.found_count,
                    'first_seen': issue.first_occurrence,
                    'suggestions': issue.suggestions,
                    'docs': issue.related_docs
                }
                for issue in issues
            ]
        }

        report_json = json.dumps(report, indent=2)

        if output_file:
            Path(output_file).parent.mkdir(parents=True, exist_ok=True)
            Path(output_file).write_text(report_json)
            logger.info(f"JSON report saved to: {output_file}")

        return report_json


def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description='Nextcloud Docker Stack Log Analyzer')
    parser.add_argument('--hours', type=int, default=1, help='Hours of logs to analyze (default: 1)')
    parser.add_argument('--output', help='Output report file')
    parser.add_argument('--json-output', help='JSON output file')
    parser.add_argument('--project-root', default='.', help='Project root directory')

    args = parser.parse_args()

    # Analyze
    analyzer = LogAnalyzer(args.project_root)

    print("Collecting logs...")
    logs = analyzer.collect_logs(args.hours)
    print(f"Collected {len(logs)} log entries")

    print("Analyzing logs...")
    issues = analyzer.analyze_logs(logs)

    # Reports
    report = analyzer.generate_report(issues, args.output)
    print("\n" + report)

    if args.json_output:
        analyzer.generate_json_report(issues, args.json_output)


if __name__ == '__main__':
    main()
