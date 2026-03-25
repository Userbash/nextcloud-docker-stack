# Contributing to Nextcloud Docker Stack

First off, thank you for considering contributing to Nextcloud Docker Stack! 🎉

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md).
By participating, you are expected to uphold this code.

## How to Contribute

### Reporting Bugs 🐛

Before creating bug reports, please check the issue list as you might find out that you don't need to create one.

When you are creating a bug report, please include as many details as possible:

* **Use a clear and descriptive title**
* **Describe the exact steps which reproduce the problem**
* **Provide specific examples to demonstrate the steps**
* **Describe the behavior you observed after following the steps**
* **Explain which behavior you expected to see**
* **Include screenshots if possible**
* **Your environment** (OS, Docker version, etc.)

### Suggesting Enhancements 💡

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

* **Use a clear and descriptive title**
* **Provide a step-by-step description of the suggested enhancement**
* **Provide specific examples to demonstrate the steps**
* **Describe the current behavior and the expected behavior**
* **Explain why this enhancement would be useful**

### Pull Requests 📝

* Fill in the required template
* Follow the shell script and Docker compose style guides
* Include appropriate test cases
* Update documentation as needed
* End all files with a newline

## Development Setup

1. Fork and clone the repository
   ```bash
   git clone https://github.com/YOUR-USERNAME/nextcloud-docker-stack.git
   cd nextcloud-docker-stack
   ```

2. Create a new branch for your feature or bug fix
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. Make your changes and test locally
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   docker-compose up -d
   ./scripts/health-check.sh
   ```

4. Commit your changes
   ```bash
   git add .
   git commit -m "Descriptive commit message"
   ```

5. Push your branch and create a Pull Request
   ```bash
   git push origin feature/your-feature-name
   ```

## Style Guides

### Shell Scripts

* Use `#!/bin/bash` shebang
* Use `set -euo pipefail` for error handling
* Add comments for complex logic
* Use meaningful variable names
* Follow ShellCheck recommendations

### Docker Compose

* Use specific image versions (not `latest`)
* Include health checks where applicable
* Use environment variables for configuration
* Document all environment variables
* Include proper restart policies

### Documentation

* Use clear, concise language
* Include code examples where helpful
* Update README.md for significant changes
* Keep documentation in sync with code

### Commit Messages

* Use the present tense ("Add feature" not "Added feature")
* Use the imperative mood ("Move cursor to..." not "Moves cursor to...")
* Limit the first line to 72 characters or less
* Reference issues and pull requests liberally after the first line

Example:
```
Add backup retention policy

Implement automatic cleanup of backups older than 7 days
to prevent disk space issues. This can be configured via
the BACKUP_RETENTION_DAYS environment variable.

Fixes #123
```

## Testing

Before submitting a PR, please test:

1. **Health checks pass**
   ```bash
   ./scripts/health-check.sh
   ```

2. **Scripts are executable**
   ```bash
   chmod +x scripts/*.sh
   ```

3. **No hardcoded secrets or sensitive data**
   ```bash
   git grep -E "(password|secret|key|token)" -- '*.yaml' '*.yml'
   ```

4. **Docker compose is valid**
   ```bash
   docker-compose config -q
   ```

5. **All documentation is updated**

## Project Structure

```
nextcloud-docker-stack/
├── .github/              # GitHub templates and workflows
├── docs/                 # Documentation
├── scripts/              # Management scripts
├── config/               # Configuration files
├── nginx/                # Nginx configuration
├── php/                  # PHP configuration
├── docker-compose.yaml   # Main compose file
├── .env.example          # Environment template
├── README.md
└── CONTRIBUTING.md
```

## Questions?

Feel free to open an issue with your question, and we'll do our best to help!

## License

By contributing, you agree that your contributions will be licensed under its MIT License.
