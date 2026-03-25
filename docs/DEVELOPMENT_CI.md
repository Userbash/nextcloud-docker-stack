# Local Testing and CI Configuration

To maintain code quality and prevent syntax errors from breaking deployments, this repository utilizes an automated testing pipeline. You can run all CI checks locally prior to pushing your commits.

---

## CI Pipeline Overview

Whenever code is pushed or a Pull Request is opened against the `main` or `dev` branches, GitHub Actions automatically triggers `ci.yml`.

The pipeline executes the following checks:
1. **ShellCheck:** Lints all `*.sh` scripts to detect bash quoting, syntax errors, and edge-case pitfalls. The database payload (`data/`) directories are explicitly bypassed to prevent traversing permissions issues.
2. **Yamllint:** Validates syntax and formatting inside `docker-compose.yaml` and other YAML configurations to catch spacing or indentation errors.
3. **Black / Flake8 (Python):** Enforces PEP-8 style guidelines and detects syntax formatting errors within Python scripts.

---

## Running CI Locally

To quickly validate your code before making a commit, you can use `act`, a local GitHub Actions simulator.

Use the provided wrapper script to run the full pipeline locally:

```bash
bash scripts/run-ci-local.sh
```

### How `act` executes locally
- Executing `run-ci-local.sh` checks if `act` is installed on your host and provides instructions if missing.
- `act` binds to the `.github/workflows/ci.yml` file and utilizes configurations found in the `.actrc` file. This ensures `act` runs silently in headless mode, automatically fetching the default Docker image needed for testing without interrupting the terminal.

---

## Running Native Linters (No Containers)

If you prefer to lint scripts continuously without waiting on `act` or container environments, you can execute standard host-side linters:

```bash
bash scripts/run-linters.sh
```
This script directly triggers Black and ShellCheck if they are installed locally on your system, bypassing the container environment entirely.
