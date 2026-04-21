# Bring-up patterns — Proxmox + Talos/k3s/k8s

How to bring up a homelab cluster without making it a snowflake.

## The ordering that saves time

1. Proxmox host(s) — bare metal install, networking sane, ZFS pool set up.
2. Decide: VM (heavy, flexible) vs LXC (light, constrained). Most services: LXC. Cluster nodes: VMs.
3. VM templates — build one golden image per OS you care about, clone from it.
4. Kubernetes cluster (if needed) — Talos or k3s, on VM clones.
5. Storage class + CNI + LoadBalancer (MetalLB) — the infra k8s needs before apps make sense.
6. Ingress controller (Traefik/Nginx) — the front door for everything.
7. First real service — end-to-end smoke test.
8. Backups and monitoring — before you trust the cluster with anything important.

Skipping steps 5-6 is the most common cause of "my cluster is up but nothing works." A cluster with no storage class, no LB, and no ingress is not usable; it just passes `kubectl get nodes`.

## Proxmox host

### First-install settings that save pain later

- **ZFS on install** — pick the root filesystem as ZFS mirror if you have two drives, RAIDZ if 3+. ZFS snapshots and rollback are the single biggest day-2 win.
- **Separate data pool** — don't put VM disks on the root pool. Make a separate pool (`tank` or similar) for VM storage; root pool small and ZFS-scrubbed.
- **Bridge networking** — `vmbr0` on your LAN NIC. Add `vmbr1` for an internal-only network if you want VMs isolated from LAN.
- **Disable subscription repo nags** or enable the no-subscription repo for updates.
- **Turn on unprivileged LXCs** by default. Privileged LXCs are root-on-host if escaped.

### LXC feature flags worth knowing

- `nesting=1` — needed to run Docker or systemd-nspawn inside an LXC.
- `keyctl=1` — needed for Docker inside LXC (along with nesting).
- `mount=nfs` — let the LXC mount NFS directly; otherwise mount on host and bind-mount in.
- GPU passthrough to LXC: add the `/dev/dri` or `/dev/nvidia*` devices via `lxc.cgroup2.devices.allow` + `lxc.mount.entry`. Simpler than VM passthrough and enough for most compute/transcode use.

### VM templates

Build once, clone N times. Template checklist:

- Cloud-init enabled (`qm set <id> --ide2 local-lvm:cloudinit`).
- QEMU guest agent installed on the template OS.
- SSH keys (yours) baked in via cloud-init.
- Tailscale or equivalent pre-installed + auto-auth if you're comfortable with that trust level.
- `apt-get upgrade` or equivalent done before converting to template.
- Convert to template (`qm template <id>`), then clone with `qm clone`.

This turns "spin up a new node" from a 30-minute install into a 90-second clone.

### GPU passthrough (one-liner because it's a rabbit hole)

If you want a GPU inside a VM:

1. IOMMU enabled in BIOS + `intel_iommu=on` (or `amd_iommu=on`) on kernel cmdline.
2. VFIO modules loaded.
3. Blacklist the GPU driver on the host.
4. Pass the PCI device to the VM.
5. Accept that reboots sometimes break things.

Full walkthrough is its own document. Not attempting to re-derive it here — point the user at Proxmox docs + the `pve-gpu-passthrough` community wiki.

## Talos bring-up (recommended for k8s on Proxmox)

```
┌──────────────────────────┐
│ PVE node                 │
│ ┌──────────┐ ┌─────────┐ │
│ │ talos-cp │ │ talos-w1│ │
│ └──────────┘ └─────────┘ │
│         ┌─────────┐      │
│         │ talos-w2│      │
│         └─────────┘      │
└──────────────────────────┘
```

Flow:

1. Download Talos ISO; upload to PVE.
2. Create VM per node (control plane: 2-4 vCPU / 4 GB RAM / 40 GB disk; workers: sized to workload).
3. Boot Talos ISO, it shows its API IP.
4. On your workstation: `talosctl gen config <cluster-name> https://<cp-ip>:6443`.
5. Apply the control-plane config: `talosctl apply-config --insecure --nodes <cp-ip> --file controlplane.yaml`.
6. Apply worker config to each worker node.
7. Bootstrap etcd: `talosctl bootstrap --nodes <cp-ip> --endpoints <cp-ip>`.
8. Fetch kubeconfig: `talosctl kubeconfig --nodes <cp-ip> --endpoints <cp-ip>`.
9. `kubectl get nodes` — should show all as Ready after CNI installs.

**Sanity-check stop**: nodes stuck `NotReady` → CNI hasn't installed. Talos ships with Flannel by default; if you chose a custom config with no CNI, you need to apply one. Cilium is a common upgrade.

## k3s bring-up (if Talos feels too alien)

```bash
# control plane
curl -sfL https://get.k3s.io | sh -

# workers (get the node-token from the control plane first)
curl -sfL https://get.k3s.io | K3S_URL=https://<cp-ip>:6443 \
  K3S_TOKEN=<node-token> sh -
```

That's it. k3s ships with Traefik, a local-path storage class, and ServiceLB. For a home cluster this is already usable. Swap pieces as needs grow:

- `--disable traefik` and install your own ingress if you want Nginx.
- `--disable servicelb` and install MetalLB if you want Real Load Balancer IPs.
- Replace local-path with Longhorn for multi-node persistent volumes.

## First-class cluster pieces you need before services make sense

### CNI
Default (Flannel on k3s/Talos) is fine for homelab. Cilium is worth the upgrade if you care about NetworkPolicy enforcement, eBPF observability, or mesh-lite features.

### Storage class

- **Single-node**: `local-path` (k3s default). PVs pinned to node; fine while cluster is ~1 node.
- **Multi-node, "good enough"**: **Longhorn**. Block storage with replicas across nodes; simple UI; decent for homelab.
- **NFS-backed**: `nfs-subdir-external-provisioner` against a host NFS export. Simple; single point of failure (the NFS host).
- **Advanced**: **Rook-Ceph** or bare Ceph. Production-grade; heavy for homelab. Don't default here.

### LoadBalancer

- **MetalLB in L2 mode** (default) — ARP-announces IPs on your LAN; works on any switch. Assign a pool of IPs from your LAN subnet outside the DHCP range.
- **MetalLB in BGP mode** — peers with your router; more elegant, more complex, requires router support.
- **k3s ServiceLB / klipper-lb** — uses HostPort on nodes; fine for small homelabs, doesn't give "real" LB IPs.

### Ingress controller

Traefik (k3s default) or Nginx Ingress or Caddy. Pick one and stick with it. Consistency > theoretical best. All of them handle HTTPS cert automation via cert-manager or built-in integrations (Traefik does this natively).

## Smoke test — does the cluster work?

After bring-up, deploy one simple thing end-to-end:

```yaml
# hello.yaml — paste this, it works on any cluster with ingress
apiVersion: apps/v1
kind: Deployment
metadata: { name: hello }
spec:
  replicas: 1
  selector: { matchLabels: { app: hello } }
  template:
    metadata: { labels: { app: hello } }
    spec:
      containers:
      - name: hello
        image: nginxdemos/hello:plain-text
        ports: [{ containerPort: 80 }]
---
apiVersion: v1
kind: Service
metadata: { name: hello }
spec:
  selector: { app: hello }
  ports: [{ port: 80, targetPort: 80 }]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hello
  annotations: { kubernetes.io/ingress.class: "traefik" }  # or "nginx"
spec:
  rules:
  - host: hello.lab.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend: { service: { name: hello, port: { number: 80 } } }
```

If `curl hello.lab.example.com` from your LAN returns something, the cluster is functional. If not, the traceback is shorter than debugging a real app's failure.

## Anti-patterns we see a lot

- **Multi-node "cluster" with all etcd on one node.** You don't have a cluster; you have a single point of failure with extra steps. Run 3 control plane nodes or accept you're running a single-node cluster.
- **Mixing cluster storage with personal data on the same pool** without quotas. Data bloat in one kills the other.
- **No infra-as-code for the cluster config.** Talos config, k3s bootstrap, manifests — all of it should live in a git repo. If your cluster is held together by yesterday's shell history, you're one reboot away from reinstalling.
- **Skipping monitoring until something breaks.** Prometheus + node-exporter + cAdvisor on day 2 is cheap. Diagnosing a dead cluster with no telemetry is expensive.
