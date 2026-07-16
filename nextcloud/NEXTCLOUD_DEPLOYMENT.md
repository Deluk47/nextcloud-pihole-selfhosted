# Nextcloud Stack Deployment Guide (Self-Hosted)

This guide describes how to deploy the Nextcloud stack in `nextcloud/` on an Ubuntu host, behind a local reverse proxy, and integrated with a LAN DNS service (for example, Pi-hole). It assumes you are using **Nextcloud All-in-One (AIO)** and a reverse proxy such as **Caddy**. [web:243][web:245]

---

## 1. Prerequisites

- Ubuntu Server (Debian-based) with Docker Engine and Docker Compose installed.
- A local DNS solution (such as Pi-hole) that can resolve a hostname (for example, `cloud.home.arpa`) to your Nextcloud server’s IP.
- A reverse proxy (for example, Caddy) configured as described in `REVERSE-PROXY.md`, listening on ports 80/443 and forwarding to the Nextcloud AIO Apache port (for example, `127.0.0.1:11000`). [web:239][web:248]

---

## 2. Review `nextcloud/compose.yaml`

The `nextcloud/compose.yaml` in this repository defines the Nextcloud AIO master container. A representative pattern looks like:

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

In your actual `compose.yaml`, you may also pass environment variables such as:

- `APACHE_PORT=11000` – the port Apache inside AIO listens on.  
- `APACHE_IP_BINDING=127.0.0.1` – bind Apache to the host loopback for use with a local reverse proxy. [web:241][web:248]  
- `SKIP_DOMAIN_VALIDATION=true` – when running AIO without public DNS/ACME. [web:244][web:247]  

Adjust this example to match your actual `nextcloud/compose.yaml` file.

---

## 3. Environment variables for Nextcloud AIO

If you use a `.env` file for the Nextcloud stack:

1. Create `.env` from the example file:

   ```bash
   cd ~/nextcloud-pihole-selfhosted/nextcloud
   cp .env.example .env
   ```

2. Edit `.env`:

   ```bash
   nano .env
   ```

   Set values such as:

   - `NEXTCLOUD_DOMAIN` – the hostname you will use via the reverse proxy (for example, `cloud.home.arpa`). [web:243]  
   - `TZ` – your timezone (for example, `Europe/London`).  
   - `APACHE_PORT` – the Apache port inside AIO (for example, `11000`) used by the reverse proxy. [web:248]  
   - `APACHE_IP_BINDING` – typically `127.0.0.1` when AIO is behind a reverse proxy on the same host. [web:241]  
   - `SKIP_DOMAIN_VALIDATION` – set to `true` if you follow the documented approach to skip AIO’s domain validation when using a purely local reverse proxy. [web:244][web:247]

3. Ensure `.env` is ignored by Git:

   ```bash
   echo ".env" >> .gitignore
   ```

---

## 4. Configure the reverse proxy and DNS

Follow `PIHOLE_DEPLOYMENT.md` and `REVERSE-PROXY.md` first so that:

- Pi-hole resolves `NEXTCLOUD_DOMAIN` (for example, `cloud.home.arpa`) to the Nextcloud host IP.
- The reverse proxy (for example, Caddy) listens on 80/443 and forwards traffic to `127.0.0.1:11000` (Apache inside AIO). [web:239][web:245]

Example Caddy snippet (for reference):

```caddy
cloud.home.arpa {
	tls internal

	# Nextcloud main endpoint
	handle {
		reverse_proxy 127.0.0.1:11000
	}
}
```

The exact Caddyfile and deployment details are documented in `REVERSE-PROXY.md`.

---

## 5. Start the Nextcloud AIO stack

From the unified repository:

```bash
cd ~/nextcloud-pihole-selfhosted/nextcloud
docker compose up -d
```

Check that the containers are running:

```bash
docker ps --filter "name=nextcloud-aio"
```

You should see entries such as:

- `nextcloud-aio-mastercontainer`  
- `nextcloud-aio-apache`  
- other AIO-managed containers (database, redis, etc.) [web:243][web:248]

If containers do not start, inspect logs:

```bash
docker logs nextcloud-aio-mastercontainer
```

---

## 6. Complete the AIO setup wizard

1. Access the AIO interface directly via the mapped port (default example):

   ```text
   https://<SERVER_IP>:8080
   ```

2. In the AIO interface:

   - Set the **domain** to your `NEXTCLOUD_DOMAIN` (for example, `cloud.home.arpa`).  
   - Enable “reverse proxy mode” if prompted and ensure the Apache port matches `APACHE_PORT` (for example, `11000`). [web:239][web:248]  
   - Create the initial admin user and choose any optional apps you want installed. [web:243]

3. Start the stack from the AIO interface (if required). AIO will create and manage the internal containers.

---

## 7. Validate DNS and reverse proxy

Once AIO is configured and the reverse proxy is running:

1. From a LAN client using Pi-hole, confirm hostname resolution:

   ```bash
   dig cloud.home.arpa
   ```

   Replace with your actual `NEXTCLOUD_DOMAIN`. The answer should be the IP of your Nextcloud host. [web:245]

2. In a browser on the same client, open:

   ```text
   https://cloud.home.arpa
   ```

3. Verify that:

   - The browser connects over HTTPS (you may see a warning if using an internal CA like Caddy’s `tls internal`). [web:229][web:232]  
   - The request reaches the Nextcloud login page via the reverse proxy.  
   - You can log in with the admin account created during the AIO setup. [web:243]

If you receive 502 errors, consult `REVERSE-PROXY.md` (port conflicts, especially around `11000`, and AIO’s `nextcloud-aio-domaincheck` container are common culprits). [web:239][web:245]

---

## 8. Routine operations

### 8.1 Updating the Nextcloud AIO stack

To update containers and configuration from this repository:

```bash
cd ~/nextcloud-pihole-selfhosted/nextcloud
git pull origin main          # if this repo is your source of truth
docker compose pull
docker compose up -d
```

AIO-managed updates may also be initiated from the AIO interface; follow the upstream AIO documentation for version-specific guidance. [web:243]

### 8.2 Inspecting logs

For the master container:

```bash
docker logs nextcloud-aio-mastercontainer
```

For the Apache container:

```bash
docker logs nextcloud-aio-apache
```

Check the reverse proxy logs (`caddy`, `nginx`, or `traefik`) if you see HTTP 502 or TLS-related issues. [web:239]

---

## 9. Backups and recovery

At minimum, you should back up:

- Nextcloud data volumes (user files).  
- Database volumes (if using an external DB rather than AIO’s internal one).  
- Nextcloud AIO configuration volumes (for example, `nextcloud_aio_mastercontainer`). [web:240][web:245]

Options include:

- Using Nextcloud AIO’s built-in Borg-based backup solution, following the official AIO documentation. [web:240]  
- Using external tooling or scripted volume backups as described in `RESTORE.md` and `AUTOMATED-BACKUPS.md` in this repository.

Test your restore process regularly on a non-production environment to ensure that you can recover the full Nextcloud stack and data if needed. [web:240]
