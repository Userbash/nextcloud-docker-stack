# ☁️ Nextcloud Stack (Docker / Podman)

This repository provides a streamlined setup for deploying a personal or organizational Nextcloud instance. It includes all necessary configurations and scripts to spin up a fully functional cloud environment quickly, without tedious manual setup.

The stack supports standard Docker, as well as Podman in rootless mode for enhanced security.

---

## 🛠 Features and Architecture

A barebones Nextcloud installation requires configuring a database, caching, and SSL certificates manually. This stack integrates these components into a unified, ready-to-deploy environment.

Architecture overview:
- **Nextcloud** — The core cloud platform and web interface.
- **PostgreSQL** — A robust, production-ready relational database.
- **Redis** — In-memory caching for faster load times and session management.
- **Nginx** — Web server serving as a reverse proxy.
- **Certbot** — Automated SSL certificate provisioning and renewal via Let's Encrypt.

---

## 🚀 Quick Start (Local Development)

To deploy the stack locally for testing:

1. Clone the repository:
   ```bash
   git clone https://github.com/suraiya8239/nextcloud-docker-stack.git
   cd nextcloud-docker-stack
   ```
2. Run the startup script:
   ```bash
   bash setup.sh --dev
   ```

Wait a few minutes and open your browser at: `http://localhost:8081`.  
The script will automatically create essential directories, generate an `.env` file with secure default credentials, and start the containers.

---

## 🌍 Production Deployment

For deployment on a VPS or home server with a registered domain:

```bash
bash setup.sh --domain cloud.yourdomain.com --email you@yourdomain.com
```

This command configures Nginx for production and automatically procures a live SSL certificate from Let's Encrypt.

---

## 📚 Documentation

Detailed guides are available to help you configure and maintain the stack:

- [Rootless Podman Setup](docs/ROOTLESS_PODMAN.md) — *Instructions for running the stack without root privileges to maximize host security.*
- [Local CI & Testing](docs/DEVELOPMENT_CI.md) — *Details on our automated testing pipeline and how to run it locally.*
- [Security Guidelines](docs/SECURITY.md) — *Best practices for passwords, port management, and hardening.*
- [Quick Reference](docs/QUICK_REFERENCE.md) — *Common commands for viewing logs, managing backups, and restarting containers.*
- [Troubleshooting](docs/TROUBLESHOOTING.md) — *Solutions for common deployment issues.*

---

## 💻 System Requirements
- **Minimum:** 2 GB RAM, 1 CPU core.
- **Recommended:** 4+ GB RAM.
- **OS:** Any modern Linux distribution (Ubuntu, Debian, Fedora, CentOS).
- **Dependencies:** `docker` and `docker-compose` (or `podman` with `podman-compose`).

---

## 🤝 Contributing
Contributions are welcome! Please open an Issue or submit a Pull Request if you find a bug or have a feature request. Before pushing, please run the local linters (see the CI documentation) to ensure your code meets the repository's formatting standards.

License: MIT.
ос