# Storage and backup

Storage choices compound. Backups *prevent* compounding mistakes.
Pay attention to both early.

## Storage layers, by role

```
┌───────────────────────────────────────────────────────────────┐
│ Application                                                   │
├───────────────────────────────────────────────────────────────┤
│ Access protocol: NFS | SMB | S3 | iSCSI | CephFS | local FS   │
├───────────────────────────────────────────────────────────────┤
│ Filesystem / block:    ZFS | ext4 | XFS | Btrfs | Ceph | ...  │
├───────────────────────────────────────────────────────────────┤
│ Disks:                 SATA | SAS | NVMe | USB (don't)        │
└───────────────────────────────────────────────────────────────┘
```

Pick the access protocol for the consumer, then filesystem for the
host, then let those choose disks. Reverse that order and you end up
with a RAIDZ3 pool serving a single Jellyfin library.

## ZFS — default filesystem for homelabs

Unless you have a strong reason otherwise:

- **Root pool**: mirrored pair (RAID1-style) of SSDs. Fast, resilient, easy to upgrade.
- **Data pool**: RAIDZ1 (4-6 disks) or RAIDZ2 (6+ disks) for large-capacity bulk storage. RAIDZ3 only for very large pools with slow rebuild times.
- **Special vdev**: add an NVMe mirror as "special" for metadata + small files — transforms browse performance on a spinning-disk pool. Losing the special vdev loses the pool, so mirror it.
- **SLOG**: power-loss-protected NVMe for sync-heavy workloads (NFS with `sync`, databases). Not needed for async workloads.
- **L2ARC**: read cache. Useful only in specific workloads; many homelabs don't benefit.

### ZFS settings that matter day one

- `compression=lz4` (or `zstd` for better ratio at CPU cost). Always on.
- `atime=off` — stop updating access times on every read.
- `recordsize`:
  - Default (128k) for mixed / media.
  - 1M for video libraries and backup targets.
  - 16k or 8k for database datasets.
- `xattr=sa` — faster xattr storage (matters for containers).
- `ashift=12` (4k) — right for nearly every modern disk. Set at pool creation; can't change later.

### ZFS snapshots + send/recv

- `zfs snapshot tank/data@daily-$(date +%F)` — instant, copy-on-write.
- Automate with `zfs-auto-snapshot` or `sanoid`.
- Replicate offsite with `syncoid` (wraps `zfs send/recv` over SSH) — incremental, resumable, efficient.

Snapshots are **not backups** — they live on the same pool. But they handle the "I deleted a file yesterday" case in ~10 seconds.

## Shared storage options

### NFS — the workhorse

- Good for: VM disks in Proxmox, shared media, Kubernetes RWX volumes.
- Gotchas: `no_root_squash` is a security trap if you run it across trust boundaries; ID mapping (UID/GID) across Linux clients must match; `sync` vs `async` — `async` is fast but risks data loss on server crash.
- Kubernetes: `nfs-subdir-external-provisioner` is easy; the NFS server is a single point of failure.

### SMB/CIFS — for Windows / macOS clients

Slower than NFS for Linux-to-Linux; use it when clients demand it.

### S3 (MinIO or SeaweedFS)

- MinIO: S3-compatible object store; single-binary, easy setup, good for backup targets and apps that speak S3.
- SeaweedFS: distributed, supports S3 + filer + mount.
- Use S3 when apps want it. Don't force apps that expect filesystems onto S3.

### Ceph / Rook-Ceph

- Enterprise-grade distributed storage. Runs well; needs compute + memory + disks at a level most homelabs don't justify.
- Minimum useful: 3 nodes, 3+ disks each, 10 GbE network.
- Below that scale, Longhorn or NFS is usually a better match.

### Longhorn (Kubernetes-specific)

- Distributed block storage for k8s. Replicates volumes across nodes.
- Lighter than Ceph, good UI, good enough for homelab HA.
- Recommended default for multi-node k8s homelabs.

## Backup strategy — the 3-2-1 rule

**3** copies of your data, on **2** different media, with **1** copy off-site.

Homelab translation:

- **Copy 1**: your live data on the primary pool.
- **Copy 2**: a secondary pool or different machine (`zfs send` target, or a dedicated backup box).
- **Copy 3 (off-site)**: cloud (B2, S3, Storj, rsync.net) or a friend's place or a drive at the office.

Snapshots + raid + one local copy = copy 1 three times. It's not backup.

### What to back up

In priority order:

1. **Irreplaceable personal data**: photos, documents, family media. Don't lose these.
2. **Config + IaC**: Proxmox configs, Talos/k3s state, k8s manifests, Terraform state, Ansible playbooks. Most of this should live in a git repo (off-machine = half-a-backup). Git alone isn't enough for binary state like Terraform remote state.
3. **Service data**: databases, Home Assistant history, media server metadata.
4. **Media libraries**: re-downloadable if lost, but re-downloading is weeks of work. Worth backing up, lower priority than 1-3.
5. **VM disks**: usually reproducible from templates + config management, so lower priority — but Proxmox VE's built-in backup (vzdump) handles this cheaply.

### Tools

- **Proxmox Backup Server (PBS)** — incremental, deduplicated, purpose-built for PVE. Run on a second box. Backups are tiny after first run.
- **Restic / borgbackup / kopia** — modern incremental encrypted backup tools. Point at files; push to local disk, NFS, S3, B2, whatever. Kopia has a good UI; Restic has broader support; Borg is the old reliable.
- **rsync + cron** — works but not incremental in a dedup sense; avoid for large backup sets.
- **zrepl / sanoid + syncoid** — for ZFS-based replication. Block-level, efficient.

### Test restores

**A backup you haven't restored is a rumor of a backup.**

Quarterly at minimum:

- Pick one backup run.
- Restore to a throwaway VM / path.
- Verify the restored data opens / starts / matches a known-good sample.
- Write down how long it took; if it's hours, your DR plan needs work.

If you've never restored from your backup, your backup does not exist. Restoring is not optional.

## Retention policy

A default that works for most homelabs (tune per dataset):

- **Hourly snapshots**: keep last 24.
- **Daily**: keep last 7.
- **Weekly**: keep last 4.
- **Monthly**: keep last 12.
- **Yearly**: keep 3+.

That's ~50 snapshots per dataset — on ZFS with `lz4`/`zstd`, near-zero incremental cost.

Off-site backups: same cadence if the pipe can handle it; otherwise daily + weekly + monthly + yearly.

## Common storage + backup footguns

- **"RAID is a backup"** — It isn't. RAID protects against one kind of failure (disk). Fire, theft, `rm -rf /`, ransomware — RAID helps with none of these.
- **Snapshot retention set to "forever"** — pool fills up unexpectedly; snapshots can't be easily freed. Always set a retention.
- **No off-site copy because "my data isn't that critical"** — reassess after the first data loss.
- **Backups with the same credentials as the source** — ransomware encrypts both. Backups should require different credentials OR be immutable (append-only, versioning on).
- **Untested backups** — see above.
- **Database backups via filesystem snapshot without app coordination** — can restore to a corrupted state. Use the DB's native dump tool or snapshot with coordinated quiesce.
- **Giant single-pool for everything** — when a pool dies, everything's gone. Separate pools for VM disks vs irreplaceable data vs media; different redundancy per pool based on value.
