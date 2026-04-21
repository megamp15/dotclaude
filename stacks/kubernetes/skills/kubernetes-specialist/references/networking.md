# Networking

## Services

| Type | What it does |
|---|---|
| `ClusterIP` (default) | Internal virtual IP; cluster-only |
| `NodePort` | Exposes on every node's IP at a fixed port; rarely the right choice |
| `LoadBalancer` | Provisions a cloud LB (or MetalLB on bare-metal) |
| `ExternalName` | DNS CNAME to an external host; no proxying |
| Headless (`clusterIP: None`) | Returns pod IPs in DNS; required for StatefulSet stable names |

Canonical `ClusterIP`:

```yaml
apiVersion: v1
kind: Service
metadata: { name: api }
spec:
  selector: { app.kubernetes.io/name: api }
  ports:
    - name: http
      port: 80
      targetPort: http
  sessionAffinity: None
```

Target by named port (`targetPort: http`), not raw number — lets you
rename the container port without touching the Service.

## Ingress

Layer-7 HTTP/HTTPS routing. Requires an ingress controller (NGINX,
Traefik, HAProxy, cloud-native ALB/GCLB/AGIC).

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts: [api.example.com]
      secretName: api-tls
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api
                port: { name: http }
```

Rules:

- Always set `ingressClassName` — controllers are getting pickier.
- Use `cert-manager` for automatic TLS (Let's Encrypt).
- Keep annotations minimal and controller-scoped; they're how NGINX
  exposes features not in the core Ingress spec.

## Gateway API (the future)

Gateway API is the successor to Ingress — more expressive, supports
more protocols (HTTP, TCP, UDP, TLS, gRPC), cleaner separation of
concerns (`GatewayClass`, `Gateway`, `HTTPRoute`).

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: api }
spec:
  parentRefs:
    - name: public-gateway
      namespace: gateway-system
  hostnames: ["api.example.com"]
  rules:
    - matches:
        - path: { type: PathPrefix, value: / }
      backendRefs:
        - name: api
          port: 80
```

Use for new clusters where the controller supports it (NGINX
Gateway Fabric, Contour, Envoy Gateway, Traefik).

## NetworkPolicy

**Default deny, then allow.**

```yaml
# Deny all ingress to the namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny-ingress, namespace: api }
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
# Allow from known frontend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-frontend, namespace: api }
spec:
  podSelector:
    matchLabels: { app.kubernetes.io/name: api }
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: web }
          podSelector:
            matchLabels: { app.kubernetes.io/name: frontend }
      ports:
        - protocol: TCP
          port: 8080
```

Requires a CNI that enforces NetworkPolicy (Calico, Cilium, Weave,
cloud-native CNI that supports it). Flannel does not.

Rules:

- Start with default-deny in every namespace.
- Allow only what traffic you actually need.
- Allow egress for DNS (`kube-dns`) explicitly — otherwise DNS
  resolution breaks.
- Test policies with `netshoot` sidecar / ephemeral container:
  ```bash
  kubectl debug -n api $pod -it --image=nicolaka/netshoot --target=<container>
  ```

## DNS inside the cluster

Service DNS name pattern:

- `<service>.<namespace>.svc.cluster.local`
- Short form from same namespace: just `<service>`.
- Pod DNS (headless Service): `<pod>.<service>.<namespace>.svc.cluster.local`.

CoreDNS is the default. Common tuning:

- Cache more aggressively: `cache 30`.
- Forward to a specific upstream for private zones.

Don't disable DNS caching client-side — the Java DNS cache's default
(forever) causes real outages.

## Service mesh briefly

When to reach for a mesh (Istio, Linkerd, Cilium Service Mesh):

- You need mTLS between services without app-level TLS code.
- You need richer L7 policy (JWT validation, rate limits, retries)
  in the data plane.
- You want L7 observability (request metrics, distributed tracing)
  without app instrumentation.

When not:

- You have < ~20 services. The complexity cost isn't worth it.
- Your only need is traffic splitting — some Ingress controllers do
  canary / mirror natively.

Linkerd is the simplest. Istio is the most capable. Cilium is
attractive if you're already on eBPF-based CNI.

## LoadBalancer on bare metal

Managed clusters provision cloud LBs for `type: LoadBalancer`.
Bare-metal clusters need MetalLB or similar:

- **L2 mode** — broadcasts the VIP via ARP; works on any network but
  only one node serves traffic at a time.
- **BGP mode** — peers with your router; true load balancing across
  nodes. Requires a BGP-capable switch.

Home labs: MetalLB L2 is almost always the right choice.

## Ingress controller sizing

NGINX ingress controller:

- 2–3 replicas minimum for HA.
- PDB with `maxUnavailable: 1`.
- HPA on CPU.
- Dedicated node pool if you want to isolate ingress traffic.

## CNI selection

| CNI | Strengths | Weaknesses |
|---|---|---|
| Cilium | eBPF-based; rich L7 policy; observability via Hubble | Complex, big control plane |
| Calico | Mature, stable, strong policy | L7 via separate component |
| Flannel | Simple | No NetworkPolicy enforcement |
| Weave | Deprecated; avoid for new clusters | — |
| Cloud-native (VPC-CNI on EKS, etc.) | Tight IP integration | Tied to provider |

For new homelab clusters: **Cilium** is increasingly the default.
For AWS EKS: stick with VPC-CNI unless you specifically need Cilium
features.

## Egress

Outbound traffic from pods usually SNATs through a node's IP.
Options to constrain / tag:

- **Static egress IPs** — cloud-specific (EKS IPAMD add-on, GKE
  Cloud NAT).
- **Egress gateway** in service mesh — route egress through specific
  pods.
- **NetworkPolicy `egress`** — allow-list outbound destinations.

Critical when a third-party vendor whitelists source IPs.

## Debugging network issues (quick bank)

- **Pod can't reach Service** → check NetworkPolicy, DNS, Service
  selector.
- **Service has no endpoints** → pod labels don't match Service
  selector; check with `kubectl get endpoints <svc>`.
- **Intermittent 502 on Ingress rollout** → preStop hook + graceful
  shutdown missing.
- **Long TCP connect times** → CNI IPAM warm-pool exhausted; node
  scaling.
- **`kubectl exec` slow** → check API server latency, webhook
  admission.
- **DNS resolves `externalName` slowly** → ndots: 5 default causes
  search-list expansion; set `ndots: 2` in pod DNS config for
  external-heavy workloads.
