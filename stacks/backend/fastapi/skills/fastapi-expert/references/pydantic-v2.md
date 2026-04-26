---
source: stacks/fastapi
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/fastapi-expert/references/pydantic-v2.md
ported-at: 2026-04-17
adapted: true
---

# Pydantic V2

## `BaseModel` + `model_config`

```python
from pydantic import BaseModel, ConfigDict

class Item(BaseModel):
    model_config = ConfigDict(
        str_strip_whitespace=True,   # strip inputs
        extra="forbid",               # reject unknown fields
        from_attributes=True,         # allow ORM objects
        populate_by_name=True,        # allow alias AND name
        validate_assignment=True,     # re-validate on attribute set
    )
    sku: str
    qty: int
```

**Never** use `class Config` (V1 syntax).

## Validators

### Field validator

```python
from pydantic import field_validator

class SignupBody(BaseModel):
    password: str

    @field_validator("password")
    @classmethod
    def strong(cls, v: str) -> str:
        if len(v) < 8: raise ValueError("min 8 chars")
        return v
```

`@classmethod` is required. `mode="before"` runs before type coercion;
`mode="after"` runs after (default).

### Model validator

```python
from pydantic import model_validator

class DateRange(BaseModel):
    start: datetime
    end: datetime

    @model_validator(mode="after")
    def order(self) -> "DateRange":
        if self.end < self.start: raise ValueError("end < start")
        return self
```

Use model validators for **cross-field** rules.

## Computed fields

```python
from pydantic import computed_field

class Order(BaseModel):
    items: list[LineItem]

    @computed_field
    @property
    def total(self) -> Decimal:
        return sum(i.subtotal for i in self.items)
```

Appear in serialized output. Useful for derived values the client should
see.

## Aliases + snake/camel case

```python
from pydantic import AliasGenerator, BaseModel, ConfigDict
from pydantic.alias_generators import to_camel

class Product(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
    )
    product_id: int
    display_name: str
```

Serializes as `{ productId, displayName }`; accepts either casing as
input.

## Discriminated unions

```python
from typing import Literal, Annotated, Union
from pydantic import Field

class CardPayment(BaseModel):
    type: Literal["card"] = "card"
    last4: str

class BankPayment(BaseModel):
    type: Literal["bank"] = "bank"
    account: str

Payment = Annotated[Union[CardPayment, BankPayment], Field(discriminator="type")]
```

Pydantic + FastAPI use the discriminator to dispatch serialization +
validation — cleanly typed polymorphism.

## `Field(...)` essentials

```python
from pydantic import Field

class User(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, repr=False)
    tags: list[str] = Field(default_factory=list, max_length=10)
    score: float = Field(ge=0.0, le=1.0, examples=[0.42])
```

- `min_length` / `max_length`, `ge` / `le`, `pattern` — declarative
  validation.
- `default_factory=list` for mutable defaults (never `default=[]`).
- `repr=False` for sensitive fields.
- `examples=[...]` flow into OpenAPI.

## Parsing + dumping

```python
# ORM row → response model
resp = UserResponse.model_validate(user_row)

# Dict → model
body = UserCreate.model_validate(some_dict)

# JSON string → model
body = UserCreate.model_validate_json(raw_str)

# Model → dict / JSON
d = body.model_dump(exclude_unset=True)
s = body.model_dump_json()
```

`exclude_unset=True` for PATCH semantics.
`exclude_none=True` to drop nulls.

## Secrets

```python
from pydantic import SecretStr

class Settings(BaseModel):
    db_password: SecretStr
# str(settings.db_password)           → "**********"
# settings.db_password.get_secret_value() → real value
```

Use `SecretStr` in settings to avoid accidental logging.

## V1 → V2 migration cheat sheet

| V1 | V2 |
|---|---|
| `class Config:` | `model_config = ConfigDict(...)` |
| `@validator("x")` | `@field_validator("x")` + `@classmethod` |
| `@root_validator` | `@model_validator(mode="before/after")` |
| `obj.dict()` | `obj.model_dump()` |
| `obj.json()` | `obj.model_dump_json()` |
| `Model.parse_obj(x)` | `Model.model_validate(x)` |
| `Model.parse_raw(s)` | `Model.model_validate_json(s)` |
| `orm_mode=True` | `from_attributes=True` |
| `allow_population_by_field_name=True` | `populate_by_name=True` |

## Common mistakes

- Reusing one model for input + output. Leaks internal fields.
- Forgetting `extra="forbid"` on input models. Silent extra fields.
- Mutable default `= []` instead of `default_factory=list`.
- Validators without `@classmethod` (V2 requires it).
- Using `Optional[int]` where `int | None` is cleaner.
- Putting secrets in repr-visible fields.
