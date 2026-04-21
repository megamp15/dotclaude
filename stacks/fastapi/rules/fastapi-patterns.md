---
source: stacks/fastapi
name: fastapi-patterns
description: FastAPI-specific patterns and anti-patterns that aren't covered by general Python/async style. Load when writing or reviewing FastAPI routes, Pydantic V2 schemas, async SQLAlchemy queries, or OAuth2/JWT auth.
triggers: fastapi, APIRouter, Depends, Annotated, pydantic v2, model_config, field_validator, AsyncSession, OAuth2PasswordBearer, BackgroundTasks, WebSocket, starlette, HTTPException, response_model
globs: ["**/*.py"]
---

# FastAPI patterns

Opinionated rules beyond generic Python style. See
`stacks/fastapi/CLAUDE.stack.md` for the baseline.

> **See also:** `stacks/fastapi/skills/fastapi-expert/` — deep-dive
> skill for schema design, dependency injection patterns, auth flows,
> async SQLAlchemy CRUD, and migration from Django.

## `Annotated` dependencies — always

```python
from typing import Annotated
from fastapi import Depends

DbDep = Annotated[AsyncSession, Depends(get_db)]
CurrentUserDep = Annotated[User, Depends(get_current_user)]

@router.get("/me")
async def me(user: CurrentUserDep) -> UserResponse: ...
```

Old style (`user: User = Depends(get_current_user)`) still works but is
inferior — type aliases don't apply, and re-use is awkward.

## Every route has `response_model` (or typed return)

```python
@router.get("/{user_id}", response_model=UserResponse)
async def get_user(...): ...
```

The `response_model` guarantees:
- Response is serialized through Pydantic (so internal fields can't leak).
- OpenAPI schema is correct.
- Type errors are caught at boundary, not at runtime in production.

## Pydantic V2 — canonical patterns

### Input with validation

```python
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

class SignupBody(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    email: EmailStr
    password: str = Field(min_length=8, repr=False)

    @field_validator("password")
    @classmethod
    def not_common(cls, v: str) -> str:
        if v.lower() in _COMMON_PASSWORDS:
            raise ValueError("password is too common")
        return v
```

### ORM → response

```python
class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: EmailStr
    name: str | None = None
```

Use `UserResponse.model_validate(user_row)` to serialize a SQLAlchemy
row.

### Partial updates

```python
class UserUpdate(BaseModel):
    name: str | None = None
    email: EmailStr | None = None

# In the handler
data = body.model_dump(exclude_unset=True)
for k, v in data.items():
    setattr(user, k, v)
```

`exclude_unset=True` is the correct knob for PATCH semantics.

## Anti-pattern: returning raw ORM rows

```python
# BAD — internal fields leak
@router.get("/{id}")
async def get(id: int, db: DbDep):
    return await crud.get_user(db, id)
```

Even if it "works", fields like `hashed_password`, `is_admin`, internal
timestamps, or relations can leak. Always a Pydantic response model.

## Anti-pattern: blocking calls in async handlers

```python
# BAD — blocks the event loop
@router.post("/sync")
async def sync_thing():
    requests.get("https://slow.example.com")   # sync HTTP
    time.sleep(5)                              # sync sleep
    row = cursor.execute("SELECT ...")          # sync DB
```

Any sync I/O in an `async def` handler pauses all concurrency on that
worker. Use:
- `httpx.AsyncClient` for HTTP.
- `asyncio.sleep` instead of `time.sleep`.
- Async SQLAlchemy (`AsyncSession`).
- Offload CPU-bound work: `BackgroundTasks`, Celery, or a process pool.

## Dependencies with parameters

```python
def pagination(limit: int = 20, offset: int = 0) -> Pagination:
    return Pagination(limit=min(limit, 100), offset=offset)

PaginationDep = Annotated[Pagination, Depends(pagination)]

@router.get("/")
async def list_users(db: DbDep, page: PaginationDep) -> list[UserResponse]: ...
```

Dependencies can take their own params — FastAPI wires query strings
through them automatically.

## Sub-dependencies

```python
async def get_current_user(token: Annotated[str, Depends(oauth2_scheme)]) -> User: ...
async def require_admin(user: Annotated[User, Depends(get_current_user)]) -> User:
    if not user.is_admin:
        raise HTTPException(403, "admin required")
    return user

AdminDep = Annotated[User, Depends(require_admin)]
```

Chain dependencies — cleaner than nested logic in routes.

## Background tasks

```python
from fastapi import BackgroundTasks

@router.post("/subscribe")
async def subscribe(email: EmailStr, background: BackgroundTasks, db: DbDep):
    await crud.subscribe(db, email)
    background.add_task(send_welcome_email, email)
    return {"ok": True}
```

Runs after the response is sent. Good for fire-and-forget work. For
heavier or reliable work, use Celery/RQ instead.

## Exception handlers

```python
from app.errors import DomainError, OutOfStockError

@app.exception_handler(OutOfStockError)
async def _(request, exc: OutOfStockError):
    return JSONResponse(
        status_code=409,
        content={
            "type": "about:blank",
            "title": "Item is out of stock",
            "status": 409,
            "code": "OUT_OF_STOCK",
            "detail": str(exc),
        },
    )

@app.exception_handler(DomainError)
async def _(request, exc: DomainError):
    return JSONResponse(status_code=400, content=...)
```

Map domain errors to consistent HTTP + JSON. Don't let raw driver
exceptions reach the client.

## Auth boilerplate

```python
from fastapi.security import OAuth2PasswordBearer
from jose import jwt, JWTError

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")

async def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: DbDep,
) -> User:
    creds_exc = HTTPException(401, "could not validate credentials")
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    except JWTError as e:
        raise creds_exc from e
    sub: str | None = payload.get("sub")
    if sub is None:
        raise creds_exc
    user = await crud.get_user_by_id(db, int(sub))
    if user is None or not user.is_active:
        raise creds_exc
    return user
```

Rules:
- Always return a generic 401 on token failures. Don't leak "user
  doesn't exist" vs. "bad token".
- Read JWT secret + algorithm from settings, not constants.
- Re-check user active state on every request — don't trust a token
  whose subject was deactivated.

## Rate limiting

FastAPI has no built-in rate limiter. Use:

- **`slowapi`** (Flask-Limiter for Starlette) — per-route decorators.
- Reverse proxy (nginx `limit_req`, Envoy) — when possible.
- Redis-backed custom limiter for precise per-user limits.

Always rate-limit auth endpoints and any public write endpoint.

## WebSocket essentials

```python
from fastapi import WebSocket, WebSocketDisconnect

@app.websocket("/ws")
async def ws(ws: WebSocket):
    await ws.accept()
    try:
        while True:
            msg = await ws.receive_text()
            await ws.send_text(f"echo: {msg}")
    except WebSocketDisconnect:
        pass
```

Rules:
- Auth **before** `accept()` — validate a token from query/header.
- Use a connection manager for fanout.
- Always handle `WebSocketDisconnect`.

## CORS

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_methods=["*"],
    allow_headers=["*"],
    allow_credentials=True,
)
```

- Explicit origin list — **never** `allow_origins=["*"]` with
  `allow_credentials=True` (the browser will ignore it and you'll chase
  ghosts).

## Do not

- Do not use Pydantic V1 syntax (`@validator`, `class Config`).
- Do not return ORM rows from routes without a response model.
- Do not block the event loop (sync HTTP, sync DB, `time.sleep`).
- Do not `except Exception:` and return 500 with internals leaked.
- Do not mix `APIRouter` prefix with `app.include_router(prefix=...)`
  — double prefix. Set prefix once.
- Do not rely on implicit status codes for mutation endpoints — set
  `status_code=201` on create, `204` on delete, etc.
