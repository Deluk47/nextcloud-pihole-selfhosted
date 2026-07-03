# nextcloud-pihole-selfhosted

Pi-hole DNS and ad-blocking stack for my self-hosted Nextcloud home lab.

## Overview

This project defines a reproducible Pi-hole deployment on Ubuntu using Docker Compose.
It is the DNS foundation for a self-hosted Nextcloud stack and local services.

## Features

- Pi-hole deployed via Docker Compose
- Configuration via `.env` for secrets (admin/API password)
- Local DNS records for Nextcloud and internal services
- Designed to work with a locked ISP router (Virgin Media) using Pi-hole DHCP

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

2. Create a `.env` file from `.env.example`:

   ```bash
   cp .env.example .env
   # Edit .env and set FTLCONF_webserver_api_password and TZ
   ```

3. Start Pi-hole with Docker Compose:

   ```bash
   docker compose up -d
   ```

4. Configure your router or Pi-hole DHCP to use Pi-hole as DNS.

## Repository layout

- `compose.yaml` – Docker Compose for Pi-hole.
- `.env.example` – Example environment variables (no secrets).
- `.gitignore` – Ignores `.env` and other local files.

## Role in the home lab

This Pi-hole stack:

- Provides DNS and DHCP for my LAN.
- Serves local DNS records such as `nextcloud.home.arpa` and `dunirvgou.cloud`.
- Is the first layer in the home lab, ensuring that Nextcloud and other services are reachable by friendly hostnames.

## Future work

- Add Nextcloud stack in a separate repository (`nextcloud-stack`).
- Add infra documentation repo (`infra`) describing full home lab architecture.
- Integrate monitoring (Netdata, Uptime Kuma) and CI checks.

