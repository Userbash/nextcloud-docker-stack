# Running Nextcloud in Rootless Podman

This guide explains how to deploy the Nextcloud stack using Podman in rootless mode. Running containers as an unprivileged system user significantly enhances security compared to running them as the root user.

If a vulnerability in Nextcloud or a plugin allows an attacker to break out of the container, a rootless setup ensures they are confined to a restricted, unprivileged namespace without access to modify the host system.

---

## Step 1. Creating a Dedicated System User

It is highly recommended to run the stack under a dedicated system user rather than your primary interactive user account. We will create a user named `nextcloud_user`.

Run the following script to create the user (this step requires `sudo`):

```bash
sudo bash scripts/setup-rootless-user.sh nextcloud_user
```
The script provisions the user, allocates necessary sub-UIDs/sub-GIDs for file mapping, and enables "linger" via systemd. Linger allows the user's background processes to remain active after the user's SSH session ends.

---

## Step 2. Switching to the New User

From this point forward, all commands must be executed as the newly created user:

```bash
sudo su - nextcloud_user
cd ~/projects/nextcloud-docker-stack
```

---

## Step 3. Directory Initialization

Prepare the file system and required directories:

```bash
bash scripts/init-rootless.sh
```
This script ensures the `data/` and `logs/` directories are initialized correctly, sets up a default `.env` configuration file, and starts the unprivileged `podman.socket` tied to the user's session.

---

## Step 4. Deploying Portainer (Optional)

If you prefer a graphical interface for container management, you can optionally install Portainer. The provided script will mount the secure, unprivileged socket directly into the Portainer container.

```bash
bash scripts/setup-portainer.sh
```
Once deployed, the Portainer UI will be accessible at `https://<YOUR_SERVER_IP>:9443`.

---

## Step 5. Starting the Stack

Start the core Nextcloud environment (Cloud, Database, and Web Server):

```bash
bash scripts/manage-rootless.sh start
```

### Managing the Environment

The `manage-rootless.sh` script is provided as a convenient wrapper to simplify stack management without constructing long compose commands.

Available commands:
- View status: `bash scripts/manage-rootless.sh ps`
- View all logs: `bash scripts/manage-rootless.sh logs`
- View specific service logs (e.g., database): `bash scripts/manage-rootless.sh logs db`
- Stop the stack: `bash scripts/manage-rootless.sh stop`

---

## Important Considerations for Rootless Mode

1. **Unprivileged Ports:** In Linux, unprivileged users cannot bind to ports below `1024` natively. Internally, Nginx binds to 80 and 443, but exposes them externally as `8080` and `8443` (this configuration is found in `.env`). In production, you will need to set up port forwarding via `iptables`/`ufw` or use a front-facing reverse proxy to route traffic from standard HTTP/HTTPS ports.
2. **SELinux Volume Labels:** In `docker-compose.rootless.yaml`, bind mounts are suffixed with `:Z` or `:z`. Do not remove these flags. They instruct the Kernel security module (e.g., SELinux on RedHat/Fedora) to correctly label the files so the specific unprivileged container processes have write access. Removing them will result in "Access Denied" application errors.
