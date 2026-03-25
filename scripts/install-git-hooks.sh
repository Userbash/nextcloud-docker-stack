#!/usr/bin/env bash
# Configure local git hooks for this repository.

set -euo pipefail

PROJECT_ROOT=""

# Resolves and enters project root.
set_project_root() {
	PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
	cd "$PROJECT_ROOT"
}

# Makes local hook scripts executable.
ensure_hook_permissions() {
	chmod +x .githooks/pre-push scripts/validate-yaml.sh scripts/run-linters.sh
}

# Points Git to repository-managed hooks.
configure_hooks_path() {
	git config core.hooksPath .githooks
}

# Entry point for hook installation.
main() {
	set_project_root
	ensure_hook_permissions
	configure_hooks_path
	echo "Git hooks installed. core.hooksPath=.githooks"
}

main "$@"
