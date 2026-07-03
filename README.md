# nextcloud-pihole-selfhosted

Pi-hole DNS and ad-blocking stack for my self-hosted Nextcloud home lab.

## Overview

This project defines a reproducible Pi-hole deployment on Ubuntu using Docker Compose.
It is the DNS foundation for a self-hosted Nextcloud stack and local services.

## Features

- Pi-hole deployed via Docker Compose
- Configuration via `.env` for secrets (admin/API password)
- Local DNS records for Nextcloud and internal services
- Designed to work with a locked ISP router using Pi-hole DHCP

## Tech stack

- Ubuntu Server
- Docker & Docker Compose
- Pi-hole (DNS, DHCP, ad-blocking)
- GitHub for configuration management

## Getting started

1. Clone the repository:

   ```bash
   git clone https://github.com/Deluk47/nextcloud-pihole-selfhosted.git
   cd nextcloud-pihole-selfhosted
   ```

2. Go to the Pi-hole folder and create a `.env` file from `.env.example`:

   ```bash
   cd pihole
   cp .env.example .env
   # Edit .env and set FTLCONF_webserver_api_password and TZ
   ```

3. Start Pi-hole with Docker Compose:

   ```bash
   docker compose up -d
   ```

4. Configure your router or Pi-hole DHCP to use Pi-hole as DNS.

For more detailed steps, see [pihole/PIHOLE_DEPLOYMENT.md](pihole/PIHOLE_DEPLOYMENT.md).

## Repository layout

- `nextcloud/` – Nextcloud AIO and reverse-proxy configuration.
- `pihole/` – Pi-hole Docker Compose, `.env.example`, and deployment guide.
- `ARCHITECTURE.md` – High-level architecture of the home lab stack.
- `README.md` – This overview and quick-start guide.
- `update.sh` – Update script for the Pi-hole stack.

## Role in the home lab

This Pi-hole stack:

- Provides DNS and DHCP for my LAN.
- Serves local DNS records such as `nextcloud.home.arpa` and `example.cloud`.
- Is the first layer in the home lab, ensuring that Nextcloud and other services are reachable by friendly hostnames.

## On a new machine

To deploy this stack on another host:

1. Clone the repository and enter it:

   ```bash
   cd ~
   git clone https://github.com/Deluk47/nextcloud-pihole-selfhosted.git
   cd nextcloud-pihole-selfhosted
   ```

2. Set up Pi-hole:

   ```bash
   cd pihole
   cp .env.example .env
   nano .env       # set TZ and FTLCONF_webserver_api_password
   docker compose up -d
   ```

3. Set up Nextcloud AIO:

   ```bash
   cd ../nextcloud
   cp .env.example .env
   nano .env       # set NEXTCLOUD_DOMAIN and NEXTCLOUD_HOST_IP
   docker compose up -d
   ```

4. Set up the Caddy reverse proxy:

   ```bash
   cd reverse-proxy
   cp .env.example .env
   nano .env       # set NEXTCLOUD_DOMAIN to match Nextcloud
   docker compose up -d
   ```

5. Point clients and/or your router DNS to the Pi-hole host IP, and access Nextcloud at:

   ```text
   https://<YOURCLOUD.cloud>
   ```

## Future work

- Add more detailed Nextcloud deployment docs under `nextcloud/`.
- Add infra documentation repo (`infra`) describing full home lab architecture.
- Integrate monitoring (Netdata, Uptime Kuma) and CI checks.
