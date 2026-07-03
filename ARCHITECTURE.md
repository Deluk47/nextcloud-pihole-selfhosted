# Home Lab DNS Architecture

## Components

- Pi-hole (this repository): core DNS, DHCP, and ad-blocking.
- Nextcloud stack (separate repository): application layer, served via Caddy.
- ISP router: WAN and Wi‑Fi entry point, DHCP disabled in favour of Pi-hole.
- Client devices: laptops, desktops, phones, tablets on the home network.

## Flow

1. A client device joins the home Wi‑Fi provided by the ISP router.
2. DHCP leases are issued by Pi-hole, providing:
   - IP address.
   - Pi-hole as the DNS server.
3. DNS queries for `nextcloud.home.arpa`, `dunirvgou.cloud`, and other internal names are resolved by Pi-hole.
4. Nextcloud is served via Caddy on the same Ubuntu host, using those hostnames.
5. External DNS queries (e.g. public websites) are forwarded from Pi-hole to upstream resolvers (such as 1.1.1.1), keeping ad-blocking in place.

## Diagram

```text
                ┌────────────────────────────┐
                │      Internet / WAN        │
                └────────────┬───────────────┘
                             │
                             │
                    ┌────────▼────────┐
                    │ ISP Router      │
                    │ (Wi‑Fi + WAN)   │
                    └────────┬────────┘
                             │
                DHCP OFF  ┌──┴───────────────┐
                          │                  │
                          │   LAN / Wi‑Fi    │
                          │                  │
                          └──┬───────────────┘
                             │
                ┌────────────▼────────────┐
                │        Pi‑hole         │
                │ (DNS + DHCP + Ads)     │
                │ Docker on Ubuntu host  │
                └────────┬───────────────┘
                         │
          DNS: nextcloud.home.arpa, dunirvgou.cloud, etc.
                         │
                ┌────────▼────────────┐
                │   Caddy + Nextcloud │
                │   (same Ubuntu host)│
                │   Reverse proxy      │
                └────────┬────────────┘
                         │
                ┌────────▼────────────┐
                │   Client Devices    │
                │ (laptops, phones,   │
                │  tablets, etc.)     │
                └─────────────────────┘
```
