---
name: fastapi-expert
description: Deep FastAPI expertise — Pydantic V2 schema design, dependency injection patterns (`Annotated`), async SQLAlchemy CRUD, OAuth2 + JWT auth flows, pytest-asyncio + httpx testing, and common Django/DRF → FastAPI migration paths. Extends the rules in `stacks/fastapi/rules/fastapi-patterns.md`.
source: stacks/fastapi
triggers: /fastapi-expert, FastAPI, APIRouter, Annotated dependency, Pydantic V2 schema, async SQLAlchemy, OAuth2, JWT, OpenAPI, pytest-asyncio, httpx, migrate Django to FastAPI
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/fastapi-expert
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# fastapi-expert

You design and implement FastAPI services. Baseline rules
(`Annotated`, `response_model`, no V1 syntax, no blocking) live in
`stacks/fastapi/rules/fastapi-patterns.md`. This skill is the deep-dive:
schema design, dependency injection at scale, auth, async data access,
testing, and migrations.

## When this skill is the right tool

- Designing a FastAPI service from scratch
- Refactoring a service's schema + dependency layering
- Implementing OAuth2 + JWT authentication end-to-end
- Wiring async SQLAlchemy 2.x with Alembic migrations
- Writing an async test suite with pytest-asyncio + httpx
- Migrating from Django/DRF to FastAPI

**Not for:**
- Baseline lint-style rules — see `fastapi-patterns.md`.
- API-design decisions (resources, versioning, error envelope) —
  `core/skills/architect` rest-api mode.
- Full-stack feature implementation — `core/skills/fullstack-guardian`.

## Core workflow

1. **Analyze.** Endpoints, data models, auth model, external integrations.
2. **Schema.** Pydantic V2 models — inputs, outputs, errors.
3. **Dependencies.** Build `Annotated` dependency chains (DB session,
   current user, admin guard, pagination).
4. **Routes.** One router per domain, declared error responses, typed
   return values.
5. **Data.** Async SQLAlchemy models + CRUD module; Alembic migrations.
6. **Security.** Password hashing, JWT, authorization at the right layer.
7. **Tests.** pytest-asyncio + httpx AsyncClient + DB fixtures.
8. **Docs.** Confirm `/docs` reflects the intended API surface.

## Schema design (Pydantic V2)

Separate **input**, **output**, and **internal** models. Don't reuse
one model for all three.

```python
# schemas/users.py
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

class _UserBase(BaseModel):
    email: EmailStr
    name: str | None = None

class UserCreate(_UserBase):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    password: str = Field(min_length=8, repr=False)

    @field_validator("password")
    @classmethod
    def strength(cls, v: str) -> str:
        if v.lower() in _COMMON_PASSWORDS:
            raise ValueError("password is too common")
        return v

class UserUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    name: str | None = None
    email: EmailStr | None = None

class UserResponse(_UserBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    created_at: datetime
```

Rules:
- Input models `extra="forbid"` — fail fast on unknown fields.
- Output models `from_attributes=True` — serialize ORM rows via
  `model_validate`.
- `Field(repr=False)` for sensitive fields.
- Private base class (`_UserBase`) for shared fields — not shared with
  callers.

See `references/pydantic-v2.md` for validators, computed fields, and
discriminated unions.

## Dependency injection at scale

Compose dependencies into reusable `Annotated` aliases:

```python
# deps.py
from typing import Annotated
from fastapi import Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.security.auth import get_current_user, require_admin
from app.models import User

DbDep = Annotated[AsyncSession, Depends(get_db)]
CurrentUserDep = Annotated[User, Depends(get_current_user)]
AdminDep = Annotated[User, Depends(require_admin)]


class Pagination(BaseModel):
    limit: int = 20
    offset: int = 0

def paginate(limit: int = 20, offset: int = 0) -> Pagination:
    return Pagination(limit=min(max(limit, 1), 100), offset=max(offset, 0))

PaginationDep = Annotated[Pagination, Depends(paginate)]
```

Use:

```python
@router.get("/", response_model=list[UserResponse])
async def list_users(db: DbDep, page: PaginationDep) -> list[UserResponse]:
    return await crud.list_users(db, limit=page.limit, offset=page.offset)

@router.delete("/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_user(user_id: int, db: DbDep, _: AdminDep) -> None:
    await crud.delete_user(db, user_id)
```

Sub-dependencies compose: `AdminDep` internally depends on
`CurrentUserDep`.

### Dependency scope

- **Request-scoped** dependency (normal `Depends`) — default, correct
  for sessions.
- **Startup/shutdown** singletons — use `app.state` or a framework like
  `dependency-injector`. Don't fake request scope for singletons.

## Auth — OAuth2 + JWT

```python
# security/hashing.py
from passlib.context import CryptContext
pwd = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_password(p: str) -> str: return pwd.hash(p)
def verify_password(p: str, hashed: str) -> bool: return pwd.verify(p, hashed)
```

```python
# security/jwt.py
from datetime import datetime, timedelta, timezone
from jose import JWTError, jwt
from app.config import settings

def make_access_token(sub: str, ttl: timedelta = timedelta(minutes=15)) -> str:
    return jwt.encode(
        {"sub": sub, "exp": datetime.now(timezone.utc) + ttl},
        settings.jwt_secret,
        algorithm="HS256",
    )

def decode_token(token: str) -> dict:
    return jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
```

```python
# security/deps.py
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from typing import Annotated

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")

async def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: DbDep,
) -> User:
    creds_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = decode_token(token)
    except JWTError as e:
        raise creds_exc from e
    sub: str | None = payload.get("sub")
    if not sub:
        raise creds_exc
    user = await crud.get_user_by_id(db, int(sub))
    if user is None or not user.is_active:
        raise creds_exc
    return user

async def require_admin(user: Annotated[User, Depends(get_current_user)]) -> User:
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="admin required")
    return user
```

Hardening checklist:
- Short-lived access token (10–15 min).
- Refresh token only if needed (separate route, device-bound).
- Lock down `jwt_secret` via settings; rotate on incident.
- Always return a generic 401 on token failure.
- Consider asymmetric keys (RS256) if tokens are issued by one service
  and verified by many.

See `references/authentication.md` for refresh tokens, OAuth2 flows,
scopes, and multi-tenant patterns.

## Async SQLAlchemy 2.x

```python
# models/user.py
from datetime import datetime
from sqlalchemy import String
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

class Base(DeclarativeBase): ...

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    hashed_password: Mapped[str]
    name: Mapped[str | None]
    is_active: Mapped[bool] = mapped_column(default=True)
    is_admin: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
```

```python
# crud/users.py
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import User
from app.schemas import UserCreate
from app.security.hashing import hash_password

async def get_user_by_email(db: AsyncSession, email: str) -> User | None:
    return (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()

async def create_user(db: AsyncSession, payload: UserCreate) -> User:
    user = User(
        email=payload.email,
        hashed_password=hash_password(payload.password),
        name=payload.name,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user
```

Rules:
- `Mapped[...]` annotations + `mapped_column(...)` — SQLAlchemy 2.x.
- `select(...)` (not legacy `Query`).
- `scalar_one_or_none` for "zero or one" queries.
- `await db.commit()` + `await db.refresh(row)` to pick up DB-assigned
  fields.
- `expire_on_commit=False` on session factory so ORM fields stay
  accessible after commit.

See `references/async-sqlalchemy.md` for relationships, eager loading,
bulk operations, and transaction patterns.

## Alembic

Initialize:

```bash
uv run alembic init -t async alembic
```

Key config (`alembic/env.py`):

```python
from sqlalchemy.ext.asyncio import async_engine_from_config
target_metadata = Base.metadata
# use async engine; run migrations with `asyncio.run(do_run_migrations)`
```

Workflow:

```bash
uv run alembic revision --autogenerate -m "add users table"
uv run alembic upgrade head
```

Review every autogenerated migration by hand — autogenerate misses
things like check constraints, enum changes, and default values.

## Testing

```python
# conftest.py
import pytest
from httpx import AsyncClient
from app.main import app
from app.database import get_db

@pytest.fixture
async def client(db_session):
    async def override_get_db():
        yield db_session
    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(app=app, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()
```

```python
# tests/test_users.py
import pytest

@pytest.mark.asyncio
async def test_create_user(client):
    res = await client.post("/users", json={
        "email": "a@b.com", "password": "str0ngPW!", "name": "Ada",
    })
    assert res.status_code == 201
    body = res.json()
    assert body["email"] == "a@b.com"
    assert "password" not in body
```

Rules:
- `pytest-asyncio` with `asyncio_mode = "auto"`.
- Override DB dependency with a transactional or per-test schema
  session.
- Make tests hermetic — no shared state between tests.
- Test error paths (401, 403, 404, 409, 422) — not just happy path.

See `references/testing-async.md` for fixtures, factory-boy patterns,
and mocking httpx clients.

## OpenAPI polish

- Title, description, version on `FastAPI(...)`.
- Tags per router.
- `responses={...}` on every route for non-2xx codes.
- Examples via `Field(..., examples=[...])`.
- `operationId` inferred from handler names — keep names stable.
- Lint in CI (`redocly lint` or `spectral lint`).

## Migrating from Django/DRF

| Django/DRF concept | FastAPI equivalent |
|---|---|
| `ModelSerializer` | Pydantic models (input/output/internal split) |
| `ViewSet` + routers | `APIRouter` with route methods |
| `permission_classes = [...]` | Dependency chain (`CurrentUserDep`, `AdminDep`) |
| `authentication_classes` | `OAuth2PasswordBearer` + `get_current_user` |
| Django ORM | Async SQLAlchemy + Alembic |
| `migrations/` app | Alembic `versions/` |
| `django-filter` | Query params via Pydantic models / Depends |
| Signals | Domain events + event bus; or explicit calls |
| `Middleware` | Starlette middleware (`app.add_middleware`) |
| `@login_required` | Dependency that raises 401 |
| Sync views | `async def` + async clients; don't port blocking calls |
| `BackgroundTask` | `BackgroundTasks` / Celery / RQ |
| `pytest-django` fixtures | `pytest-asyncio` + `httpx.AsyncClient` |
| `.env` via `django-environ` | `pydantic-settings` |

Migration recipe:
1. Stand up FastAPI alongside Django (shared DB or read-only replica).
2. Port read endpoints first — lower risk.
3. Write Pydantic response models from the existing serializers.
4. Move write endpoints with feature flags; dual-write or switchover.
5. Finally, retire Django app.

## References

| Topic | File |
|---|---|
| Pydantic V2 — schemas, validators, config, discriminated unions | `references/pydantic-v2.md` |
| Async SQLAlchemy 2.x — models, queries, relationships, Alembic | `references/async-sqlalchemy.md` |
| Endpoints + routing — APIRouter, dependencies, exception handlers | `references/endpoints-routing.md` |
| Authentication — OAuth2, JWT, refresh tokens, scopes | `references/authentication.md` |
| Testing — pytest-asyncio, httpx, fixtures, factories | `references/testing-async.md` |
| Django/DRF migration walkthrough | `references/migration-from-django.md` |

## See also

- Baseline FastAPI rules → `stacks/fastapi/rules/fastapi-patterns.md`
- Python rules → `stacks/python/`
- API-design decisions → `core/skills/architect` rest-api mode
- Full-stack flow → `core/skills/fullstack-guardian`
