# Pi-hole Deployment Guide (Self-Hosted / Self-Contained Cloud)

This guide describes how to deploy and verify Pi-hole on an Ubuntu Server host for a self-contained home cloud (including Nextcloud). Pi-hole runs in Docker bridge mode and provides DNS for your LAN, including a local record for `<YOUR_CLOUD_HOSTNAME>`. [web:74][web:164]

> **Terminology:**  
> - **Pi-hole host IP** = the LAN IP address of the machine running the Pi-hole container (for example `192.168.0.53`).  
> - **\<YOUR_CLOUD_HOSTNAME\>** = the internal DNS name you will use for your cloud service (for example `cloud.home.arpa` or `nextcloud.home.arpa`).  
> - LAN clients (like your jump host) must use the Pi-hole host IP as their DNS server.

> **Choosing `<YOUR_CLOUD_HOSTNAME>` (best practice):**  
> For purely internal services, use a **private, non-public** domain such as a subdomain of `home.arpa` (reserved for home networks) instead of a made-up public TLD. Examples: `cloud.home.arpa`, `nextcloud.home.arpa`, `files.home.arpa`. [web:74]

---

## 1. Free port 53 on the host

Pi-hole must own port `53/tcp` and `53/udp` on the host. Disable any service already listening there (typically `systemd-resolved`). [web:146][web:147]

1. Check port 53 usage:

   ```bash
   sudo ss -tulpn | grep :53
   ```

2. Stop and disable `systemd-resolved` if it appears:

   ```bash
   sudo systemctl stop systemd-resolved
   sudo systemctl disable systemd-resolved
   sudo systemctl mask systemd-resolved
   ```

3. Fix `/etc/resolv.conf` so it’s a normal file you can edit: [web:145]

   ```bash
   ls -l /etc/resolv.conf
   ```

   If it is a symlink to `systemd-resolved`, remove and recreate it:

   ```bash
   sudo rm /etc/resolv.conf
   sudo tee /etc/resolv.conf > /dev/null << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
   ```

4. Confirm port 53 is now free:

   ```bash
   sudo ss -tulpn | grep :53 || echo "Port 53 free"
   ```

---

## 2. Configure UFW firewall

Open only what Pi-hole and administration need, *before* starting the container. [web:79][web:81]

1. Set default policy:

   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   ```

2. Allow SSH (admin):

   ```bash
   sudo ufw allow 22/tcp
   ```

3. Allow DNS:

   ```bash
   sudo ufw allow 53/tcp
   sudo ufw allow 53/udp
   ```

4. Allow Pi-hole web UI (HTTP on 8080):

   ```bash
   sudo ufw allow 8080/tcp
   ```

5. Enable UFW and reload:

   ```bash
   sudo ufw enable
   sudo ufw reload
   sudo ufw status verbose
   ```

---

## 3. Prepare Pi-hole environment (.env)

Use an environment file for timezone and Pi-hole web password. [web:39][web:164]

1. Go to the Pi-hole folder:

   ```bash
   cd ~/nextcloud-pihole-selfhosted/pihole
   ```

2. Create `.env` (or copy from example):

   ```bash
   cp .env.example .env  # if .env.example exists
   ```

3. Edit `.env`:

   ```bash
   nano .env
   ```

   Example:

   ```bash
   TZ=Europe/London
   FTLCONF_webserver_api_password=myhole12
   ```

4. Ensure `.env` is **not** committed:

   ```bash
   echo ".env" >> .gitignore
   ```

---

## 4. Write / confirm `compose.yaml` (Docker bridge mode)

Pi-hole runs in Docker’s default bridge network, with host ports mapped for DNS and web. [web:39][web:74]

```yaml
services:
  pihole:
    container_name: pihole
    image: pihole/pihole:latest

    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "8080:80/tcp"
      - "8443:443/tcp"

    env_file:
      - .env

    environment:
      - TZ=${TZ}
      - FTLCONF_webserver_api_password=${FTLCONF_webserver_api_password}
      # Optional: widen listeningMode via env if needed
      # - FTLCONF_dns_listeningMode=all

    volumes:
      - "./etc-pihole:/etc/pihole"
      - "./etc-dnsmasq.d:/etc/dnsmasq.d"

    dns:
      - 8.8.8.8
      - 8.8.4.4

    restart: unless-stopped

    cap_add:
      - NET_ADMIN
```

---

## 5. Start the Pi-hole container

1. Start:

   ```bash
   cd ~/nextcloud-pihole-selfhosted/pihole
   docker compose up -d
   ```

2. Check container status and published ports:

   ```bash
   docker ps --filter "name=pihole" \
     --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
   ```

3. Get the container’s bridge IP (for host-only diagnostics):

   ```bash
   docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' pihole
   ```

   Example: `172.18.0.2` (for host diagnostics only). [web:39]

---

## 6. Configure Pi-hole DNS and listening behavior

Use the web UI on the Pi-hole host. [web:151][web:163]

1. In a browser, open:

   ```text
   http://<PI-HOLE_HOST_IP>:8080/admin
   ```

2. **Upstream DNS Servers** (Settings → DNS):

   - Enable **Custom**.
   - Set:
     - `8.8.8.8`
     - `8.8.4.4`
   - Disable other upstreams if you want only Google DNS. [web:151][web:155]

3. **Interface listening behavior** (Settings → DNS):

   - Select **Listen on all interfaces, permit all origins**.  
     This allows LAN clients (including your jump host) to query Pi-hole when Pi-hole is running in Docker bridge mode. [web:163][web:175]

4. Save.

---

## 7. Add the local DNS record for your cloud

Create an internal DNS name for your cloud service, such as Nextcloud. [web:101][web:196]

1. In the Pi-hole admin UI, go to **Local DNS → DNS Records**.
2. Add:

   - **Domain**: `<YOUR_CLOUD_HOSTNAME>`
   - **IP**: `<PI-HOLE_HOST_IP>`

   Example:

   - Domain: `cloud.home.arpa`
   - IP: `192.168.0.53` (Pi-hole host IP)

3. Save.

---

## 8. Configure clients to use Pi-hole

Point clients (e.g. your jump host) at the Pi-hole host IP for DNS. [web:196][web:164]

On the **jump host**:

```bash
sudo tee /etc/resolv.conf > /dev/null << 'EOF'
nameserver <PI-HOLE_HOST_IP>
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
```

Example:

```bash
nameserver 192.168.0.53
nameserver 1.1.1.1
nameserver 8.8.8.8
```

---

## 9. Sanity-check Pi-hole behavior

### 9.1 On the Pi-hole host

```bash
dig @127.0.0.1 cloudflare.com
dig @127.0.0.1 <YOUR_CLOUD_HOSTNAME>
```

Both should return `NOERROR`, and `<YOUR_CLOUD_HOSTNAME>` should resolve to your Pi-hole host IP. [web:194]

### 9.2 From a LAN client (jump host)

Verify the client is using Pi-hole:

```bash
cat /etc/resolv.conf
# Should show: nameserver <PI-HOLE_HOST_IP>
```

Then:

```bash
dig @<PI-HOLE_HOST_IP> cloudflare.com
dig @<PI-HOLE_HOST_IP> <YOUR_CLOUD_HOSTNAME>
dig <YOUR_CLOUD_HOSTNAME>
```

Expected:

- `cloudflare.com` returns valid A records.
- `<YOUR_CLOUD_HOSTNAME>` returns `<PI-HOLE_HOST_IP>`.
- The `SERVER:` line in `dig` output shows `<PI-HOLE_HOST_IP>#53`. [web:194][web:200]

---

## 10. Access Pi-hole web admin (final check)

From any LAN client using Pi-hole:

```text
http://<PI-HOLE_HOST_IP>:8080/admin
```

Log in with the password from `.env`. Confirm:

- You see DNS queries from your clients.
- Requests for `<YOUR_CLOUD_HOSTNAME>` appear in query logs when you run `dig` or open the URL. [web:74][web:199]

---

## 11. Document settings in this repo

After confirming everything works, commit the working configuration. [web:167]

1. Ensure these files are correct:

   - `pihole/compose.yaml`
   - `pihole/PIHOLE_DEPLOYMENT.md` (this guide)
   - `pihole/.gitignore` (includes `.env`)

2. Commit and push:

   ```bash
   cd ~/nextcloud-pihole-selfhosted
   git add pihole/compose.yaml pihole/PIHOLE_DEPLOYMENT.md pihole/.gitignore
   git commit -m "Document working Pi-hole DNS and <YOUR_CLOUD_HOSTNAME> setup"
   git push origin main
   ```

Next steps (in a separate Nextcloud guide) will be to start the Nextcloud container, add `<YOUR_CLOUD_HOSTNAME>` to `trusted_domains`, and configure your reverse proxy to serve that hostname. [web:184][web:185]
