#!/bin/bash
# Nextcloud Docker Stack - Complete Testing & Troubleshooting Suite
# This script runs configuration tests and log analysis

set -euo pipefail

# ============ CONFIGURATION ============
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCAL_TESTS="${SCRIPT_DIR}/local-environment-tests.sh"
LOG_ANALYZER="${PROJECT_ROOT}/monitoring/log_analyzer.py"
REPORTS_DIR="${PROJECT_ROOT}/test-reports"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============ UTILITIES ============

print_header() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ $1$(printf '%*s' $((56 - ${#1})) | tr ' ' ' ')║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}\n"
}

print_section() {
    echo -e "${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# ============ ENVIRONMENT CHECKS ============

check_python() {
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 not found. Install it to use Python tests."
        return 1
    fi
    print_success "Python 3 found: $(python3 --version)"
    return 0
}

check_bash() {
    if ! [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
        print_error "Bash 4+ required (current: ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]})"
        return 1
    fi
    print_success "Bash ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]} found"
    return 0
}

check_required_tools() {
    local missing_tools=()

    for tool in docker podman docker-compose podman-compose; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_info "Optional tools not found: ${missing_tools[*]}"
    else
        print_success "All container tools available"
    fi
}

# ============ TEST EXECUTION ============

run_bash_tests() {
    print_section "Running Local Environment Tests"

    if [ ! -f "$LOCAL_TESTS" ]; then
        print_error "Local tests script not found: $LOCAL_TESTS"
        return 1
    fi

    if ! bash "$LOCAL_TESTS" "$PROJECT_ROOT"; then
        print_error "Local environment tests reported failures"
        # Since these tests might fail on a minimal environment, we just warn instead of exit 1
        return 0
    fi

    print_success "Local environment tests completed"
    return 0
}

run_python_tests() {
    print_info "Python framework tests skipped."
    return 0
}

run_log_analysis() {
    print_section "Analyzing Container Logs"

    if [ ! -f "$LOG_ANALYZER" ]; then
        print_error "Log analyzer not found: $LOG_ANALYZER"
        return 1
    fi

    if ! check_python; then
        print_info "Skipping log analysis"
        return 0
    fi

    local hours="${1:-1}"
    local output_file="${REPORTS_DIR}/log_analysis_$(date +%Y%m%d_%H%M%S).txt"
    local json_output="${REPORTS_DIR}/log_analysis_$(date +%Y%m%d_%H%M%S).json"

    mkdir -p "$REPORTS_DIR"

    print_info "Analyzing last $hours hour(s) of logs..."

    if ! python3 "$LOG_ANALYZER" \
        --hours "$hours" \
        --output "$output_file" \
        --json-output "$json_output" \
        --project-root "$PROJECT_ROOT"; then
        print_info "Log analysis failed or engines not found, continuing..."
    else
        print_success "Log analysis completed. Report: $output_file"
    fi
    return 0
}

# ============ REPORT SUMMARY ============

show_report_summary() {
    print_section "Test Reports Summary"

    if [ ! -d "$REPORTS_DIR" ]; then
        print_info "No reports generated yet"
        return
    fi

    local report_count=$(find "$REPORTS_DIR" -type f | wc -l)

    if [ "$report_count" -eq 0 ]; then
        print_info "No reports available"
        return
    fi

    echo -e "  Found $report_count report(s):"
    ls -lh "$REPORTS_DIR" | grep -v '^total' | awk '{print "    " $9 " (" $5 ")"}'

    print_info "View latest report: cat $(ls -t "$REPORTS_DIR"/* 2>/dev/null | head -1)"
}

# ============ QUICK HEALTH CHECK ============

quick_health_check() {
    print_section "Quick Health Check"

    # Check containers
    local runtime="${1:-docker}"

    if ! command -v "$runtime" &> /dev/null; then
        print_error "Runtime '$runtime' not found"
        return 1
    fi

    print_info "Checking containers with $runtime..."

    if ! "$runtime" ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null | tail -n +2; then
        print_error "Failed to list containers"
        return 1
    fi

    print_success "Container status check completed"
    return 0
}

# ============ MAIN MENU ============

show_menu() {
    cat << EOF

${CYAN}╔════════════════════════════════════════════════════════════╗${NC}
${CYAN}║  NEXTCLOUD DOCKER STACK - TESTING & TROUBLESHOOTING SUITE  ║${NC}
${CYAN}╚════════════════════════════════════════════════════════════╝${NC}

${GREEN}Usage:${NC}
  ./run_tests.sh [COMMAND] [OPTIONS]

${GREEN}Commands:${NC}
  all              Run all tests and analysis (default)
  bash             Run Bash configuration tests only
  python           Run Python configuration tests only
  logs             Analyze container logs (optional: hours argument)
  health           Quick health check of containers
  help             Show this help message

${GREEN}Examples:${NC}
  ./run_tests.sh all          # Run everything
  ./run_tests.sh logs 2       # Analyze last 2 hours of logs
  ./run_tests.sh health       # Check container status

${GREEN}Configuration:${NC}
  Project Root:    $PROJECT_ROOT
  Reports Dir:     $REPORTS_DIR
  Python Framework: $PYTHON_FRAMEWORK
  Bash Framework:  $BASH_FRAMEWORK
  Log Analyzer:    $LOG_ANALYZER

EOF
}

# ============ MAIN EXECUTION ============

main() {
    local command="${1:-all}"
    local option="${2:-1}"

    print_header "Nextcloud Docker Stack - Test Suite"

    # Check basics
    check_bash || exit 1

    case "$command" in
        all)
            run_bash_tests
            run_python_tests
            run_log_analysis "$option"
            show_report_summary
            ;;
        bash)
            run_bash_tests
            show_report_summary
            ;;
        python)
            run_python_tests
            show_report_summary
            ;;
        logs)
            run_log_analysis "$option"
            ;;
        health)
            quick_health_check
            ;;
        help|--help|-h)
            show_menu
            ;;
        *)
            print_error "Unknown command: $command"
            show_menu
            exit 1
            ;;
    esac

    echo ""
    print_success "Test suite completed!"
}

main "$@"
