#!/usr/bin/env bash
# Run local quality checks before commit/push.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Prints a warning and continues when an optional tool is missing.
warn_missing_tool() {
    local tool_name="$1"
    echo "[!] ${tool_name} is not installed. Skipping."
}

# Runs ShellCheck for repository shell scripts.
run_shellcheck() {
    echo "[1/4] Running shellcheck..."
    if command -v shellcheck >/dev/null 2>&1; then
        find . -name "*.sh" -not -path "./data/*" -not -path "./.git/*" -print0 | xargs -0 shellcheck
    else
        warn_missing_tool "shellcheck"
    fi
}

# Runs strict YAML validation (required).
run_yaml_checks() {
    echo "[2/4] Running YAML validation..."
    bash scripts/validate-yaml.sh
}

# Runs Python linting when flake8 is available.
run_flake8() {
    echo "[3/4] Running flake8..."
    if command -v flake8 >/dev/null 2>&1; then
        flake8 .
    else
        warn_missing_tool "flake8"
    fi
}

# Runs Python formatting checks when black is available.
run_black() {
    echo "[4/4] Running black..."
    if command -v black >/dev/null 2>&1; then
        black --check .
    else
        warn_missing_tool "black"
    fi
}

# Entry point for local checks.
main() {
    echo "=== Running local code checks ==="

    run_shellcheck
    run_yaml_checks
    run_flake8
    run_black

    echo "=== All local checks passed successfully! ==="
    echo "To run full GitHub Actions locally: bash scripts/run-ci-local.sh"
}

main "$@"
