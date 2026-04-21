---
source: stacks/fastapi
---

# Stack: FastAPI

FastAPI conventions. Layers on top of `core/` and `stacks/python`
(always active for any FastAPI project). Read those first — this file
extends, it doesn't replace.

## Version assumption

- **FastAPI** current stable (0.110+).
- **Pydantic V2** — `BaseModel`, `model_config`, `field_validator`,
  `model_validator`. No V1 syntax (`@validator`, `class Config`).
- **Python 3.11+**, async everything.
- **SQLAlchemy 2.x async** when a relational DB is in play.
- **uv** for dependency management (per `stacks/python`).

## Project layout

```
src/app/
├── main.py             # FastAPI() instance + lifespan + routers
├── config.py           # settings via pydantic-settings
├── database.py         # async engine + session factory
├── schemas/            # Pydantic models (per domain)
├── models/             # SQLAlchemy ORM models
├── routers/            # APIRouter per domain
├── crud/               # data-access functions
├── security/           # auth, password hashing, JWT
├── deps.py             # shared dependency callables
└── main.py
tests/
├── conftest.py
└── test_*.py
```

One module per bounded context (`users`, `orders`, …). Per-domain files
inside `schemas/`, `models/`, `routers/`, `crud/` — not one giant module.

## Pydantic V2

```python
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

class UserCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    email: EmailStr
    password: str = Field(min_length=8, repr=False)
    name: str | None = None

    @field_validator("password")
    @classmethod
    def not_obvious(cls, v: str) -> str:
        if v.lower() in {"password", "12345678"}:
            raise ValueError("password is too weak")
        return v


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: EmailStr
    name: str | None = None
```

Rules:
- `model_config = ConfigDict(...)` — **never** `class Config`.
- `@field_validator` / `@model_validator` — **never** `@validator`.
- `from_attributes=True` on response models to serialize ORM objects.
- `extra="forbid"` on inputs to reject unknown fields.
- `Field(..., repr=False)` for sensitive fields (passwords, tokens) so
  they don't show up in repr/logs.

## Annotated dependencies

FastAPI 0.95+ introduced `Annotated[...]` dependency injection — use it.

```python
from typing import Annotated
from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.security.deps import get_current_user

DbDep = Annotated[AsyncSession, Depends(get_db)]
CurrentUserDep = Annotated[User, Depends(get_current_user)]
```

Then in routes:

```python
@router.get("/me", response_model=UserResponse)
async def read_me(current: CurrentUserDep) -> UserResponse:
    return UserResponse.model_validate(current)
```

This pattern beats `user: User = Depends(get_current_user)` — the type
alias is reusable and keeps signatures readable.

## Async all the way

- Every endpoint is `async def`.
- Every DB call is awaited (`await session.execute(...)`).
- Don't `asyncio.run()` or `.result()` inside a handler — that blocks
  the event loop.
- Use `httpx.AsyncClient` for outbound HTTP, not `requests`.
- CPU-bound work: offload (`BackgroundTasks`, Celery, RQ, or a process
  pool). Don't compute inside the handler.

## Routers

```python
from fastapi import APIRouter

router = APIRouter(prefix="/users", tags=["users"])

@router.get("/{user_id}", response_model=UserResponse)
async def get_user(user_id: int, db: DbDep) -> UserResponse:
    ...
```

- `prefix` + `tags` on every router.
- `response_model` on every route (or a typed return annotation with
  FastAPI's response inference).
- Group routers by domain, import them into `main.py` via
  `app.include_router(users_router)`.

## Error handling + responses

- Raise `HTTPException` for expected failures with a proper status code.
- Use `status.HTTP_*` constants for clarity.
- Declare non-2xx response shapes with `responses={...}`:

  ```python
  @router.post(
      "",
      status_code=status.HTTP_201_CREATED,
      response_model=OrderResponse,
      responses={
          400: {"model": ErrorBody, "description": "Validation error"},
          409: {"model": ErrorBody, "description": "Out of stock"},
      },
  )
  ```

- Central exception handlers (`@app.exception_handler(...)`) map domain
  exceptions to consistent JSON — see `core/skills/fullstack-guardian`
  for the error-handling strategy.

## Database (SQLAlchemy async)

```python
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

engine = create_async_engine(settings.database_url, echo=False, pool_pre_ping=True)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)

async def get_db() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session
```

- `expire_on_commit=False` keeps attributes accessible after commit.
- `pool_pre_ping=True` handles idle-connection drops.
- One session per request (yield from `get_db`). Don't reuse across
  requests.
- Use `AsyncSession.execute(select(...).where(...))`, not the legacy
  `.query()` API.

## Auth

- **JWT** via `python-jose` or `pyjwt` — pick one.
- **OAuth2PasswordBearer** for the standard Bearer-token flow.
- Hash passwords with `passlib[bcrypt]` or `argon2-cffi`. Never store
  plaintext; never log tokens or passwords.
- Centralize auth logic in `security/` — routes only call the
  dependency.

## Testing

- `pytest` + `pytest-asyncio` (`asyncio_mode = "auto"` in `pyproject.toml`).
- HTTP client: `httpx.AsyncClient(app=app, base_url="http://test")`.
- DB: run against a throwaway schema or transactional fixture; don't
  share state between tests.
- Run tests with `pytest -q` — warnings about un-awaited coroutines are
  bugs.

## Config

- `pydantic-settings` with `.env` support.
- Fail fast on missing required env vars.
- No `os.environ[...]` scattered around the app.

```python
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str
    jwt_secret: str
    cors_origins: list[str] = []
```

## Observability

- Structured logs (`structlog` or stdlib `logging` with `LOG_FORMAT=json`).
- Include `request_id`, `user_id` (when available), `path`, `status`,
  `duration_ms` per request.
- Metrics: `prometheus-fastapi-instrumentator` or OpenTelemetry.
- OpenTelemetry tracing: instrument FastAPI + SQLAlchemy + httpx.

## OpenAPI

- Title, description, version set on `FastAPI(...)`.
- Tags grouped logically (5–15 operations per tag is a good target).
- Examples on Pydantic fields via `Field(..., examples=[...])`.
- Lint the generated schema in CI:
  ```bash
  curl -s http://localhost:8000/openapi.json | npx @redocly/cli lint -
  ```

## Do not

- Do not use Pydantic V1 syntax.
- Do not block the event loop with sync DB or sync HTTP calls.
- Do not return raw ORM objects without a Pydantic response model.
- Do not hardcode secrets — `pydantic-settings` + env.
- Do not skip `response_model` (or typed return) on endpoints.
- Do not catch bare `Exception` in handlers and return 500 with details
  leaked.
- Do not run `uvicorn` as PID 1 in prod without a proper worker
  manager (use `gunicorn` + `uvicorn.workers.UvicornWorker` or
  `uvicorn --workers N` behind a reverse proxy).
