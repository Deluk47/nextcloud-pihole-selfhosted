# Nextcloud Stack Deployment Guide (Self-Hosted)

This guide describes how to deploy the Nextcloud stack defined in `nextcloud/` on an Ubuntu host, behind a reverse proxy, and integrated with a local DNS service (for example, Pi-hole).

---

## Prerequisites

- Ubuntu Server (Debian-based) with Docker and Docker Compose.
- A local DNS solution (such as Pi-hole) capable of resolving internal hostnames to your Nextcloud server.
- A reverse proxy (such as Caddy, Nginx, or Traefik) running on the same host or in the same Docker network to route HTTPS traffic to Nextcloud.

---

## Step 1: Review compose configuration

The `nextcloud/compose.yaml` in this repository defines the Nextcloud stack. It might include:

- A Nextcloud All-in-One (AIO) master container, or
- Separate services for Nextcloud, database, caching, and related apps.

Example (simplified pattern):

```yaml
services:
  nextcloud-aio-mastercontainer:
    image: ghcr.io/nextcloud-releases/all-in-one:latest
    container_name: nextcloud-aio-mastercontainer
    restart: always
    ports:
      - "8080:8080"
    volumes:
      - nextcloud_aio_mastercontainer:/mnt/docker-aio-config
      - /var/run/docker.sock:/var/run/docker.sock:ro

volumes:
  nextcloud_aio_mastercontainer:
```

Adjust this example to match your actual `compose.yaml` in the `nextcloud/` folder.

---

## Step 2: Environment variables (optional but recommended)

If you use a `.env` file for the Nextcloud stack:

1. Create `.env` from an example file:

   ```bash
   cd /path/to/nextcloud-pihole-selfhosted/nextcloud
   cp .env.example .env
   ```

2. Edit `.env` to set values such as:

   - `NEXTCLOUD_DOMAIN` – a hostname you control on your LAN or public DNS (for example, `cloud.example.local`).
   - `TZ` – your timezone.
   - Database credentials or other internal secrets if not handled by Nextcloud AIO.

Ensure `.env` is listed in `.gitignore` so secrets are not committed.

---

## Step 3: Configure the reverse proxy

The `nextcloud/reverse-proxy/` directory contains configuration for your reverse proxy. A typical entry for Caddy (as an example) might look like:

```caddyfile
cloud.example.local {
  tls internal
  reverse_proxy nextcloud-aio-apache:11000
}
```

Key ideas (regardless of proxy):

- The proxy listens on ports 80/443 on the host.
- It forwards traffic to the Nextcloud container by service name and port on the Docker network.
- The hostname (`cloud.example.local` here) is resolved by your DNS solution to the server’s IP.

Update the configuration files in `nextcloud/reverse-proxy/` so they match your actual service names, ports, and chosen hostname.

---

## Step 4: Start the Nextcloud stack from this repository

From the unified repository:

```bash
cd /path/to/nextcloud-pihole-selfhosted/nextcloud
docker compose up -d
```

Check that the containers are running:

```bash
docker ps
```

The Nextcloud containers should show a status of `Up`. If you are using Nextcloud AIO, you may need to complete the initial setup through the AIO interface. [web:162][web:222][web:227]

---

## Step 5: Complete Nextcloud application setup

Depending on your configuration:

- For Nextcloud AIO:
  - Visit the AIO setup interface using the mapped port from `compose.yaml` (for example, `https://<SERVER_IP>:8080`).
  - Follow the wizard to set the domain, admin account, and optional apps. [web:162][web:222]

- For a non-AIO stack:
  - Access the web interface via your reverse proxy hostname (for example, `https://cloud.example.local`).
  - Complete the initial Nextcloud installation (database connection, admin user creation, etc.). [web:228]

---

## Step 6: Validate DNS and proxy integration

With DNS and the reverse proxy configured:

1. Confirm that your chosen hostname resolves to the server IP:

   ```bash
   dig cloud.example.local
   ```

   Replace `cloud.example.local` with your actual hostname.

2. From a client device on the network, open:

   ```text
   https://cloud.example.local
   ```

3. Verify that:

   - DNS resolution is correct.
   - The reverse proxy terminates TLS and forwards traffic to Nextcloud.
   - The Nextcloud web interface loads and you can log in.

---

## Step 7: Operational tasks

To update the Nextcloud stack:

```bash
cd /path/to/nextcloud-pihole-selfhosted/nextcloud
git pull origin main   # if you are using this repo as the source of truth
docker compose pull
docker compose up -d
```

To inspect logs for troubleshooting:

```bash
docker logs nextcloud-aio-mastercontainer
# or the specific Nextcloud service name used in your compose.yaml
```

For backups:

- Use Nextcloud’s built-in backup tools, Nextcloud AIO backup features, or
- Export/snapshot the data volumes and database using your preferred backup strategy. [web:226][web:228]

