---
source: stacks/fastapi
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/fastapi-expert/references/async-sqlalchemy.md
ported-at: 2026-04-17
adapted: true
---

# Async SQLAlchemy 2.x

## Engine + session

```python
# database.py
from collections.abc import AsyncIterator
from sqlalchemy.ext.asyncio import (
    AsyncSession, async_sessionmaker, create_async_engine,
)
from app.config import settings

engine = create_async_engine(
    settings.database_url,
    echo=False,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10,
)

SessionLocal = async_sessionmaker(engine, expire_on_commit=False)

async def get_db() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session
```

- `expire_on_commit=False` — access attributes after commit without
  re-loading.
- `pool_pre_ping=True` — detects dead connections after idle time.
- Tune `pool_size` to match worker count × concurrency.

## Models (2.x style)

```python
from datetime import datetime
from decimal import Decimal
from sqlalchemy import ForeignKey, String, Numeric
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

class Base(DeclarativeBase): ...

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)

    orders: Mapped[list["Order"]] = relationship(back_populates="user")

class Order(Base):
    __tablename__ = "orders"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    total: Mapped[Decimal] = mapped_column(Numeric(12, 2))
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)

    user: Mapped[User] = relationship(back_populates="orders")
```

Rules:
- `Mapped[T]` annotations — single source of truth for types.
- `mapped_column(...)` for column config (not bare `Column(...)` on new
  code).
- `relationship(...)` with `back_populates=` on both sides for
  bidirectional links.
- Put `index=True` on foreign keys and frequently filtered columns.

## Queries

### Single row

```python
from sqlalchemy import select

async def get_user_by_id(db: AsyncSession, user_id: int) -> User | None:
    return (
        await db.execute(select(User).where(User.id == user_id))
    ).scalar_one_or_none()
```

### List + pagination

```python
async def list_users(db: AsyncSession, limit: int, offset: int) -> list[User]:
    return (
        await db.execute(
            select(User).order_by(User.id).limit(limit).offset(offset)
        )
    ).scalars().all()
```

### Count

```python
from sqlalchemy import func

async def count_users(db: AsyncSession) -> int:
    return (await db.execute(select(func.count()).select_from(User))).scalar_one()
```

### Eager loading

```python
from sqlalchemy.orm import selectinload, joinedload

# selectinload: separate query per relationship (good for one-to-many)
await db.execute(
    select(User).options(selectinload(User.orders)).where(User.id == user_id)
)

# joinedload: one SQL statement with JOIN (good for many-to-one / one-to-one)
await db.execute(
    select(Order).options(joinedload(Order.user)).where(Order.id == order_id)
)
```

Rule: N+1 is a bug. Always load relationships you're going to touch.

### Insert + return generated id

```python
user = User(email=payload.email, hashed_password=...)
db.add(user)
await db.commit()
await db.refresh(user)  # populate id, defaults, server-side timestamps
```

### Update

```python
user = await get_user_by_id(db, user_id)
if user is None: raise HTTPException(404)
for k, v in payload.model_dump(exclude_unset=True).items():
    setattr(user, k, v)
await db.commit()
await db.refresh(user)
```

### Bulk update / delete (2.x)

```python
from sqlalchemy import update, delete

await db.execute(
    update(User).where(User.id.in_(ids)).values(is_active=False)
)
await db.execute(delete(Order).where(Order.status == "expired"))
await db.commit()
```

Bulk statements skip ORM unit-of-work — faster but you must invalidate
session state yourself if the objects are loaded.

## Transactions

Implicit transactions are default:

```python
async with SessionLocal() as session:
    ...  # operations
    await session.commit()
```

Explicit block for multiple commits / savepoints:

```python
async with session.begin():
    async with session.begin_nested():   # SAVEPOINT
        ...
    ...                                    # continue outer txn
```

Rollback on exception happens automatically with context managers.

## Performance patterns

### Don't open a session per call

Use one session per request (via `get_db`). Long-lived sessions across
handlers share state in confusing ways.

### Batch inserts

```python
db.add_all([User(email=e) for e in emails])
await db.commit()
```

Better than a loop of `add` + `commit`.

### Pagination — prefer keyset over offset

```python
# offset-based (simple, slow for deep pages)
select(User).order_by(User.id).offset(offset).limit(limit)

# keyset (stable, fast)
select(User).where(User.id > cursor).order_by(User.id).limit(limit)
```

For APIs, use keyset / cursor pagination once you cross a few thousand
rows.

### Avoid N+1

If you see queries logged in a loop, you loaded a relationship lazily.
Add `selectinload` or `joinedload` to the parent query.

## Alembic

### Init

```bash
uv run alembic init -t async alembic
```

### `alembic/env.py` (skeleton)

```python
from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from sqlalchemy.ext.asyncio import async_engine_from_config
from alembic import context
import asyncio
from app.models import Base  # imports all models so metadata is populated
from app.config import settings

config = context.config
config.set_main_option("sqlalchemy.url", settings.database_url)
fileConfig(config.config_file_name)

target_metadata = Base.metadata

async def run_async_migrations():
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()

def do_run_migrations(connection):
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()

asyncio.run(run_async_migrations())
```

### Workflow

```bash
uv run alembic revision --autogenerate -m "add orders table"
uv run alembic upgrade head
uv run alembic downgrade -1
uv run alembic current
uv run alembic history
```

Rule: **review autogenerated migrations by hand**. Autogenerate misses:
- Check constraints.
- Enum value changes.
- Default value changes.
- Index renames.
- Column reorders.

## Testing

Use a transactional fixture that rolls back after each test:

```python
@pytest.fixture
async def db_session(test_engine):
    async with test_engine.connect() as conn:
        txn = await conn.begin()
        session = AsyncSession(bind=conn, expire_on_commit=False)
        try:
            yield session
        finally:
            await session.close()
            await txn.rollback()
```

Override `get_db` in the FastAPI app to yield this session. Every test
starts with a clean slate.

## Common mistakes

- Using the legacy `.query()` API — use `select()`.
- Lazy-loading relationships in an async context — `MissingGreenlet`
  errors are this bug. Use `selectinload` / `joinedload`.
- Forgetting `await db.refresh(row)` after commit — id / defaults are
  stale.
- Sharing a session across requests or background tasks.
- Running `Base.metadata.create_all()` in prod — use Alembic.
- Putting business logic in ORM models. Keep them thin; domain logic
  elsewhere.
