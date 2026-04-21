# Networking — the one area where homelab pain concentrates

More homelab problems are networking problems than anything else. This
reference covers the patterns that prevent 80% of them.

## Subnet and VLAN layout (suggested baseline)

Even on a flat /24 home network, separate concerns logically; upgrade to
VLANs when your switch supports them:

| Purpose | Example CIDR | VLAN ID |
|---|---|---|
| Trusted LAN (desktops, laptops) | 192.168.10.0/24 | 10 |
| Servers / infra (Proxmox, NAS, admin UIs) | 192.168.20.0/24 | 20 |
| IoT / untrusted (smart plugs, random cameras) | 192.168.30.0/24 | 30 |
| Guest / WiFi for strangers | 192.168.40.0/24 | 40 |
| MetalLB LB pool / cluster services | 192.168.50.0/24 | 50 |

Firewall rules then:

- IoT → can reach internet, cannot reach LAN/servers (except maybe NTP, DNS).
- Guest → internet only.
- LAN → servers (admin UI) yes, MetalLB yes.
- Servers → LAN only via allow-list (usually not needed).

Without VLANs, put these concerns at least in separate IP ranges and police via host firewalls. Better than nothing.

## DNS — the single most useful homelab service

Pihole/AdGuard + Unbound is the standard combo:

- **Pihole/AdGuard** — DNS resolver for the LAN with ad/tracker blocking. Also the right place to define local names (`jellyfin.lab.mydomain.com → 192.168.50.10`).
- **Unbound** — recursive resolver; Pihole forwards to it. You skip forwarding everything to 1.1.1.1 / 8.8.8.8.

DHCP: give clients Pihole as their DNS server (either via DHCP option or point DHCP at Pihole if you want it to manage leases).

### Local DNS for local services

Two common patterns:

1. **Subdomain of a real domain** — `*.lab.yourdomain.com` all resolve on the LAN only. The real domain lives at your registrar; you never publish these records externally. Benefit: you can get real TLS certs via DNS-01 ACME challenge (Let's Encrypt) without exposing anything.
2. **Made-up TLD** — `*.home.arpa` (RFC-reserved for this) or `*.lab`. Works fine, but you can't get a real TLS cert — use your own CA instead (mkcert, smallstep-ca).

Recommendation: buy a cheap domain, use pattern 1. $12/year saves hours.

### Split-horizon DNS

If some services are reachable both internally and externally, Pihole/AdGuard can answer internally with an internal IP while external DNS returns an external IP (or no record). Set this up once; you never think about it again.

## Reverse proxy

One process in front of everything handles TLS, routing, HTTP→HTTPS redirect, and auth. Options:

- **Traefik** — label-driven (Docker), CRD-driven (k8s). Auto-discovers targets. Killer app for Docker Compose homelabs. TLS via Let's Encrypt out of the box.
- **Nginx Proxy Manager (NPM)** — Nginx + a web UI. Pick this if you don't want to write config.
- **Caddy** — Automatic HTTPS by default. Simple Caddyfile syntax. Underappreciated.
- **Nginx / Apache** — manual config. Only if you already know and prefer them.

**Rule**: put ONE reverse proxy in front; don't layer multiple. Every hop is a source of header mangling, timeout mismatches, and broken `X-Forwarded-*`.

### TLS certs

- **Public service** (exposed to internet): Let's Encrypt via HTTP-01 (needs port 80 reachable) or DNS-01 (needs DNS provider API credentials).
- **Internal-only service**: Let's Encrypt via DNS-01 on your real domain (works without exposing anything), OR your own CA (mkcert for quick, smallstep-ca for a proper internal CA).
- **Don't** use self-signed certs with browsers warning every time; it trains you to ignore warnings.

### Real-IP propagation

Under a reverse proxy, the backend sees the proxy IP, not the client IP, unless you:

1. Configure the proxy to set `X-Forwarded-For` / `X-Real-IP` / `X-Forwarded-Proto`.
2. Configure the backend to trust those headers from the proxy's IP.

If backend logs show `127.0.0.1` or the proxy IP for every client, that's the miss. Fix both ends, not just the proxy.

## MetalLB

The piece that gives Kubernetes Services of type `LoadBalancer` real IPs on-prem. Two modes:

### L2 (ARP) mode — simpler

- Pool of IPs from your LAN subnet, outside DHCP range.
- MetalLB ARP-announces them; one node is "active" per IP.
- Works on any switch (no special config required).
- Failover on node loss (~10-20 seconds typically).

Config:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lan-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.50.200-192.168.50.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lan-l2
  namespace: metallb-system
spec:
  ipAddressPools: [lan-pool]
```

### BGP mode — fancier

- Your router must speak BGP (many do not).
- MetalLB peers with the router; ECMP gives real HA + load-balancing.
- Overkill for homelab unless you've got the gear.

### Common MetalLB pitfalls

- **IP pool overlaps with DHCP range** → collisions.
- **IP pool outside LAN subnet** → arp announcements go to the void.
- **MetalLB L2 behind another L2 LB/switch that's filtering ARP** → intermittent or silent failure.

## Remote access

### The golden path: Tailscale

- Every node + your devices join a Tailscale tailnet.
- You reach the cluster, the admin UIs, your NAS, everything via tailnet IPs as if they were local.
- No port-forwarding to the LAN.
- MagicDNS gives you names like `proxmox.tail123.ts.net`.

This is the single biggest homelab security upgrade after "use a reverse proxy."

### Headscale (self-hosted control plane)

If you object to the Tailscale company holding the coordination keys, run Headscale on a VPS. Same experience, self-hosted control plane. More operational burden.

### WireGuard (DIY)

Point-to-point VPN. Manageable for 2-3 devices; painful at scale. The thing Tailscale/Headscale automates for you.

### Exposing public services

For services that need to be reachable from the public internet (not just you):

- **Cloudflare Tunnel (`cloudflared`)** — no port-forward; Cloudflare terminates TLS; built-in DDoS protection. Free tier is generous. Recommended for public homelab services.
- **Reverse proxy + port forward** — classic; you own everything; responsibility matches.
- **Tailscale Funnel** — limited (HTTPS only, certain ports) but zero-config.

Whatever you pick: **enable auth on everything**. Authelia, Authentik, Keycloak, Vouch, or service-native auth. "Just behind a proxy" is not security.

## Firewall discipline

Even in a homelab:

- Default deny on inter-VLAN traffic; allow specific flows.
- Log drops; occasionally scan the log to see what's trying to connect.
- Block common egress abuse (outbound SMTP, etc.) if you run any untrusted workloads.

pfSense / OPNsense / OpenWrt / UniFi — any of them supports this. The router that came with your ISP probably does not.

## Common networking footguns

- **Double NAT** — ISP router + your router both NATing. Breaks UPnP, some VPN setups. Put the ISP router in bridge mode if possible.
- **MTU mismatches** — WireGuard tunnels + Jumbo frames somewhere + VXLAN + … path MTU problems appear as "some things work, some things hang." Start with MTU 1420 on WireGuard and work from there.
- **DNS glue failures** — Pihole died; nothing resolves; including Proxmox's own stuff. Always have a fallback (router's own DNS, or manual entries in `/etc/hosts` on critical boxes).
- **IPv6 half-on** — enable it fully (with firewalling) or disable it. Half-on means clients prefer IPv6 paths that your firewall doesn't cover.
- **Switch ports not trunked for VLANs** you're using — Proxmox sees tagged frames as untagged, VM can't reach anything.
