# Architecture: nextcloud-pihole-selfhosted

This document describes the high-level architecture of the self-hosted cloud stack built around Pi-hole and Nextcloud.[web:44]  
It focuses on components, data flows, and stable design decisions rather than implementation details that may change frequently.[web:44]

## Goals

- Provide a reproducible home lab stack for DNS, DHCP, and personal cloud services.  
- Make Nextcloud and other services reachable via friendly, LAN-local hostnames.  
- Keep configuration in Git and host-specific secrets in `.env` files, so rebuilding on a new machine is straightforward.[web:41][web:44]

## Core components

### 1. Pi-hole (DNS/DHCP)

- Runs in Docker using the `pihole/compose.yaml` stack.  
- Acts as the primary DNS server for the LAN and can optionally provide DHCP.  
- Hosts local DNS records such as:
  - `nextcloud.home.arpa` → Nextcloud host IP  
  - `example.cloud` → reverse proxy host IP or same host  
- Uses environment variables from `pihole/.env` (for example `TZ`, `FTLCONF_webserver_api_password`).[web:48]

### 2. Nextcloud (AIO)

- Runs in Docker using the `nextcloud/` stack (Nextcloud All-in-One).  
- Provides personal cloud storage, file sync, and collaboration features.  
- Uses `nextcloud/.env` to define:
  - `NEXTCLOUD_DOMAIN` (public or LAN-local hostname)  
  - `NEXTCLOUD_HOST_IP` (LAN IP of the host running Nextcloud)  
- Relies on Pi-hole for DNS resolution of its own hostname and other services.[web:37][web:48]

### 3. Reverse proxy (for example Caddy)

- Runs in Docker using the `reverse-proxy/` stack.  
- Terminates HTTPS and routes traffic to Nextcloud and any future services.  
- Uses `reverse-proxy/.env` (for example `NEXTCLOUD_DOMAIN`) to match domains and upstreams.  
- Can be configured to obtain certificates from Let’s Encrypt or to trust an internal CA, depending on the deployment model.[web:48][web:46]

## Network and DNS layout

- LAN IP range: typically `192.168.0.0/24` (or similar), with:
  - Pi-hole host IP (for example `192.168.0.51`).  
  - Nextcloud host IP (may be the same host or a separate VM).  
- Pi-hole is the primary DNS server for clients:
  - Router DNS is set to Pi-hole host IP, or  
  - Pi-hole provides DHCP and hands out its own IP as DNS, or  
  - Clients are manually configured to use Pi-hole as DNS.[web:46]

Example local DNS records in Pi-hole:

- `nextcloud.home.arpa` → `192.168.0.51` (Nextcloud + reverse proxy host).  
- `example.cloud` → `192.168.0.51` or another service host.[web:48]

These records allow clients to reach services by stable hostnames rather than raw IPs.

## Data and request flow

A typical HTTPS request from a client to Nextcloud flows as follows:

1. Client (browser) requests `https://nextcloud.home.arpa/`.  
2. Client DNS resolver uses Pi-hole:
   - Pi-hole resolves `nextcloud.home.arpa` to the configured LAN IP (for example `192.168.0.51`).[web:48]  
3. Client connects to the reverse proxy on that IP:
   - Reverse proxy terminates TLS for `nextcloud.home.arpa`.  
   - Reverse proxy forwards the request to the Nextcloud container on its internal port (for example `11000` or an upstream defined in Docker Compose).[web:46]  
4. Nextcloud responds through the reverse proxy back to the client.[web:37]

For other services, the pattern is similar: Pi-hole resolves a hostname, the client connects to the reverse proxy or directly to a service container, and responses flow back over the same path.[web:48]

## Configuration and reproducibility

- All Docker Compose files (`pihole/compose.yaml`, `nextcloud/compose.yaml`, `reverse-proxy/compose.yaml`) are stored in Git.  
- Host-specific values and secrets live in `.env` files:
  - Committed `.env.example` files document required variables with safe example values.  
  - Real `.env` files are created per host and excluded from version control.[web:44]  
- Rebuilding the stack on a new host is done by:
  - Cloning the repo.  
  - Copying `.env.example` to `.env` in each component directory.  
  - Editing `.env` values for the new host (IPs, domains, passwords).  
  - Running `docker compose up -d` for Pi-hole, Nextcloud, and the reverse proxy in that order.[web:41]

## Invariants and design decisions

These are the stable assumptions the architecture relies on:[web:44]

- Pi-hole is the primary DNS server for the LAN.  
- Local DNS records in Pi-hole map service hostnames (for example `nextcloud.home.arpa`) to the correct LAN IPs.  
- Nextcloud and the reverse proxy are deployed via Docker Compose and use the same host or a known set of hosts.  
- Environment variables are used to keep configuration flexible and host-specific without changing Compose files for each deployment.[web:44]  
- Secrets (passwords, keys) are never stored directly in Git; they live in `.env` files on each host.[web:44]

## Future extensions

The architecture is intended to be extended with:

- Additional services fronted by the same reverse proxy and registered in Pi-hole DNS.  
- Monitoring and observability (for example Netdata, Uptime Kuma) on the same or another host.  
- CI/CD checks that validate DNS records, container health, and basic connectivity after each change or redeploy.[web:47]
