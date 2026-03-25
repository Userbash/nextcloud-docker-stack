#!/bin/bash
# Script for running local linters before committing
# Saves time by checking code locally before pushing to remote CI.

set -e

echo "=== Running local code checks ==="

# 1. Shell scripts check
if command -v shellcheck &> /dev/null; then
    echo "[1/4] Running shellcheck..."
    find . -name "*.sh" -not -path "./data/*" -not -path "./.git/*" -print0 | xargs -0 shellcheck
else
    echo "[!] shellcheck is not installed. Skipping."
fi

# 2. YAML check
if command -v yamllint &> /dev/null; then
    echo "[2/4] Running yamllint..."
    yamllint docker-compose*.yaml .github/workflows/
else
    echo "[!] yamllint is not installed. Skipping."
fi

# 3. Python code check (flake8)
if command -v flake8 &> /dev/null; then
    echo "[3/4] Running flake8..."
    flake8 .
else
    echo "[!] flake8 is not installed. Skipping."
fi

# 4. Python code formatting check (black)
if command -v black &> /dev/null; then
    echo "[4/4] Running black..."
    black --check .
else
    echo "[!] black is not installed. Skipping."
fi

echo "=== All local checks passed successfully! ==="
echo "To run a full GitHub Actions simulation, use the wrapper: bash scripts/run-ci-local.sh"
