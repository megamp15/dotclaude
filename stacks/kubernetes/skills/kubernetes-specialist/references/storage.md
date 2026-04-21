# Storage

## PV / PVC lifecycle

- **PersistentVolume (PV)** — a cluster-level object representing a piece
  of storage (a disk, a volume, an NFS export).
- **PersistentVolumeClaim (PVC)** — a user-level request for storage.
- **StorageClass** — parameters the dynamic provisioner uses to create a
  new PV on demand.

Normal flow: pod → PVC → StorageClass → CSI driver provisions → binds to
PV → mounted into pod.

## StorageClass

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
reclaimPolicy: Delete              # or Retain for anything irreplaceable
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer   # delays provisioning until pod is scheduled
```

Rules:

- **`volumeBindingMode: WaitForFirstConsumer`** for zonal storage — avoids
  provisioning a volume in a zone the pod can't run in.
- **`allowVolumeExpansion: true`** — you'll want to grow volumes later.
- **`reclaimPolicy: Retain`** for production data. `Delete` is fine for
  ephemeral / replaceable workloads.

## Access modes

| Mode | Meaning | Typical driver |
|---|---|---|
| `ReadWriteOnce` (RWO) | One node at a time (one pod, or multi-pod on same node) | EBS, GP3, Azure Disk, GCE PD |
| `ReadOnlyMany` (ROX) | Many nodes read | NFS, some cloud disks in RO |
| `ReadWriteMany` (RWX) | Many nodes read/write | NFS, EFS, Azure Files, Longhorn |
| `ReadWriteOncePod` (RWOP) | Exactly one pod | Newer, CSI-supported |

For stateful singleton pods (Postgres, Redis primary) — RWO is correct.
For shared data across replicas — you need RWX (NFS / EFS / Longhorn /
OpenEBS) or rearchitect.

## StatefulSet storage

```yaml
volumeClaimTemplates:
  - metadata: { name: data }
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: gp3
      resources: { requests: { storage: 100Gi } }
```

Each replica gets its own PVC named `<template>-<statefulset>-<ordinal>`:
`data-postgres-0`, `data-postgres-1`, `data-postgres-2`.

**Deleting a StatefulSet does not delete the PVCs.** This is intentional.
`kubectl delete pvc -l app=postgres` to actually free the storage.

## Volume modes

- **`Filesystem`** (default) — formatted, mounted.
- **`Block`** — raw block device mapped into the pod. Databases that want
  to bypass filesystem overhead, or apps using DRBD-style replication.

## CSI drivers

Every modern driver is a CSI driver. The relevant ones:

| Environment | Driver |
|---|---|
| AWS | `aws-ebs-csi-driver` (RWO), `aws-efs-csi-driver` (RWX) |
| GCP | `pd.csi.storage.gke.io` (RWO), Filestore CSI (RWX) |
| Azure | `disk.csi.azure.com`, `file.csi.azure.com` |
| Proxmox / homelab | Longhorn, OpenEBS (Mayastor or cStor), Rook/Ceph |
| Talos / bare metal | Longhorn or OpenEBS Mayastor |
| NFS anywhere | `nfs-subdir-external-provisioner` |

Install via Helm; verify the `CSIDriver` CR shows up:

```bash
kubectl get csidrivers
```

## Homelab storage choices

| Option | When |
|---|---|
| **Longhorn** | Default for homelab clusters — replicated block storage, simple UI |
| **OpenEBS Mayastor** | When you need higher performance than Longhorn; NVMe-aware |
| **NFS** | Shared-across-pods data; simple if you have a NAS |
| **Rook/Ceph** | Serious scale; heavy operational burden |
| **local-path-provisioner** (Rancher) | Dev clusters only; single-node "storage" |

Longhorn is almost always the right first answer for a 3-node+ homelab.

## Resize a PVC

```bash
kubectl patch pvc data-postgres-0 -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
```

Requires `allowVolumeExpansion: true` on the StorageClass. Some drivers
need a pod restart to pick up the new size; most online-resize nowadays.

## Backup

Built-in primitives are minimal. Options:

- **Velero** — cluster-level: manifests + volume snapshots. Best general
  answer.
- **CSI VolumeSnapshot** — take point-in-time snapshot of a PVC:
  ```yaml
  apiVersion: snapshot.storage.k8s.io/v1
  kind: VolumeSnapshot
  metadata: { name: pg-snap-20260417 }
  spec:
    volumeSnapshotClassName: csi-hostpath-snapclass
    source: { persistentVolumeClaimName: data-postgres-0 }
  ```
- **Application-aware** — `pg_dump`, `mongodump`, etc., stored in S3.
  Preferred for databases; avoid relying solely on volume snapshots for
  RDBMS.

Rule: follow **3-2-1** — 3 copies, 2 media types, 1 off-site. See
`core/skills/homelab-infra/` for the broader strategy.

## Storage gotchas

- **Pending pods**: PVC cannot be bound. `kubectl describe pvc` to see
  why (no StorageClass, no matching PV, zone mismatch).
- **Pod stuck terminating**: PV still mounted somewhere. Check
  `kubectl describe pod` events for `FailedUnmount`.
- **Data loss after scale-down**: PVC stayed, pod died, PVC got
  deleted. Set `reclaimPolicy: Retain` or take snapshots before big
  ops.
- **Zonal volumes, cross-zone scheduling**: pod can't start because PV
  is in another zone. Use `WaitForFirstConsumer` binding mode.
- **Full volume**: pod can't write. Alerts on PV usage > 80%.
  CSI drivers that support expansion can grow online.

## StorageClass defaults and tiers

Offer tiers, not a single class:

```yaml
# High-performance
name: nvme-ssd
parameters: { type: io2, iops: "10000" }
reclaimPolicy: Retain

# General-purpose default
name: gp3
parameters: { type: gp3 }
reclaimPolicy: Delete
annotations: { storageclass.kubernetes.io/is-default-class: "true" }

# Archive / cold
name: sc1
parameters: { type: sc1 }
```

Teams pick the tier they need; the default catches forgotten
declarations.
