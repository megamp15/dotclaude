---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/code-documenter/references/api-docs-fastapi-django.md
ported-at: 2026-04-17
adapted: true
---

# API docs — FastAPI + Django

## FastAPI

FastAPI generates OpenAPI automatically from type hints and Pydantic models.
Your job is to make what it generates **useful**.

### Baseline

```python
from fastapi import FastAPI

app = FastAPI(
    title="Orders Service",
    version="1.4.0",
    description="Orders, fulfillment, and payments API.",
    contact={"name": "Platform team", "email": "platform@example.com"},
    license_info={"name": "Proprietary"},
)
```

### Routers + tags

```python
from fastapi import APIRouter

router = APIRouter(prefix="/orders", tags=["Orders"])

@router.post(
    "",
    status_code=201,
    summary="Create an order",
    description="Validates stock, applies coupon, charges the user, emits Order.Created.",
    responses={
        400: {"description": "Validation error"},
        401: {"description": "Unauthenticated"},
        409: {"description": "Out of stock or invalid coupon"},
    },
)
async def create_order(body: CreateOrderRequest) -> Order:
    """Create an order.

    Business rules:
    - All items must be in stock.
    - Coupon, if provided, must be valid and unexpired.
    - On success, charges the user and emits `Order.Created`.
    """
```

### Request + response models with examples

```python
from pydantic import BaseModel, Field

class CreateOrderRequest(BaseModel):
    items: list[OrderItem] = Field(..., min_length=1, description="At least one item.")
    coupon: str | None = Field(None, description="Optional coupon code.")

    model_config = {
        "json_schema_extra": {
            "examples": [
                {"items": [{"sku": "A1", "qty": 2}], "coupon": "WELCOME10"}
            ]
        }
    }

class Order(BaseModel):
    id: str
    status: Literal["pending_fulfillment", "paid", "cancelled"]
    total: Decimal
```

### Error responses (RFC 7807-ish)

Return a consistent error envelope. Document it in a reusable `Error` model
and wire it into `responses=` for each route.

```python
class ErrorBody(BaseModel):
    type: str = "about:blank"
    title: str
    status: int
    code: str
    detail: str | None = None
    instance: str | None = None
```

### Auth docs

```python
from fastapi.security import OAuth2PasswordBearer

oauth2 = OAuth2PasswordBearer(tokenUrl="/auth/token", scopes={"read:orders": "Read orders"})
```

FastAPI renders the security scheme + scopes in `/docs` automatically.

### Validation

```bash
# Lint the generated schema
python -c "import json, app; print(json.dumps(app.app.openapi()))" > openapi.json
npx @redocly/cli lint openapi.json
```

### Rules

- Every route has `summary` + (optional) `description`.
- Every route declares error responses it emits.
- Group routes with `tags`.
- Use Pydantic `Field(..., description=..., examples=[...])` on public fields.
- Pin `version` and bump it on breaking changes (see `architect` rest-api mode).

## Django (DRF + drf-spectacular)

### Baseline

```python
# settings.py
REST_FRAMEWORK = {
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
}

SPECTACULAR_SETTINGS = {
    "TITLE": "Orders Service",
    "DESCRIPTION": "Orders, fulfillment, and payments API.",
    "VERSION": "1.4.0",
    "SERVE_INCLUDE_SCHEMA": False,
}
```

### Serializers

```python
class CreateOrderSerializer(serializers.Serializer):
    items = OrderItemSerializer(many=True, allow_empty=False, help_text="At least one item.")
    coupon = serializers.CharField(required=False, allow_blank=True, help_text="Coupon code.")
```

### Views

```python
from drf_spectacular.utils import extend_schema, OpenApiExample

@extend_schema(
    summary="Create an order",
    description="Validates stock, applies coupon, charges the user.",
    request=CreateOrderSerializer,
    responses={201: OrderSerializer, 400: ErrorSerializer, 409: ErrorSerializer},
    examples=[
        OpenApiExample(
            "Single item",
            value={"items": [{"sku": "A1", "qty": 2}], "coupon": "WELCOME10"},
            request_only=True,
        ),
    ],
)
class OrderCreate(APIView): ...
```

### Generating + serving

```python
# urls.py
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

urlpatterns += [
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs/", SpectacularSwaggerView.as_view(url_name="schema")),
]
```

Validation:

```bash
python manage.py spectacular --file schema.yml --validate --fail-on-warn
```

### Rules

- Serializers are the source of truth — keep `help_text` on every field.
- Use `@extend_schema` to name + describe every view.
- Declare all error responses, not just 200.
- Keep one `Error` serializer reused across endpoints.

## FastAPI vs. Django — picking a style

| Concern | FastAPI | Django/DRF |
|---|---|---|
| Schema source | Type hints + Pydantic | Serializers + `@extend_schema` |
| Auto-docs endpoint | `/docs`, `/redoc` | `/api/docs`, `/api/schema` |
| Breaking-change discipline | Semver the app `version=` | Version at URL or header |
| Common gap | Missing error responses | Missing examples |
