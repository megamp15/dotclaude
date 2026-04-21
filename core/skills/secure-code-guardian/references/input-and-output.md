# Input validation and output encoding

## The golden rule

**Validate on input, encode on output.** Never skip either step,
and never conflate them.

- **Validation** = "is this data the right shape for my domain?"
- **Encoding** = "how do I emit this data into a target language
  safely?"

Same string has different dangers in SQL vs. HTML vs. a shell. The
string itself isn't "safe" or "dangerous" — its *context* is.

## Parsing, not validating

Borrowed from Alexis King: **parse** inputs into typed domain
values, don't *validate-then-pass-as-raw*.

```python
# Bad: easy to forget to re-check downstream.
def create_user(email: str) -> None:
    if not EMAIL_RE.match(email):
        raise ValueError
    # ... email is still `str`, used unchecked later
```

```python
# Good: schema produces a typed object. Once you have Email, it's safe.
class EmailAddress:
    def __init__(self, raw: str) -> None:
        if not _EMAIL_RE.match(raw):
            raise ValueError("invalid email")
        self.value = raw.lower()

def create_user(email: EmailAddress) -> None:
    # No re-check required.
    ...
```

In TypeScript: Zod/Valibot produce typed outputs. In Python:
Pydantic, attrs, `dataclass` with a validating `__post_init__`.

## Schema validation at every boundary

- HTTP request bodies, query, headers, cookies.
- Message queue payloads.
- File uploads (MIME type, size, content).
- Environment variables (parse once at boot).
- Third-party API responses you integrate with.

**Size limits** are part of validation:

- JSON body cap (common: 1 MB).
- Field-length caps.
- Array-length caps.
- File upload caps.

Without these, validation still accepts a 1 GB email and you OOM.

## SQL injection — parameterize

```python
# Never
cur.execute(f"SELECT * FROM users WHERE email = '{email}'")

# Always
cur.execute("SELECT * FROM users WHERE email = %s", [email])
```

ORMs do this for you — use them idiomatically. Raw SQL is fine,
just always with placeholders.

Table / column names can't be parameterized. If dynamic, **allowlist**:

```python
ALLOWED_SORT_COLS = {"created_at", "email", "name"}
if sort_by not in ALLOWED_SORT_COLS:
    raise ValueError
cur.execute(f"SELECT * FROM users ORDER BY {sort_by}", [])
```

## Shell / command injection

```python
# Never: `shell=True` with user input
subprocess.run(f"rm -rf {user_path}", shell=True)  # ← RCE

# Always: argv list
subprocess.run(["rm", "-rf", user_path], check=True)
```

Even the argv form requires validation (don't let `user_path` be
`../etc/passwd`). The argv form just prevents *metacharacter*
injection.

Alternatives:

- Use language APIs rather than shelling out. `shutil.rmtree(path)`
  instead of `rm -rf`.
- Use an allowlist of commands if you genuinely need to shell.

## Template / HTML injection (XSS)

### Server-side

- **Templates with auto-escape ON.** Jinja2 (`autoescape=True`),
  Django (default), ERB (default), Blade (default).
- Use context-specific escapers when emitting into `<script>`,
  `style`, attributes. Most template engines have these helpers.

### Client-side

- **React, Vue, Svelte, Solid** — auto-escape text. `dangerouslySetInnerHTML`
  / `v-html` / `@html` are the footgun.
- **Sanitize HTML** before rendering if users submit rich text:
  [`DOMPurify`](https://github.com/cure53/DOMPurify) is the
  standard.
- **Never trust attribute values** built from user input without
  encoding.

### Content-Security-Policy

Your last-line defense. A strong CSP prevents most XSS from
becoming disaster:

```
Content-Security-Policy:
  default-src 'self';
  script-src 'self' 'sha256-...';
  style-src 'self' 'unsafe-inline';
  img-src 'self' data: https:;
  frame-ancestors 'none';
  base-uri 'self';
  object-src 'none';
```

Start strict, add exceptions as needed. Use `report-uri` /
`report-to` during rollout.

## SSRF — Server-Side Request Forgery

Anywhere your server fetches a URL supplied by users (webhook
targets, image proxies, URL previews, OAuth callbacks):

### Defense

- **Allowlist domains** when possible.
- If not, resolve DNS first, then **block private / metadata ranges**:
  - `127.0.0.0/8`, `169.254.0.0/16` (AWS metadata!), `::1`,
    `fc00::/7`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.
- **Follow redirects carefully** — re-check the destination IP on
  every redirect, not just the first.
- **Disable HTTP methods** you don't need.
- **Short timeouts.** SSRF payloads often involve long-hanging
  requests to internal services.

Libraries: [`safe-url`](https://pypi.org/project/safeurl/) in
Python, [`ssrf-req-filter`](https://www.npmjs.com/package/ssrf-req-filter)
in Node.

### Cloud specifics

- AWS instance metadata service v2 (IMDSv2) is token-based; enforce
  `HttpTokens=required` on all EC2 instances.
- GCP and Azure have similar metadata endpoints; treat them as
  dangerous.

## Deserialization

Avoid deserializing untrusted data into **code-constructable**
formats:

- **Python** — `pickle`, `shelve`, `yaml.load` (use `safe_load`),
  `marshal`.
- **Java** — native `ObjectInputStream`. Entire CVE genres.
- **PHP** — `unserialize`.
- **Ruby** — YAML with unsafe mode.

If you control the protocol, use JSON or Protobuf. If you must
accept arbitrary object graphs, ask hard questions — there's
probably a vulnerability.

## File uploads

Checklist:

- **Size cap** per upload; per-user quota.
- **Content-type sniffing** — don't trust the client's `Content-Type`;
  verify by file magic (`python-magic`, `file(1)`).
- **Filename sanitization** — strip path traversal; regenerate on
  server (UUID name).
- **Store outside the web root** or behind an authenticated
  endpoint; don't serve uploads from a path under your app's
  origin.
- **Scan** if content is user-visible (ClamAV, cloud AV).
- **Process carefully** — image libraries have CVEs; convert via a
  subprocess with a timeout.
- **If the file is HTML/SVG**, serve with `Content-Disposition:
  attachment` or on a sandboxed origin.

## Redirect / open-redirect

`?next=...` or `?returnUrl=...` parameters used after login:

- **Allowlist** the set of destinations (paths, not full URLs).
- If full URLs are needed, match against a domain allowlist.
- Never blindly `302` to arbitrary input.

## Path traversal

When code reads / writes a file based on a path that includes user
input:

```python
# Bad
open(os.path.join("/var/app/uploads", user_filename))

# Good
base = Path("/var/app/uploads").resolve()
target = (base / user_filename).resolve()
if base not in target.parents:
    raise ValueError("path traversal")
open(target)
```

Resolve, then check the result is under the expected base.

## Regex DoS (ReDoS)

Backtracking regex on user input with pathological patterns =
catastrophic CPU. Example: `(a+)+$` fed `aaaaa...!`.

Defense:

- Use RE2 (Go default; `re2` library in Python/Node) — no
  catastrophic backtracking.
- Or restrict user input length.
- Or use simpler patterns. Avoid nested quantifiers.

## HTTP header smuggling / injection

Anywhere you set a header from user input (`Location`, cookies,
`Content-Disposition`):

- **Reject CR/LF** — no newlines in header values.
- Use the framework's API; don't manually concatenate headers.

## JSON-specific gotchas

- **Prototype pollution** in JS — never merge user input directly
  into an object literal. Use `Object.assign(Object.create(null), ...)`
  or sanitize keys.
- **Large numbers** — JS `Number` loses precision past 2^53; use
  BigInt or strings for IDs over that range.
- **Duplicate keys** behave differently per parser; validators may
  accept inputs downstream code rejects.
