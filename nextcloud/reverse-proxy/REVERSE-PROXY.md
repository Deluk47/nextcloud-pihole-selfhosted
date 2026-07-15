# Local Reverse Proxy Configuration (Caddy Host-Mode)

This document outlines the architecture, networking decisions, and configurations used to expose the self-hosted Nextcloud All-in-One (AIO) instance securely over the local Proxmox network using **Caddy** running in **Host Network Mode**.

## Architecture & Network Flow

Because Nextcloud AIO manages its own internal ecosystem of containers via a master supervisor, standard Docker bridge networks present routing layers. The final operational traffic routing flow is established as follows:

```text
[ Client Browser ]
        │ (https://yourcloud.home.arpa)
        ▼
[ Pi-hole Local DNS ] ──( Resolves domain to )──► [ Proxmox Server IP ]
                                                                 │
                                                       (Host Firewall: UFW)
                                                                 │ (Passes Ports 80/443)
                                                                 ▼
                                              [ Caddy Container (network_mode: host) ]
                                                                 │
                                                       (Decrypts TLS internal)
                                                       (Proxies via 127.0.0.1)
                                                                 ▼
                                              [ Nextcloud AIO Apache Container ]
```

---

## Technical Architecture & Constraints

During deployment, several critical networking constraints were identified and resolved:

* **Host Network Mode Limitation:** Caddy uses `network_mode: "host"`. This binds it directly to host ports `80` and `443` without bridge network layers. Because this disables internal Docker DNS resolution, Caddy **cannot** resolve backends via container names; it must route to the loopback interface (`127.0.0.1`).
* **Docker Compose Constraint:** Declaring a `ports:` block while using `network_mode: "host"` creates a configuration conflict causing continuous container crashes. The `ports:` block must be entirely omitted.
* **Apache Isolation:** Nextcloud AIO isolates its Apache web endpoint by default. You must pass `APACHE_IP_BINDING=127.0.0.1` to force it to bind to the host loopback interface where Caddy can locate it.
* **Internal TLS:** To maintain local operations without opening public internet ports for Let's Encrypt validation, the global option `{ local_certs }` combined with `tls internal` forces Caddy to issue its own self-signed certificates.
* **QUIC Tuning (HTTP/3):** Caddy utilizes QUIC over UDP. Standard Linux kernel receive/send buffers (208 KiB) cause packet drops under high-bandwidth transfers. The host parameters must be tuned to 7.5 MB (`net.core.rmem_max=7500000`) to prevent warnings.
* **Read-Only Volume Mismatch:** Because the `Caddyfile` is mounted as a read-only volume (`:ro`), the standard container hot-formatting command (`caddy fmt --overwrite`) fails. Formatting operations must be offloaded on the host layer using standard input (`stdin`) data piping.

---

## Configuration Blueprints

### 1. Environmental Variables (`.env`)
```env
NEXTCLOUD_DOMAIN=your-server-domain
NEXTCLOUD_HOST_IP=your-server-ip
APACHE_PORT=11000
APACHE_IP_BINDING=127.0.0.1
SKIP_DOMAIN_VALIDATION=true
TALK_PORT=3479
COLLABORA_SECCOMP_DISABLED=true
```

### 2. Reverse Proxy Map (`Caddyfile`)
```caddy
{
	local_certs
}

your-server-domain {
	tls internal

	# High-performance backend signaling (Nextcloud Talk)
	handle_path /standalone-signaling/* {
		reverse_proxy 127.0.0.1:3479 {
			flush_interval -1
		}
	}

	# Collabora Online Office Suite
	handle /cool/* {
		reverse_proxy 127.0.0.1:9980
	}

	# Main Nextcloud AIO Apache Endpoint (Catch-all)
	handle {
		reverse_proxy 127.0.0.1:11000
	}
}
```
---

### 3. Container Orchestration Stack (`compose.yaml`)
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

---

## Chronological Deployment Runbook

### Stage 1: Optimize Host Kernel Network Buffers
Run these commands on your host server terminal to lift system UDP performance ceilings:
```bash
# Apply changes immediately to the live host
sudo sysctl -w net.core.rmem_max=7500000
sudo sysctl -w net.core.wmem_max=7500000

# Persist settings across system reboots
sudo tee -a /etc/sysctl.conf << 'EOF'
net.core.rmem_max=7500000
net.core.wmem_max=7500000
EOF
```

### Stage 2: Configure the Host OS Firewall
Open standard ingress web listeners to ensure the proxy is reachable:
```bash
# Permit inbound connections over web interfaces via UFW
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload

# Confirm host network interfaces are listening actively on destination sockets
sudo ss -tulpn | grep -E '(:80|:443)'
```

### Stage 3: Sanitize Configuration Layout
Navigate to your proxy configuration workspace directory and fix any text alignment inconsistencies safely via standard input streaming:
```bash
cd ~/nextcloud-pihole-selfhosted/nextcloud/reverse-proxy
caddy fmt - < Caddyfile > Caddyfile.tmp && mv Caddyfile.tmp Caddyfile
```

### Stage 4: Initialize the Caddy Proxy Service
Deploy the stack and confirm the engine state:
```bash
# Fire up the stack in a detached background state
sudo docker compose up -d

# Verify initialization and check for errors
sudo docker logs caddy

# Validate the config layout parsing internally
sudo docker exec -it caddy caddy validate --config /etc/caddy/Caddyfile
```

---

## Operational Troubleshooting Runbook

### Live Hot-Reloading Configuration Updates
If you alter your proxy rules in the `Caddyfile` later, apply changes immediately without dropping active sessions:
```bash
sudo docker exec -it caddy caddy reload --config /etc/caddy/Caddyfile
```

### Resolving Port 11000 Collisions (HTTP 502 Loops)
Nextcloud AIO spawns a temporary service called `nextcloud-aio-domaincheck`. If a global restart is forced, this tool conflicts with Apache on port `11000`, putting the stack in a binding failure loop. Use this sequence to clean up the network paths:
```bash
# 1. Force purge the transient diagnostic container
docker rm -f nextcloud-aio-domaincheck

# 2. Force recreate the core application containers
cd ~/nextcloud-pihole-selfhosted/nextcloud
docker compose up -d --force-recreate

# 3. Recycle the reverse proxy deployment
cd ~/nextcloud-pihole-selfhosted/reverse-proxy
docker compose down && docker compose up -d
```

### Resetting Forgotten Nextcloud Administrative Credentials
If you encounter a "Wrong login or password" error on your admin account, force a credential baseline shift via the command-line interface:
```bash
docker exec --user www-data -it nextcloud-aio-nextcloud php occ user:resetpassword admin
```

### Web Browser Security Warnings
Because Caddy operates via self-signed tokens (`tls internal`), web browsers will present an untrusted certificate error (`NET::ERR_CERT_AUTHORITY_INVALID`). 
* **Bypass:** Select **Advanced** -> **Proceed to your-server-domain (unsafe)**.
* **Cache Management:** Use an **Incognito / Private Window** when shifting proxy configurations to prevent browser-enforced HSTS routing loops from masking connectivity problems.

