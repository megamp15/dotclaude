---
source: stacks/fastapi
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/fastapi-expert/references/authentication.md
ported-at: 2026-04-17
adapted: true
---

# Authentication — OAuth2 + JWT

## Password hashing

```python
from passlib.context import CryptContext

pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_password(plain: str) -> str:
    return pwd.hash(plain)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd.verify(plain, hashed)
```

- **Bcrypt** (cost ≥ 12) or **argon2** — both fine. Pick one, stick.
- Never log or print passwords.
- Keep `deprecated="auto"` so old hashes get re-hashed on successful
  verification as algorithms evolve.

## Password flow

```python
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm

router = APIRouter(prefix="/auth", tags=["auth"])

@router.post("/token")
async def login(
    form: Annotated[OAuth2PasswordRequestForm, Depends()],
    db: DbDep,
):
    user = await crud.get_user_by_email(db, form.username)
    if user is None or not verify_password(form.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="invalid credentials")
    access_token = make_access_token(str(user.id))
    return {"access_token": access_token, "token_type": "bearer"}
```

Rules:
- Return a **generic 401** on failure — don't distinguish "no such
  user" vs. "wrong password".
- Rate-limit this endpoint aggressively (per email + per IP).
- Consider lockout or CAPTCHA after repeated failures.

## JWT issuing + decoding

```python
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError

def make_access_token(sub: str, ttl: timedelta = timedelta(minutes=15)) -> str:
    return jwt.encode(
        {
            "sub": sub,
            "iat": datetime.now(timezone.utc),
            "exp": datetime.now(timezone.utc) + ttl,
            "type": "access",
        },
        settings.jwt_secret,
        algorithm="HS256",
    )

def decode_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
```

Token contents:
- `sub` (subject) — user id as string.
- `iat` / `exp` — issued at / expires at (UTC).
- `type` — `"access"` vs. `"refresh"`.
- Scopes or roles only if you genuinely use them; keep payload tiny.

Algorithms:
- **HS256** for single-service apps. Secret must be long + random.
- **RS256** / **EdDSA** for multi-service or third-party verification.

## Refresh tokens (when needed)

Refresh tokens let access tokens stay short-lived (good) while the user
stays logged in across sessions.

```python
def make_refresh_token(sub: str) -> str:
    return jwt.encode(
        {
            "sub": sub,
            "exp": datetime.now(timezone.utc) + timedelta(days=30),
            "type": "refresh",
            "jti": str(uuid.uuid4()),  # for server-side revocation list
        },
        settings.jwt_refresh_secret,
        algorithm="HS256",
    )

@router.post("/refresh")
async def refresh(refresh_token: str, db: DbDep):
    try:
        payload = jwt.decode(
            refresh_token, settings.jwt_refresh_secret, algorithms=["HS256"]
        )
    except JWTError:
        raise HTTPException(401, "invalid refresh token")
    if payload.get("type") != "refresh":
        raise HTTPException(401, "invalid refresh token")
    if await is_revoked(payload["jti"]):
        raise HTTPException(401, "token revoked")
    # Rotate: issue new access + new refresh, revoke the old refresh.
    await revoke(payload["jti"])
    sub = payload["sub"]
    return {
        "access_token": make_access_token(sub),
        "refresh_token": make_refresh_token(sub),
    }
```

Rules:
- **Rotate refresh tokens** on use — single-use semantics.
- **Track revocation** (`jti` in a Redis set) so compromised tokens can
  be killed.
- Store refresh tokens in an `HttpOnly`, `Secure`, `SameSite=Strict`
  cookie where possible — never in `localStorage`.
- Separate secret for refresh tokens (don't reuse access-token secret).

## Current-user dependency

```python
from fastapi.security import OAuth2PasswordBearer

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")

async def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: DbDep,
) -> User:
    creds_exc = HTTPException(
        status_code=401,
        detail="could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = decode_token(token)
    except JWTError as e:
        raise creds_exc from e
    if payload.get("type") != "access":
        raise creds_exc
    sub = payload.get("sub")
    if not sub:
        raise creds_exc
    user = await crud.get_user_by_id(db, int(sub))
    if user is None or not user.is_active:
        raise creds_exc
    return user

CurrentUserDep = Annotated[User, Depends(get_current_user)]
```

Always re-check `is_active` (or equivalent) — don't trust tokens issued
before a user was banned.

## Authorization (role / scope / tenant)

### Role-based

```python
async def require_role(required: str):
    async def checker(user: CurrentUserDep) -> User:
        if required not in user.roles:
            raise HTTPException(403, "insufficient role")
        return user
    return checker

AdminDep = Annotated[User, Depends(require_role("admin"))]
```

### Scope-based (OAuth2)

```python
oauth2_scheme = OAuth2PasswordBearer(
    tokenUrl="/auth/token",
    scopes={"read:orders": "Read orders", "write:orders": "Write orders"},
)

from fastapi.security import SecurityScopes

async def get_current_user_scoped(
    security_scopes: SecurityScopes,
    token: Annotated[str, Depends(oauth2_scheme)],
    db: DbDep,
) -> User:
    # validate token …
    token_scopes = payload.get("scopes", [])
    for s in security_scopes.scopes:
        if s not in token_scopes:
            raise HTTPException(403, f"missing scope {s}")
    return user
```

Route:

```python
from fastapi import Security

@router.get("/orders")
async def list_orders(user: Annotated[User, Security(get_current_user_scoped, scopes=["read:orders"])]): ...
```

### Tenant isolation

If your app is multi-tenant, **derive tenant from the token**, never
from client input:

```python
@router.get("/items/{id}")
async def get_item(id: int, user: CurrentUserDep, db: DbDep):
    item = await crud.get_item(db, id)
    if item is None or item.tenant_id != user.tenant_id:
        raise HTTPException(404)  # 404 hides existence across tenants
    return item
```

Never trust `X-Tenant-Id` or similar from the client.

## OAuth2 + OIDC (Google, GitHub, etc.)

Use **`authlib`** or **`oauth2-lib`**. The broad shape:

1. Redirect user to provider (`/auth/login/{provider}`).
2. Provider redirects back with an `code`.
3. Exchange `code` for access + ID tokens.
4. Fetch user info.
5. Find or create the local user; issue your app's own JWT.

Don't treat the provider's access token as your app's session — issue
your own.

## CSRF (when using cookies)

If you put the session in an `HttpOnly` cookie:
- Use `SameSite=Lax` (or `Strict`).
- Add CSRF tokens for state-changing requests, or require
  `Origin`/`Referer` checks.
- Verify the `Origin` header against an allowlist.

APIs using Bearer tokens in headers are immune to classic CSRF but
vulnerable to token theft — keep tokens out of JavaScript-accessible
storage.

## Security checklist

- [ ] Passwords hashed with bcrypt/argon2.
- [ ] Short-lived access tokens (≤ 15 min).
- [ ] Refresh tokens rotated + revocable (if used).
- [ ] Generic 401 on auth failures.
- [ ] Rate limits on login + refresh.
- [ ] `WWW-Authenticate: Bearer` on 401 responses.
- [ ] Active-status check on every request.
- [ ] Tenant/role/scope enforced **server-side**, derived from token.
- [ ] HTTPS only; HSTS set.
- [ ] No tokens in logs; no passwords ever.
