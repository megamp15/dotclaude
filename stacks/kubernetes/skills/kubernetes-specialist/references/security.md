# Kubernetes security

## RBAC — scoped by default

```yaml
# Namespaced
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: api-reader, namespace: api }
rules:
  - apiGroups: [""]
    resources: [configmaps, secrets]
    resourceNames: [api-config, api-secrets]
    verbs: [get]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: api-reader, namespace: api }
subjects:
  - kind: ServiceAccount
    name: api
    namespace: api
roleRef:
  kind: Role
  name: api-reader
  apiGroup: rbac.authorization.k8s.io
```

Rules:

- **Start with empty permissions**; grant only what the workload uses.
- **`resourceNames`** to restrict a rule to specific named objects when
  possible.
- **`Role`/`RoleBinding`** (namespace-scoped) over `ClusterRole`/`ClusterRoleBinding`
  (cluster-wide) unless you truly need cross-namespace.
- **One `ServiceAccount` per workload.** `default` is a trap — loses you
  the audit trail and makes per-workload policy impossible.

## ServiceAccount identity

- K8s SA → short-lived bearer token (projected into pod, rotated by
  kubelet).
- In-cluster SDK / `kubectl` from inside a pod uses the mounted SA
  token.

For cloud access:

- **AWS IRSA** — map SA to IAM role via OIDC:
  ```yaml
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: api
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::ACC:role/api-role
  ```
- **GKE Workload Identity** — annotate SA with GSA:
  ```yaml
  annotations:
    iam.gke.io/gcp-service-account: api@project.iam.gserviceaccount.com
  ```
- **Azure Workload Identity** — federated credential on AAD app.

Never store long-lived cloud keys in Secrets if workload identity is
available.

## Pod Security Standards

Three levels: `privileged`, `baseline`, `restricted`. Enforce per
namespace:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: api
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/audit:    restricted
    pod-security.kubernetes.io/warn:     restricted
```

Target `restricted` for application namespaces; `baseline` for
platform/control-plane stuff that genuinely needs e.g. `hostNetwork`.

`restricted` requires:

- `runAsNonRoot: true`
- `allowPrivilegeEscalation: false`
- No `hostNetwork`, no `hostPID`, no `hostIPC`, no `hostPath`
- All capabilities dropped; only `NET_BIND_SERVICE` allowed
- Seccomp `RuntimeDefault` or localhost profile

Template:

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    fsGroup: 10001
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: app
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: [ALL] }
```

## NetworkPolicy defaults

See `networking.md`. Default-deny ingress is the floor.

## Secrets — don't stop at K8s Secrets

K8s Secrets are **base64-encoded, not encrypted at rest by default**.
They're visible to anyone with `get` on secrets in the namespace.

Minimum:

- Enable **etcd encryption at rest** (control-plane config).
- Restrict SA access to secrets.

Better:

- **External Secrets Operator (ESO)** syncs from Vault / AWS Secrets
  Manager / GCP Secret Manager / Azure Key Vault:
  ```yaml
  apiVersion: external-secrets.io/v1beta1
  kind: ExternalSecret
  metadata: { name: api-secrets, namespace: api }
  spec:
    refreshInterval: 1h
    secretStoreRef: { name: aws-sm, kind: SecretStore }
    target: { name: api-secrets, creationPolicy: Owner }
    data:
      - secretKey: DB_PASSWORD
        remoteRef: { key: api/prod/db }
  ```
- **Sealed Secrets** (Bitnami) — encrypt manifests at rest, commit to
  git, sealer decrypts in-cluster. Good when your source of truth is
  git.
- **Vault Agent Injector** — vault-native sidecar / init container.

## Image policy

- **Pin by digest** in production:
  `image: ghcr.io/mycorp/api@sha256:abc...`
- **Scan in CI**: `trivy image` against the built image. Fail PR on
  HIGH+.
- **Admission policy**: Kyverno / OPA Gatekeeper to reject images from
  unknown registries:
  ```yaml
  apiVersion: kyverno.io/v1
  kind: ClusterPolicy
  metadata: { name: require-registries }
  spec:
    validationFailureAction: Enforce
    rules:
      - name: only-mycorp-registry
        match: { any: [{ resources: { kinds: [Pod] } }] }
        validate:
          message: "Image must come from ghcr.io/mycorp or registry.gitlab.com/mycorp"
          pattern:
            spec:
              containers:
                - image: "ghcr.io/mycorp/* | registry.gitlab.com/mycorp/*"
  ```
- **Sign images** with `cosign`; require signed images via Sigstore
  admission policy.

## Admission control

Two popular engines:

- **Kyverno** — K8s-native CRDs, YAML policies; smooth learning curve.
- **OPA Gatekeeper** — Rego; more expressive, steeper learning curve.

Common policies (both):

- Require `resources.requests` on every container.
- Forbid `:latest` tag.
- Forbid privileged pods, `hostPath`, `hostNetwork`.
- Require specific labels (`owner`, `cost-center`).
- Restrict `imagePullPolicy` to `IfNotPresent` for digest-pinned
  images.
- Enforce that every Deployment > 1 replica has a PDB.

## Audit logs

Control plane:

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: RequestResponse
    verbs: [create, update, patch, delete]
    resources:
      - group: ""
        resources: [secrets, configmaps, serviceaccounts]
  - level: Metadata
```

Ship logs to your SIEM. Alert on:

- `create secrets` outside expected automation.
- `exec` into pods in prod namespaces.
- `escalate` / `impersonate` calls.
- Failed auth attempts.

## Supply chain

- Build reproducible containers (pinned base images, locked deps).
- Generate SBOM (syft, `docker sbom`).
- Sign with cosign.
- Track exposure via `trivy image` scheduled against your deployed
  images, not just at build time.

## Multi-tenancy

Cheapest: namespace isolation + RBAC + NetworkPolicy + PSS restricted.
Most orgs stop here.

Hardened:

- Separate node pools per tenant (`nodeSelector` + taints).
- Separate clusters per risk tier ("prod" vs. "untrusted-customer-code").
- `vcluster` / capsule for soft multi-tenancy on a shared cluster.

Hard multi-tenancy (two mutually-distrustful tenants) is hard on
Kubernetes. Separate clusters are usually the right answer.
