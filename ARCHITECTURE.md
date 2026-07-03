# Home Lab DNS Architecture

## Components

- Pi-hole (this repository): core DNS/DHCP, ad-blocking
- Nextcloud stack (separate repo): application layer, served via Caddy
- Virgin Media router: WAN and Wi-Fi, DHCP disabled in favour of Pi-hole

## Flow

1. Client joins Wi-Fi on Virgin router.
2. DHCP lease is issued by Pi-hole, providing:
   - IP address
   - Pi-hole as DNS server
3. DNS queries for `nextcloud.home.arpa` and other internal names are resolved by Pi-hole.
4. Nextcloud is served via Caddy on the same host, using those hostnames.
