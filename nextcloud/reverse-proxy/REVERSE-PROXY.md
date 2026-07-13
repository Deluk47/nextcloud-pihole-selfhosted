# Local Reverse Proxy Configuration (Caddy Host-Mode)

This document outlines the architecture, networking decisions, and configurations used to expose the self-hosted Nextcloud All-in-One (AIO) instance securely over the local Proxmox network using **Caddy** running in **Host Network Mode**.

## Architecture & Network Flow

Because Nextcloud AIO manages its own internal ecosystem of containers via a master supervisor, standard Docker bridge networks present routing layers. The final operational traffic routing flow is established as follows:


[ Client Browser ]│ (https://<your.cloud-name>)▼[ Pi-hole Local DNS ] ──( Resolves domain to  )│▼[ Proxmox Server () ]│(Port 443)▼[ Caddy Container (network_mode: host) ]│(Decrypts TLS internal -> Proxies to 127.0.0.1:11000)▼[ Docker User-Land Proxy / iptables ]│▼[ Nextcloud AIO Apache Container (nextcloud-aio-apache) ]



---

## Technical Constraints & Findings

During deployment, several critical networking constraints were identified and resolved:

1. **Host Network Mode Limitation:** Caddy is configured with `network_mode: "host"`. While this allows it to bind cleanly to the physical machine's ports `80` and `443` without bridge interference, it breaks standard Docker internal DNS naming resolution. Caddy **cannot** resolve backends using container names like `http://nextcloud-aio-apache`. It must point to the loopback interface (`127.0.0.1`).
2. **Nextcloud AIO Apache Port Exposure:** By default, Nextcloud AIO isolates its Apache container. It must be explicitly forced to bind to the host's loopback interface using `APACHE_IP_BINDING=127.0.0.1` so the host-mode proxy can find it.
3. **Internal TLS Generation:** To run entirely locally without exposing ports to the public internet for Let's Encrypt validation, the global option `{ local_certs }` combined with `tls internal` forces Caddy to operate its own internal Certificate Authority (CA).

---

## Configuration Files

### 1. Environmental Variables (`.env`)
The core environment parameters defining the Apache interface mappings:

```env
NEXTCLOUD_DOMAIN=<your.cloud-name>
NEXTCLOUD_HOST_IP=<your-nextcloud-host-IP>

APACHE_PORT=11000
APACHE_IP_BINDING=127.0.0.1
SKIP_DOMAIN_VALIDATION=true
TALK_PORT=3479
COLLABORA_SECCOMP_DISABLED=true
```

### 2. Caddyfile Proxy Rules (`reverse-proxy/Caddyfile`)
The explicit layout mapping domain headers to backend loopback listeners:

```caddy
{
    local_certs
}

<your.cloud-name>:443 {
    tls internal

    # High-performance backend signaling (Nextcloud Talk)
    handle_path /standalone-signaling/* {
        reverse_proxy 127.0.0.1:3479 {
            flush_interval -1
        }
    }

    # Collabora Online Office Suite
    reverse_proxy /cool/* 127.0.0.1:11000

    # Main Nextcloud AIO Apache Endpoint
    reverse_proxy 127.0.0.1:11000
}
```

### 3. Docker Compose (`reverse-proxy/compose.yaml`)
Note the inclusion of persistent volume targets to maintain the internal CA security certificates between container lifecycles:

```yaml
version: "3.9"

services:
  caddy:
    image: caddy:alpine
    restart: always
    container_name: caddy
    network_mode: "host"
    ports:
      - "80:80"
      - "443:443"
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

## Operational Troubleshooting & Runbook

### Resolving Port Collisions (HTTP 502 / Bind Failures)
Nextcloud AIO spawns a transient service called `nextcloud-aio-domaincheck`. If a brute-force global restart is initiated via Docker CLI, this diagnostic tool will conflict with Apache on port `11000`, creating a binding failure loop. 

To clear port locks, force a clean stack recreation using:
```bash
# 1. Purge the diagnostic checker block
docker rm -f nextcloud-aio-domaincheck

# 2. Force rebuild the active Nextcloud containers
cd ~/nextcloud-pihole-selfhosted/nextcloud
docker compose up -d --force-recreate

# 3. Recycle the Caddy daemon
cd ~/nextcloud-pihole-selfhosted/reverse-proxy
docker compose down && docker compose up -d
```

### Accessing the Web UI
Because Caddy operates via self-signed tokens (`tls internal`), web browsers will trigger an untrusted certificate caution warning (`NET::ERR_CERT_AUTHORITY_INVALID`). 
* **Bypass:** Select **Advanced** -> **Proceed to <your.cloud-name> (unsafe)**.
* Always clear the browser cache or use an **Incognito Window** if shifting between HTTP/HTTPS blocks to avoid HSTS routing errors.




