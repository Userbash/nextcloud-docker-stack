#!/usr/bin/env bash
# Validate all YAML files in the repository before publishing changes.

set -euo pipefail

PROJECT_ROOT=""
YAML_FILES=()

# Prints an error and exits.
die() {
    echo "[yaml] ERROR: $*"
    exit 1
}

# Resolves and enters project root.
set_project_root() {
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    cd "$PROJECT_ROOT"
}

# Ensures yamllint is available before running checks.
require_yamllint() {
    if ! command -v yamllint >/dev/null 2>&1; then
        die "yamllint is not installed. Install it first (example: sudo apt-get install -y yamllint)"
    fi
}

# Collects YAML files while skipping generated and git internals.
collect_yaml_files() {
    mapfile -d '' YAML_FILES < <(
        find . \
            -type d \( -name '.git' -o -name 'data' -o -name 'test-reports' \) -prune -o \
            -type f \( -name '*.yml' -o -name '*.yaml' \) -print0
    )
}

# Runs strict linting over all collected YAML files.
run_yaml_lint() {
    if [ "${#YAML_FILES[@]}" -eq 0 ]; then
        echo "[yaml] No YAML files found."
        return 0
    fi

    echo "[yaml] Files to check: ${#YAML_FILES[@]}"
    yamllint -s "${YAML_FILES[@]}"
}

# Entry point for YAML validation.
main() {
    echo "[yaml] Running strict YAML validation..."

    set_project_root
    require_yamllint
    collect_yaml_files
    run_yaml_lint

    echo "[yaml] YAML validation passed."
}

main "$@"
