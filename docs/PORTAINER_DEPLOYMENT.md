# Portainer Deployment Guide

This guide covers deploying **Portainer** as a web-based container management UI on top of
a rootless **Podman** environment and then initialising the Nextcloud stack through Portainer.

---

## Overview

Portainer provides a graphical interface for managing containers, stacks, volumes, and
networks.  It connects to the Podman API socket and lets you deploy a Docker Compose /
Podman Compose stack without touching the command line after the initial setup.

---

## Prerequisites

| Requirement | How to verify |
|-------------|---------------|
| Setup script completed successfully | `id nextcloud-app && id nextcloud-rootless` |
| Podman installed | `podman --version` |
| Subuid / subgid configured | `grep nextcloud-rootless /etc/subuid /etc/subgid` |
| Root / sudo access | `sudo -v` |

---

## Phase 1 — Run the Setup Script

The `scripts/setup-portainer.sh` script automates pre-flight checks and container
deployment.

```bash
sudo bash scripts/setup-portainer.sh
```

### What the script does

1. **Pre-flight checks** — verifies that the `nextcloud-app` and `nextcloud-rootless` users
   exist and that Podman is installed.
2. **Enables `podman.socket`** — activates the system-wide Podman API socket so that
   Portainer can communicate with the Podman daemon.
3. **Creates a persistent data volume** — `portainer_data` stores Portainer configuration
   across container restarts.
4. **Starts the Portainer container** — exposes the web UI on port **9443** (HTTPS) and
   the tunnel/agent endpoint on port **8000**.

You can skip the user checks if the environment is already known to be correct:

```bash
sudo bash scripts/setup-portainer.sh --skip-checks
```

---

## Phase 2 — Configure Secrets

Before deploying the Nextcloud stack you must populate the secure environment file with
real credentials.

1. SSH into the server.
2. Open the template:

   ```bash
   sudo nano /root/nextcloud-docker-stack/.env.secure
   # or, if the project is in a different directory:
   sudo nano .env.secure
   ```

3. Replace every `generate_secure_password_here` placeholder with a strong, unique value.
   Recommended minimum length: **24 characters**.

   ```
   MYSQL_ROOT_PASSWORD=<strong-random-password>
   MYSQL_PASSWORD=<strong-random-password>
   NEXTCLOUD_ADMIN_USER=admin
   NEXTCLOUD_ADMIN_PASSWORD=<strong-random-password>
   REDIS_PASSWORD=<strong-random-password>
   ```

4. Save and close (`Ctrl+O`, `Enter`, `Ctrl+X` in nano).
5. Verify the file permissions remain `600`:

   ```bash
   stat -c '%a %n' .env.secure
   # expected output: 600 .env.secure
   ```

---

## Phase 3 — Initialise Portainer

1. Open a browser and navigate to `https://<YOUR_SERVER_IP>:9443`.
2. Accept the self-signed certificate warning.
3. Create the initial administrator account (username + strong password).
4. Click **"Get Started"** to use the local Podman environment.

---

## Phase 4 — Deploy the Nextcloud Stack in Portainer

1. In the Portainer dashboard select your **Local** environment.
2. Click **Stacks** in the left sidebar, then **Add stack**.
3. Name the stack — for example, `nextcloud-stack`.
4. Select **Web editor** and paste the contents of `docker-compose.rootless.yaml`.
5. Scroll down to **Environment variables**:
   - Click **Load variables from .env file** and upload the configured `.env.secure` file,
     **or** add each variable manually in the key/value fields.
6. Click **Deploy the stack**.

> **Note:** The first deployment may take several minutes while Podman pulls the
> images and the database initialises.

---

## Phase 5 — Verify the Deployment

1. In Portainer navigate to **Containers**.
2. Confirm that every Nextcloud stack container (`db`, `app`, `redis`, `nginx`, etc.) shows
   status **Running**.
3. Open your Nextcloud instance:
   - Development: `https://localhost:8443`
   - Production: `https://<your-domain>`

---

## Troubleshooting

### Portainer cannot connect to Podman

Check that the system Podman socket is active:

```bash
systemctl status podman.socket
```

If the unit is not found, try the user socket instead and adjust the socket path in
`scripts/setup-portainer.sh` accordingly:

```bash
# As nextcloud-rootless:
systemctl --user start podman.socket
echo $XDG_RUNTIME_DIR   # typically /run/user/5001
```

### Portainer web UI is unreachable

Ensure ports 9443 and 8000 are open in the firewall:

```bash
sudo ufw allow 9443/tcp
sudo ufw allow 8000/tcp
```

### Stack deployment fails with "env variable not set"

Verify that all variables referenced in the compose file are present in the `.env.secure`
file you uploaded, or in the **Environment variables** section of the Portainer stack form.

---

## AI Agent Operations Plan

For automated management of this infrastructure, an agent should follow these phases.

### Phase 1 — Daily state check

- Call the Portainer API to retrieve container statuses (`/api/endpoints/{id}/docker/containers/json`).
- Parse container logs for critical patterns: OOM kills, `Database connection lost`, `FATAL`.
- Check available disk space on the host.

### Phase 2 — Configuration drift management

- Compare the running stack definition against the reference `docker-compose.rootless.yaml`
  in the Git repository.
- On detected drift: create a database backup, then trigger a stack redeploy via the
  Portainer API (`PUT /api/stacks/{id}?endpointId={id}`).

### Phase 3 — Automated image updates (scheduled)

- Check for new image tags (Nextcloud, MariaDB/PostgreSQL, Redis).
- Stop dependent services → run the volume backup script (`scripts/backup.sh`).
- Send a `PUT` request to the Portainer API with `PullImage: true` to update the stack.
- Perform an HTTP health-check: wait for a `200 OK` response from the Nextcloud web interface.

### Phase 4 — Security and incident remediation

- If a service crashes more than **3 times per hour**, roll back to the previous stable
  image tag.
- Periodically verify that `.env.secure` retains `600` permissions and is owned by the
  expected user:

  ```bash
  stat -c '%a %U' .env.secure
  # expected: 600 root   (or the appropriate owner)
  ```

---

*For general quick-reference commands see [docs/QUICK_REFERENCE.md](QUICK_REFERENCE.md).*  
*For security guidance see [docs/SECURITY_HARDENING_GUIDE.md](SECURITY_HARDENING_GUIDE.md).*
