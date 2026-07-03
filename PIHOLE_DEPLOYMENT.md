# Pi-hole Deployment Guide (Self-Hosted Network)

This guide describes how to deploy the Pi-hole DNS and ad-blocking stack defined in this repository on an Ubuntu Server host. Pi-hole acts as the DNS/DHCP layer for a self-hosted Nextcloud and other services.

---

## Prerequisites

- **OS**: Ubuntu Server (Debian-based).
- **Firewall**: UFW (Uncomplicated Firewall) enabled.
- **Containers**: Docker and Docker Compose installed.
- **Repository layout**: This guide assumes the repo is checked out at `~/pihole`.

---

## Step 1: DNS and system resolver considerations

Pi-hole needs to bind to port `53` for DNS. If system services such as `systemd-resolved` are still listening on port `53`, container startup will fail.

1. Check whether anything is bound to port 53:

   ```bash
   sudo ss -tulpn | grep :53
   ```

2. If you see `systemd-resolved` or another service binding `:53`, you can either:
   - Configure `systemd-resolved` with `DNSStubListener=no` in `/etc/systemd/resolved.conf` and restart it, or
   - Stop and disable `systemd-resolved` entirely if you prefer Pi-hole to own DNS on the host.

   Example (disable completely):

   ```bash
   sudo systemctl stop systemd-resolved
   sudo systemctl disable systemd-resolved
   ```

3. Verify the port is free:

   ```bash
   sudo ss -tulpn | grep :53
   ```

   No output indicates that port `53` is now available.

---

## Step 2: Configure UFW for DNS and web admin

Open required ports on the host firewall:

```bash
# DNS (53/TCP and 53/UDP)
sudo ufw allow 53/tcp
sudo ufw allow 53/udp

# Pi-hole web admin (mapped from container port 80 to host 8081/8082)
sudo ufw allow 8081/tcp
sudo ufw allow 8082/tcp

sudo ufw reload
```

These rules allow clients to send DNS queries and you to access the web admin UI through the mapped HTTP ports.

---

## Step 3: Prepare Pi-hole environment variables

This repository uses `.env` for sensitive values.

1. Create `.env` from the example:

   ```bash
   cd ~/pihole
   cp .env.example .env
   ```

2. Edit `.env` and set:

   ```bash
   TZ=Europe/London
   FTLCONF_webserver_api_password=<YOUR_SECURE_PASSWORD>
   ```

   Replace `<YOUR_SECURE_PASSWORD>` with a strong Pi-hole web/API password. The `.env` file is gitignored and not committed.

---

## Step 4: Review the Compose configuration

The Pi-hole stack is defined in `compose.yaml`:

```yaml
services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8082:80/tcp"
      - "8081:80/tcp"
    env_file:
      - .env
    environment:
      - TZ=${TZ}
      - FTLCONF_webserver_api_password=${FTLCONF_webserver_api_password}
    volumes:
      - './etc-pihole:/etc/pihole'
      - './etc-dnsmasq.d:/etc/dnsmasq.d'
    dns:
      - 127.0.0.1
      - 1.1.1.1
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
```

- `etc-pihole` and `etc-dnsmasq.d` are bind mounts for Pi-hole configuration and DNS settings.
- `cap_add: NET_ADMIN` is required for DHCP and advanced networking.

---

## Step 5: Start and verify Pi-hole

1. Start Pi-hole in detached mode:

   ```bash
   cd ~/pihole
   docker compose up -d
   ```

2. Check container status:

   ```bash
   docker ps
   ```

   The `pihole` container should report `Up` and, ideally, a healthy status.

3. Access the web admin UI:

   ```text
   http://<YOUR_SERVER_IP>:8081/admin
   ```

   or, if you prefer the second mapping:

   ```text
   http://<YOUR_SERVER_IP>:8082/admin
   ```

   Log in using the password defined in `.env`.

---

## Step 6: Configure DHCP and local DNS (optional but recommended)

Once Pi-hole is running:

1. Decide whether Pi-hole will act as your DHCP server.
2. If yes, disable DHCP on your ISP router and enable Pi-hole DHCP in the admin UI.
3. Add local DNS records for internal services, such as:
   - `nextcloud.home.arpa -> <Nextcloud/Caddy host IP>`
   - `dunirvgou.cloud -> <Nextcloud/Caddy host IP>`

This makes client devices resolve your self-hosted services by name, using Pi-hole as the DNS source.

---

## Troubleshooting: Port 53 "address already in use"

If you see an error like:

```text
failed to bind host port 0.0.0.0:53/tcp: address already in use
```

then another service is still holding port 53.

1. Check the binding process:

   ```bash
   sudo ss -tulpn | grep :53
   ```

2. Stop or disable the conflicting service (typically `systemd-resolved`), as shown earlier.

3. Bring down the stack and restart:

   ```bash
   docker compose down
   docker compose up -d
   ```

If the port is free and the container still fails, inspect logs with:

```bash
docker logs pihole
```

for more details.

