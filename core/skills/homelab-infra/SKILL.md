---
source: core
name: homelab-infra
description: Self-hosted infra — Proxmox host provisioning, Talos/k3s/k8s bring-up, networking (VLANs, reverse proxy, DNS), storage (ZFS, NFS, Ceph), and backup strategies. Use when the user is planning a homelab, debugging a cluster that won't come up, or deciding where a new service should live.
triggers: proxmox, proxmox ve, pve, lxc, qemu, kvm, talos, talos linux, k3s, k8s, kubernetes bring-up, metallb, traefik, nginx-proxy-manager, pihole, unbound, adguard, zfs, nfs, ceph, longhorn, cloudflared, tailscale, headscale, wireguard, pfsense, opnsense, unifi, homelab, selfhost, self-host
---

# homelab-infra

Domain hub for running infrastructure in a home or small-shop
environment. Different from cloud ops: hardware is cheap, time is
expensive, blast radius is mostly yourself, and "good enough" beats
"enterprise-correct".

Three failure modes this hub tries to prevent:

1. **Building a fragile snowflake** — one-off clicks in the Proxmox UI,
   undocumented `/etc/hosts` edits, "I think the DNS is on the router?"
   When anything breaks you're reverse-engineering your own stack at 2am.
2. **Over-engineering a 3-node cluster to Google scale** — Ceph + full
   Kubernetes + Prometheus + Grafana for a Jellyfin instance. The
   complexity tax eats the time you meant to spend using the services.
3. **No backup story until the day you need one** — ZFS is not a backup.
   RAID is not a backup. One copy of data is not a backup. The 3-2-1
   rule applies to homelabs too; most homelabs don't meet it.

## When to use this skill

- "Should I run this in an LXC, a VM, a container on the host, or k8s?"
- "How do I expose this service to the internet safely?"
- "Proxmox / Talos / k3s won't come up — what's next?"
- "Should I use ZFS or ext4 for my data pool?"
- "What's a reasonable backup strategy for a homelab?"
- "Why does my MetalLB IP not work from outside the cluster?"

## Default architecture — the 80% stack

Unless the user has specific reasons otherwise, this is the starting
point:

```
┌──────────────────────────────────────────────────────────────────┐
│  Proxmox VE host(s)                                              │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │ VMs for anything needing isolation / a full OS:          │    │
│  │   - Talos / k3s control plane + workers                  │    │
│  │   - Opnsense/pfSense (if you're routing through PVE)    │    │
│  │   - NixOS / Ubuntu for hand-managed services             │    │
│  ├──────────────────────────────────────────────────────────┤    │
│  │ LXC for lightweight, share-the-kernel services:          │    │
│  │   - Pihole/AdGuard + Unbound                             │    │
│  │   - Nginx-Proxy-Manager / Traefik edge                   │    │
│  │   - Home Assistant (or VM if you need USB passthrough)   │    │
│  ├──────────────────────────────────────────────────────────┤    │
│  │ Storage: ZFS pool on host, exported via NFS/SMB          │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
          │
          │  Tailscale / WireGuard for remote access
          │  (NOT port-forwarding randomly into LAN)
          │
   [ external access ]
```

This beats "everything in Kubernetes" for maintainability in a 1-3 node
homelab. Kubernetes is the right answer when you have a cluster-shaped
workload, not because it's the cool thing.

## Decision points

### LXC vs VM vs container-on-host vs k8s

| Layer | When it's right |
|---|---|
| **LXC** | Stateless Linux service that plays nicely (Pihole, proxies, metric stacks). Shares host kernel → fast, thrifty. Lossy for kernel modules / init systems. |
| **VM (qemu/kvm)** | Anything needing a different kernel (BSD, Windows, Talos), full isolation, device passthrough (GPU/USB), or long-term stability. |
| **Container on host (Docker Compose)** | A single-node deployment where you want the containerized-software ecosystem without an orchestrator. Perfectly fine for 80% of homelab services. |
| **Kubernetes (k3s/k8s/Talos)** | You have ≥2 nodes, want self-healing, or want to rehearse prod patterns at home. Not because it's "better" — because the workload benefits. |

**Anti-pattern**: running a single-node k8s cluster on one Proxmox VM to host three services. You've added 4 layers (PVE → VM → kubelet → container) and gained nothing over Docker Compose.

### Talos vs k3s vs vanilla k8s

- **Talos Linux** — minimal, immutable, API-driven, no SSH. Best bring-up for bare metal or VMs. Learning curve on day 1, then easier forever. Great match for Proxmox VMs.
- **k3s** — single-binary k8s, opinionated defaults, trivial to install. Best for "I want a k8s cluster now with minimal fuss."
- **Vanilla k8s (kubeadm)** — production-grade, more moving parts. Not usually the right homelab answer.

For a new homelab cluster: **Talos on Proxmox VMs** is the current sweet spot if you're willing to learn `talosctl`. **k3s** if you want shell-familiarity.

### Single-node vs multi-node

- Single node: Docker Compose > Kubernetes. Fewer moving parts.
- Two nodes: if you need HA, you need 3 (for etcd quorum). Two nodes is a worst-case — neither "single simple" nor "HA".
- Three nodes: real HA becomes possible. Talos/k3s shines.

If you have two nodes: either run one as a hot standby (manually fail over), or add a third (even a small one) before building HA.

## Reference guide

| Topic | Reference |
|---|---|
| Proxmox + Talos/k3s/k8s bring-up workflow | `references/bring-up-patterns.md` |
| Networking: VLANs, reverse proxy, DNS, remote access | `references/networking.md` |
| Storage (ZFS/NFS/Ceph/Longhorn) + backup strategy (3-2-1) | `references/storage-and-backup.md` |

## Common pitfalls (fast triage)

| Symptom | First suspect |
|---|---|
| LXC can't run Docker inside | `nesting=1, keyctl=1` features not enabled on the LXC |
| MetalLB IP pings locally but not from LAN | L2 vs BGP mode mismatch; MetalLB in L2 mode needs the IP to be on-link for the host network |
| Talos node stuck "not ready" | CNI not applied yet, or secrets/config mismatch between control plane and worker |
| Pod stuck `ContainerCreating` | Usually CNI or storage CSI. `kubectl describe pod` then follow the events. |
| Reverse proxy gets client IP as 127.0.0.1 | Missing real-IP / `X-Forwarded-For` propagation; upstream needs `PROXY protocol` or trust-chain headers |
| Services work inside cluster, not from LAN | Not exposed via Ingress/LoadBalancer — ClusterIP-only. Or firewall. |
| ZFS pool degraded | Disk failing. Replace. Don't wait. |
| Proxmox cluster loses quorum with 2 nodes | Two-node clusters need a qdevice or manual override — expected behavior. |

## Security defaults for homelab

- **Do not port-forward** services from the internet directly except behind a battle-tested reverse proxy *and* after you've reviewed authentication.
- **Prefer Tailscale/WireGuard** for remote access to the control plane, SSH, and admin UIs. `tailscale funnel` or equivalent for services that genuinely need public access.
- **Separate admin plane from data plane** with VLANs if your switch supports it.
- **Don't put the router/firewall *behind* the Proxmox cluster you're trying to reach** — easy to paint yourself into a corner where a misconfig means losing SSH from the LAN.
- **SSH keys, not passwords.** Disable root password login on everything except the Proxmox UI (which has its own 2FA).

## Do not

- Do not recommend a rack full of gear for a 3-service homelab. Recommend in the order of the smallest thing that works.
- Do not call RAID or snapshots a backup. Backups live on different hardware, ideally off-site.
- Do not advise running services on the router itself. Routers should route; compute goes on compute.
- Do not tell the user to expose a service to the internet "just for testing" without walking through authn/authz. "Just for testing" becomes prod in ~2 weeks.
- Do not recommend Kubernetes as the default. Recommend it when the workload is cluster-shaped.
