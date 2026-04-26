# Crypto and secrets

## First rule: don't invent

Use well-maintained libraries. The number of subtle bugs in
hand-rolled crypto that look fine in a code review is overwhelming.

| Task | Library |
|---|---|
| Python high-level | [`cryptography`](https://cryptography.io) (`Fernet` for symmetric) |
| Python low-level | `pynacl` (libsodium bindings) |
| Node.js | built-in `crypto`; `@noble/*` audited libraries; `libsodium-wrappers` |
| Browser | WebCrypto API |
| Go | stdlib `crypto/*`; `golang.org/x/crypto/nacl/*` |
| Rust | `ring`, `RustCrypto/*` |

Avoid: anything that exposes raw AES blocks, raw RSA primitives, or
lets you pick modes by guessing.

## Hashing vs. encryption vs. signing

- **Hash** — one-way. For integrity, content-addressing, password
  storage.
- **Encryption** — two-way with a key. For confidentiality.
- **Signing** — asymmetric; prove authorship / integrity.
- **MAC** — symmetric signing; prove integrity with a shared key.

Use the right tool. Encrypting a password "for safety" is
*wrong*; hash with Argon2id instead.

## Symmetric encryption

Default: AES-256-GCM or ChaCha20-Poly1305 via a high-level API.

```python
# Python with cryptography
from cryptography.fernet import Fernet
key = Fernet.generate_key()
f = Fernet(key)
token = f.encrypt(plaintext_bytes)
f.decrypt(token)    # raises on tamper
```

```python
# Low-level AES-GCM (if you must)
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
key = AESGCM.generate_key(bit_length=256)
aes = AESGCM(key)
nonce = os.urandom(12)
ct = aes.encrypt(nonce, plaintext, aad)
pt = aes.decrypt(nonce, ct, aad)
```

Rules:

- **Nonce / IV must be unique per key.** For GCM with a random 96-
  bit nonce, safe for ~2^32 messages. Beyond that, use an XChaCha
  or a counter.
- **Include AAD** (associated data) for any context binding.
- **Don't reuse nonce+key** — catastrophic for GCM.

## Asymmetric

Use Ed25519 for signatures. X25519 for key exchange. Don't touch
RSA unless you must interop with a legacy system that requires it;
then use 3072+ bits and OAEP.

```python
# libsodium signing
from nacl.signing import SigningKey
signer = SigningKey.generate()
sig = signer.sign(message)
signer.verify_key.verify(message, sig.signature)
```

## Random / nonces / IDs

- **Security-critical** — `secrets` (Python), `crypto.randomBytes`
  (Node), `crypto/rand` (Go), `SecureRandom` (Java).
- **Non-security** — `random` / `Math.random` fine.
- **UUIDs for IDs exposed to users**: UUID v4 (random) or v7
  (time-ordered, random-filled) — both unguessable.

**Never** use `Math.random` for tokens, session IDs, CSRF tokens.

## Constant-time comparison

When comparing secrets (tokens, HMACs):

```python
import hmac
if hmac.compare_digest(token, expected):
    ...
```

Early-exit `==` leaks timing information. `compare_digest` compares
in constant time.

## Webhook signing

Pattern:

- Issuer signs `timestamp + "." + body` with HMAC-SHA256.
- Header: `X-Signature-Timestamp: 1698...`, `X-Signature: hexdigest`.
- Receiver:
  1. Rejects if `|now - timestamp| > 5 minutes` (replay protection).
  2. Computes expected HMAC.
  3. Constant-time compares.

```python
def verify(body: bytes, ts: int, sig: str, key: bytes) -> bool:
    if abs(time.time() - ts) > 300:
        return False
    mac = hmac.new(key, f"{ts}.".encode() + body, "sha256").hexdigest()
    return hmac.compare_digest(mac, sig)
```

Rotate HMAC keys via header-based key ID: `X-Signature-Key: v2`.

## TLS

- **Use TLS 1.2 or 1.3 only.** Disable 1.0, 1.1, SSL v3.
- **Certificates**: publicly trusted for public endpoints; private
  CA or mTLS for internal.
- **Certificate validation** — verify hostname + chain. Don't
  pass `verify=False`.
- **HSTS** on public web: `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`.
- **Let's Encrypt / ACME** for free public certs; automated
  rotation via cert-manager or Caddy.

### mTLS

For service-to-service within an infrastructure:

- Issue client certs from a private CA.
- Rotate short-lived (hours) via SPIFFE / SPIRE or a mesh
  (Linkerd, Istio).
- The server verifies client cert; the client verifies server
  cert.

## Secret storage

### Never in repo

`.env` files in `.gitignore`. Only `.env.example` with non-secret
placeholders.

Secret scanners in pre-commit:

```yaml
# .pre-commit-config.yaml
- repo: https://github.com/gitleaks/gitleaks
  rev: v8.18.2
  hooks:
    - id: gitleaks
```

CI runs `gitleaks detect --source .` or `trufflehog`.

### Storage options

| Option | When |
|---|---|
| HashiCorp Vault | Multi-tenant; dynamic secrets; strong audit |
| AWS Secrets Manager | On AWS |
| GCP Secret Manager | On GCP |
| Azure Key Vault | On Azure |
| Kubernetes Secret + Sealed Secrets | K8s native, GitOps-friendly |
| External Secrets Operator | K8s → external SM |
| 1Password / Doppler / Infisical | Developer-friendly hosted |

### Injection

- **Environment variables** are the lingua franca. Fine.
- **Mounted files** (K8s Secret as volume) — atomic updates on
  rotation.
- **Sidecar fetchers** (Vault Agent) — pull fresh secrets
  periodically.
- **Short-lived credentials** (IAM roles, workload identity) —
  best when available. No static secret to rotate.

### Rotation

Plan:

- Automatic where possible (IAM, short-lived).
- Quarterly for manual rotations (API keys, database credentials).
- Immediately on suspected breach.
- Never in-place; roll with two active keys, deprecate the old
  once clients have moved.

## Logging and redaction

Redact secrets **at log-entry time**, not aggregation time:

```python
class SafeAdapter(logging.LoggerAdapter):
    def process(self, msg, kwargs):
        for k in ("password", "token", "api_key"):
            if k in kwargs.get("extra", {}):
                kwargs["extra"][k] = "***"
        return msg, kwargs
```

Pattern-scrub the plaintext (emails, tokens, card numbers) with an
allowlist of what can pass through.

**Error responses** — don't leak stack traces, env vars, or SQL
errors to users. Log server-side, return a generic message.

## Dependency hygiene

- **Pin versions** in lockfile — dependency confusion / pinning
  is first-line defense.
- **Scan** — `pip-audit`, `npm audit`, `cargo audit`, `trivy`,
  `grype`. Weekly cron + PR gate.
- **Patch window** — CVE fixes merged within 7 days for high /
  critical.
- **Minimal base images** — distroless, Chainguard, Wolfi. Fewer
  packages → fewer CVEs.
- **SBOM** — generate `cyclonedx` or `spdx` per build. Ship with
  release artifacts.
- **Signed artifacts** — `cosign sign` images; verify on deploy.
- **Verify transitive provenance** — `npm install --ignore-scripts`
  to disable npm lifecycle scripts by default; review `postinstall`
  hooks.

## Supply-chain threats

- **Typosquatting** — check `requests-oauthlib` vs.
  `request-oauthlib`. Use lockfile + review.
- **Maintainer takeover** — if a single maintainer of a popular
  lib is compromised, downstream is breached. Prefer libraries
  with organizational maintainers.
- **Post-install scripts** — npm scripts can run arbitrary code
  during install. Review or disable.
- **Prototype pollution in JS** — see input-and-output.md.
- **PyPI source distributions** — `setup.py` runs arbitrary code.
  Prefer wheels.

## Secret kinds and their life cycles

| Secret | TTL ideal | How to rotate |
|---|---|---|
| Cloud IAM access keys | 0 (don't use) — use roles | If unavoidable: 90d |
| Database password | 90d | Dual-key rolling via Secrets Manager |
| OAuth client secret | 1y | Regenerate at IdP, deploy |
| JWT signing key | 30d | JWKS with multiple keys |
| Webhook HMAC | 90d | Header-based key ID versioning |
| TLS cert (public) | 90d (LE default) | Auto via ACME |
| TLS cert (internal mTLS) | 24h–7d | Short-lived via SPIFFE |
| Encryption keys (DEK) | 1y+ | Rotate via KMS; re-encrypt data lazily |
| KMS root | per-compliance | Managed by KMS |

## When you really must encrypt app data

Use an envelope-encryption pattern:

- Data is encrypted with a random **Data Encryption Key (DEK)**.
- DEK is encrypted with a **Key Encryption Key (KEK)** managed by
  KMS.
- Store encrypted DEK + ciphertext together; KEK stays in KMS.

Libraries: AWS Encryption SDK, GCP Tink, HashiCorp Vault Transit.

## Things that look secure and aren't

- **"We use SHA256 for passwords"** — too fast; hashes to brute
  force in bulk. Use Argon2id.
- **"We base64 encode tokens"** — not encryption.
- **"We encrypt with AES ECB"** — pattern-leaking mode. Never use
  ECB for multi-block data.
- **"We use RSA to encrypt large data"** — RSA is only for small
  (< key-size) messages. Use hybrid encryption.
- **"Our homegrown algorithm is secure because nobody knows how it
  works"** — security by obscurity. Discard.
