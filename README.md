# nextcloud-pihole-selfhosted

Self-hosted Pi-hole DNS and Nextcloud stack for a home lab on Ubuntu, orchestrated with Docker Compose.[web:46]

## Overview

This repository defines a reproducible, self-contained cloud environment built around Pi-hole for DNS/DHCP and Nextcloud for personal cloud storage and collaboration.[web:41]  
Pi-hole is the DNS foundation of the stack: it serves local DNS records and ad-blocking for your LAN, while Nextcloud and a reverse proxy (such as Caddy) run alongside it on the same host or a dedicated node.[web:46][web:48]

### Key features

- Pi-hole deployed via Docker Compose as the primary LAN DNS and optional DHCP.[web:46]  
- Configuration via `.env` files for all secrets and host-specific values (Pi-hole admin/API password, Nextcloud domain, host IPs).[web:44]  
- Local DNS records for Nextcloud and internal services (for example `nextcloud.home.arpa`, `example.cloud`).[web:48]  
- Designed to work even when the ISP router is “locked” by using Pi-hole DHCP and per-client DNS overrides.[web:46]  
- GitHub-tracked configuration and docs so the stack can be rebuilt consistently on new hosts.[web:41][web:44]

## Architecture

The project is split into focused components:[web:44]

- `pihole/` – Pi-hole Docker Compose stack, `.env.example`, and deployment guide.  
- `nextcloud/` – Nextcloud AIO and related configuration (domain, host IP, volumes).  
- `reverse-proxy/` – Reverse proxy (for example Caddy) that fronts Nextcloud and other services.  
- `ARCHITECTURE.md` – High-level description of how Pi-hole, Nextcloud, and the reverse proxy fit together in the home lab.  
- `update.sh` – Helper script for updating the Pi-hole stack on an existing host.  

Pi-hole is typically deployed first; once DNS is in place, Nextcloud and the reverse proxy use Pi-hole for name resolution and serve friendly hostnames to clients.[web:48]

## Prerequisites

On the target host (Ubuntu Server recommended):[web:46]

- A user with `sudo` access.  
- Docker Engine and Docker Compose installed from the official Docker packages.  
- Basic familiarity with editing `.env` files and using `docker compose` on the CLI.  
- A LAN where you can either:
  - Set DNS to the Pi-hole host IP on the router, or  
  - Use Pi-hole’s DHCP server and/or per-device DNS overrides.[web:46]

## Quick start: Pi-hole only

These steps bring up Pi-hole as DNS/DHCP and give you a working foundation for the rest of the stack.[web:46]

1. Clone the repository and enter it:

   ```bash
   git clone https://github.com/Deluk47/nextcloud-pihole-selfhosted.git
   cd nextcloud-pihole-selfhosted
   ```

2. Prepare the Pi-hole environment:

   ```bash
   cd pihole
   cp .env.example .env
   nano .env   # set TZ and FTLCONF_webserver_api_password
   ```

   - `TZ` should match your timezone (for example `Europe/London`).  
   - `FTLCONF_webserver_api_password` becomes your Pi-hole web UI password.[web:48]

3. Start Pi-hole with Docker Compose:

   ```bash
   docker compose up -d
   ```

4. Point clients to Pi-hole for DNS:

   - Set the Pi-hole host IP as DNS on your router (if possible), or  
   - Enable Pi-hole DHCP and point clients at Pi-hole for DNS, or  
   - Manually configure DNS per client (IPv4 settings → DNS server = Pi-hole host IP).[web:46][web:48]

5. Log into the Pi-hole web UI and add local DNS records for your services (for example `nextcloud.home.arpa`, `example.cloud`).[web:48]

For more detailed deployment notes and troubleshooting steps, see [`pihole/PIHOLE_DEPLOYMENT.md`](https://github.com/Deluk47/nextcloud-pihole-selfhosted/blob/main/pihole/PIHOLE_DEPLOYMENT.md).[web:41]

## Full stack on a new host

To build the full Pi-hole + Nextcloud + reverse proxy stack on a new machine, use this sequence.[web:41][web:44]

1. Clone the repository:

   ```bash
   cd ~
   git clone https://github.com/Deluk47/nextcloud-pihole-selfhosted.git
   cd nextcloud-pihole-selfhosted
   ```

2. Set up Pi-hole (DNS/DHCP foundation):

   ```bash
   cd pihole
   cp .env.example .env
   nano .env   # set TZ and FTLCONF_webserver_api_password
   docker compose up -d
   ```

3. Set up Nextcloud AIO:

   ```bash
   cd ../nextcloud
   cp .env.example .env
   nano .env   # set NEXTCLOUD_DOMAIN and NEXTCLOUD_HOST_IP
   docker compose up -d
   ```

   - `NEXTCLOUD_DOMAIN` must match the hostname you plan to use (for example `nextcloud.home.arpa` or `YOURCLOUD.cloud`).[web:37]  
   - `NEXTCLOUD_HOST_IP` is the LAN IP of the host running Nextcloud.[web:48]

4. Set up the reverse proxy (for example Caddy):

   ```bash
   cd ../reverse-proxy
   cp .env.example .env
   nano .env   # set NEXTCLOUD_DOMAIN to match Nextcloud
   docker compose up -d
   ```

5. Wire DNS to the cloud host:

   - Ensure Pi-hole has a local DNS record that maps `NEXTCLOUD_DOMAIN` to `NEXTCLOUD_HOST_IP`.  
   - Point clients or the router DNS to the Pi-hole host IP.[web:48]

6. Access Nextcloud:

   ```text
   https://<YOURCLOUD.cloud>
   ```

   Replace `YOURCLOUD.cloud` with the actual domain you set in `NEXTCLOUD_DOMAIN` and in Pi-hole’s local DNS.[web:37]

## Repository layout

| Path              | Description                                                                 |
|-------------------|-----------------------------------------------------------------------------|
| `pihole/`         | Pi-hole Docker Compose stack, `.env.example`, and Pi-hole deployment guide. |
| `nextcloud/`      | Nextcloud AIO configuration and supporting files.                           |
| `reverse-proxy/`  | Reverse proxy configuration (Caddy, etc.) for HTTPS and routing.           |
| `ARCHITECTURE.md` | High-level architecture and design notes for the home lab.                 |
| `README.md`       | Overview and quick-start guide (this file).                                |
| `update.sh`       | Script to update the Pi-hole stack on an existing host.                    |

## Role in the home lab

Within the wider home lab, this stack:[web:46]

- Provides consistent DNS and DHCP for the LAN.  
- Serves local DNS records such as `nextcloud.home.arpa` and `example.cloud`.  
- Acts as the first layer that ensures all other services are reachable by stable, human-friendly hostnames.  
- Can be replicated on a new host with minimal manual configuration by reusing `.env` files and Compose definitions.[web:41][web:44]

## Environment files and configuration

To keep secrets and host-specific details out of version control, each component uses `.env` files:[web:44]

- `pihole/.env` – Contains `TZ` and `FTLCONF_webserver_api_password` (and any other Pi-hole envs).  
- `nextcloud/.env` – Contains `NEXTCLOUD_DOMAIN`, `NEXTCLOUD_HOST_IP`, and Nextcloud-specific settings.  
- `reverse-proxy/.env` – Contains `NEXTCLOUD_DOMAIN` and proxy-specific variables.

A matching `.env.example` is committed for each component with safe example values only. Copy `.env.example` to `.env` and edit locally before running `docker compose up -d`.[web:44]

## Maintenance

- Use `update.sh` in the repo root to update Pi-hole on an existing host.  
- Periodically review `ARCHITECTURE.md` and this README when you change ports, domains, or add new services.[web:44]  
- Keep `.env.example` in sync with actual variables so a new host can be configured with minimal surprises.[web:41]

## Future work

Planned improvements include:[web:41]

- More detailed Nextcloud deployment docs under `nextcloud/` (storage layout, backups, SSL/TLS notes).  
- A dedicated infra documentation repo (`infra/`) describing the full home lab topology (hosts, networks, VPNs).[web:43]  
- Integrated monitoring (for example Netdata, Uptime Kuma) and CI checks that validate DNS records, container health, and basic Nextcloud connectivity on each deploy.[web:47]
