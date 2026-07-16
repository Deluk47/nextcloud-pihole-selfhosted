# Local Reverse Proxy Configuration (Caddy Host-Mode)

This document describes how Caddy is used as a local reverse proxy to expose a self-hosted Nextcloud All-in-One (AIO) instance over the Proxmox LAN. Caddy runs in **host network mode** and terminates TLS locally using an internal CA. [web:229][web:232]

---

## 1. Architecture and traffic flow

Nextcloud AIO manages its own internal ecosystem of containers via a master supervisor, which makes traditional bridge-network-based reverse proxy setups awkward. The final routing flow is:

```text
[ Client Browser ]
        │ (https://your-server-domain)
        ▼
[ Pi-hole Local DNS ] ──( Resolves domain to )──► [ Proxmox / Caddy Host IP ]
                                                          │
                                                (Host Firewall: UFW)
                                                          │ (Allows 80/443)
                                                          ▼
                                    [ Caddy Container (network_mode: host) ]
                                                          │
                                                (Terminates TLS locally)
                                                (Proxies to 127.0.0.1)
                                                          ▼
                                    [ Nextcloud AIO Apache Container ]
```

Key points:

- Pi-hole resolves `your-server-domain` to the Proxmox host running Caddy. [web:225]  
- Caddy binds directly to host ports 80 and 443 via host network mode. [web:238]  
- Caddy proxies HTTP requests to Nextcloud AIO’s Apache service bound on `127.0.0.1:11000`. [web:235]  

---

## 2. Technical constraints and decisions

Several important constraints shape this configuration:

- **Host network mode:**  
  `network_mode: "host"` binds Caddy directly to the host’s network stack on ports 80 and 443. Docker DNS-based service discovery is not available, so Caddy must route to explicit IPs (here, `127.0.0.1`). [web:238]

- **No `ports:` block with host mode:**  
  Defining `ports:` while using `network_mode: "host"` causes configuration conflicts and container crashes; the `ports:` section must be omitted completely. [web:238]

- **Apache IP binding:**  
  Nextcloud AIO isolates its Apache endpoint. You must pass `APACHE_IP_BINDING=127.0.0.1` into the AIO configuration so Apache listens on the host loopback, where Caddy can reach it. [web:235]

- **Internal TLS with Caddy:**  
  For a purely local deployment (no public DNS / ACME), the Caddy global option `{ local_certs }` combined with `tls internal` configures Caddy to issue certificates via its own internal CA. [web:229][web:232]

- **HTTP/3 / QUIC tuning:**  
  Caddy can serve HTTP/3 over UDP. Under high-bandwidth transfers, default Linux UDP buffers may be too small, leading to warnings and reduced throughput. Raising `net.core.rmem_max` and `net.core.wmem_max` mitigates this. [web:233]

- **Read-only Caddyfile mount:**  
  Because `Caddyfile` is mounted read-only (`:ro`), `caddy fmt --overwrite` inside the container fails. Formatting is done on the host using stdin/stdout instead.

---

## 3. Environment variables (`.env`)

Example `.env` for the reverse proxy:

```env
NEXTCLOUD_DOMAIN=your-server-domain     # e.g. cloud.home.arpa
NEXTCLOUD_HOST_IP=your-server-ip        # e.g. 192.168.0.50 (Caddy/Proxmox host)
APACHE_PORT=11000
APACHE_IP_BINDING=127.0.0.1
SKIP_DOMAIN_VALIDATION=true
TALK_PORT=3479
COLLABORA_SECCOMP_DISABLED=true
```

Notes:

- `NEXTCLOUD_DOMAIN` must match the hostname Pi-hole resolves to the Caddy host. [web:225]  
- `APACHE_IP_BINDING=127.0.0.1` is applied on the Nextcloud AIO side so that Apache listens on loopback. [web:235]  

---

## 4. Caddy configuration (`Caddyfile`)

Minimal Caddyfile for this setup:

```caddy
{
	local_certs
}

your-server-domain {
	tls internal

	# Nextcloud Talk standalone signaling
	handle_path /standalone-signaling/* {
		reverse_proxy 127.0.0.1:3479 {
			flush_interval -1
		}
	}

	# Collabora Online office suite
	handle /cool/* {
		reverse_proxy 127.0.0.1:9980
	}

	# Main Nextcloud AIO Apache endpoint (catch-all)
	handle {
		reverse_proxy 127.0.0.1:11000
	}
}
```

Replace `your-server-domain` with the same value you use for `NEXTCLOUD_DOMAIN` and in Pi-hole’s local DNS record. [web:229][web:232]

---

## 5. Container stack (`compose.yaml`)

Caddy runs in host network mode and uses named volumes for configuration and certificate storage:

```yaml
version: "3.9"

services:
  caddy:
    image: caddy:alpine
    restart: always
    container_name: caddy
    network_mode: "host"
    env_file:
      - .env
    volumes:
      - caddy_certs:/certs
      - caddy_config:/config
      - caddy_data:/data
      - caddy_sites:/srv
      - ./Caddyfile:/etc/caddy/Caddyfile:ro

volumes:
  caddy_certs:
  caddy_config:
  caddy_data:
  caddy_sites:
```

Caddy’s internal CA root certificate is stored under its data directory; trusting this root on client devices can remove browser warnings, if desired. [web:232]

---

## 6. Deployment runbook

### 6.1 Tune host UDP buffers (optional but recommended)

On the Caddy host, increase UDP buffer sizes:

```bash
# Apply immediately
sudo sysctl -w net.core.rmem_max=7500000
sudo sysctl -w net.core.wmem_max=7500000

# Persist across reboots
sudo tee -a /etc/sysctl.conf << 'EOF'
net.core.rmem_max=7500000
net.core.wmem_max=7500000
EOF
```

### 6.2 Open firewall ports

Ensure the host firewall allows HTTP and HTTPS:

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload

sudo ss -tulpn | grep -E '(:80|:443)'
```

### 6.3 Format and validate `Caddyfile`

From the reverse proxy directory:

```bash
cd ~/nextcloud-pihole-selfhosted/nextcloud/reverse-proxy
caddy fmt - < Caddyfile > Caddyfile.tmp && mv Caddyfile.tmp Caddyfile
```

---

### 6.4 Start Caddy

```bash
cd ~/nextcloud-pihole-selfhosted/nextcloud/reverse-proxy

# Start in background
sudo docker compose up -d

# Check logs
sudo docker logs caddy

# Validate config inside the container
sudo docker exec -it caddy caddy validate --config /etc/caddy/Caddyfile
```

If validation fails, fix the Caddyfile and re-run `caddy validate` before reloading. [web:236]

---

## 7. Runtime operations and troubleshooting

### 7.1 Hot-reload configuration

After editing `Caddyfile` on the host:

```bash
sudo docker exec -it caddy caddy reload --config /etc/caddy/Caddyfile
```

This reloads configuration without dropping active connections. [web:236]

---

### 7.2 Resolving port 11000 conflicts (HTTP 502)

Nextcloud AIO may start a temporary container called `nextcloud-aio-domaincheck` that also tries to use port `11000`, causing binding failures for Apache and resulting in 502 errors via Caddy. A typical recovery sequence:

```bash
# 1. Remove the transient diagnostic container
docker rm -f nextcloud-aio-domaincheck

# 2. Recreate core Nextcloud containers
cd ~/nextcloud-pihole-selfhosted/nextcloud
docker compose up -d --force-recreate

# 3. Restart the reverse proxy
cd ~/nextcloud-pihole-selfhosted/nextcloud/reverse-proxy
docker compose down
docker compose up -d
```

---

### 7.3 Resetting Nextcloud admin password

If you cannot log in to Nextcloud with the admin account:

```bash
docker exec --user www-data -it nextcloud-aio-nextcloud php occ user:resetpassword admin
```

Follow the prompts to set a new password, then log in through the Caddy HTTPS endpoint. [web:238]

---

### 7.4 Browser certificate warnings

Because this setup uses `tls internal` and `{ local_certs }`, browsers will initially treat the certificate as untrusted. [web:229][web:232]

Options:

- **Quick bypass (testing):**  
  Use the browser’s “Advanced → Proceed to site” option on `https://your-server-domain`.  

- **Cleaner approach:**  
  - Export the Caddy local CA root certificate from the Caddy data directory (inside the container or mapped volume). [web:232]  
  - Import it into the trust store of your client devices so that `your-server-domain` is trusted.  

When changing proxy configuration, testing in an incognito/private window avoids issues with cached HSTS or old certificate chains.
