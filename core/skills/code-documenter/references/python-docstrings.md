---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/code-documenter/references/python-docstrings.md
ported-at: 2026-04-17
adapted: true
---

# Python docstrings

Pick **one** style per project and stick with it.

| Style | Good for | Renders with |
|---|---|---|
| Google | General app code, readable prose | Sphinx (napoleon), MkDocs (mkdocstrings) |
| NumPy | Scientific code, long param sections | Sphinx (napoleon) |
| Sphinx / reST | Heavy Sphinx-first projects | Sphinx |

## Google style (recommended default)

```python
def create_order(
    user_id: int,
    items: list[OrderItem],
    coupon: str | None = None,
) -> Order:
    """Create a new order for a user.

    Performs stock validation, applies any supplied coupon, charges the
    user's default payment method, and emits `Order.Created`.

    Args:
        user_id: ID of the purchasing user.
        items: Non-empty list of items to order.
        coupon: Optional coupon code. Must be valid and unexpired.

    Returns:
        The created `Order`, in status `pending_fulfillment`.

    Raises:
        OutOfStockError: If any line item is below requested quantity.
        InvalidCouponError: If `coupon` is unknown or expired.
        PaymentError: If the payment provider rejects the charge.

    Emits:
        Order.Created: Once the order is persisted and charged.

    Example:
        >>> order = create_order(
        ...     user_id=42,
        ...     items=[OrderItem(sku="A1", qty=2)],
        ...     coupon="WELCOME10",
        ... )
        >>> order.status
        'pending_fulfillment'
    """
```

Section order: summary → extended description → Args → Returns → Raises →
(optional) Emits / Yields / Warnings / Example.

## NumPy style

```python
def interpolate(
    x: np.ndarray, y: np.ndarray, kind: str = "linear"
) -> Callable[[float], float]:
    """Return a 1-D interpolator for the given samples.

    Parameters
    ----------
    x : np.ndarray
        Sample locations, strictly increasing, shape (n,).
    y : np.ndarray
        Sample values, shape (n,).
    kind : {"linear", "cubic"}, optional
        Interpolation kind. Defaults to "linear".

    Returns
    -------
    Callable[[float], float]
        Interpolator usable as `f(x0) -> y0`.

    Raises
    ------
    ValueError
        If `x` is not strictly increasing or `x` and `y` have different lengths.

    Notes
    -----
    Cubic interpolation requires at least 4 samples.
    """
```

## Sphinx / reST style

```python
def send_email(to: str, subject: str, body: str) -> None:
    """Send an email via the configured provider.

    :param to: RFC 5322 recipient address.
    :param subject: Email subject line.
    :param body: Plain-text or HTML body (autodetected).
    :raises InvalidAddressError: If `to` is not a valid address.
    :raises EmailProviderError: If the provider refuses the message.
    """
```

## Class docstrings

```python
class RateLimiter:
    """Token-bucket rate limiter.

    Suitable for per-key limits up to ~1 000 ops/sec. Uses a Redis backend
    for distributed operation.

    Attributes:
        rate: Tokens replenished per second.
        burst: Maximum tokens a key may hold.

    Example:
        >>> limiter = RateLimiter(rate=10, burst=100)
        >>> limiter.allow("user:42")
        True
    """
```

## Module docstrings

The first statement of a module. Short, high-level:

```python
"""Order domain — pricing, stock checks, and lifecycle transitions.

Do not import infra from this module.
"""
```

## Conventions

- One-line summary, then a blank line, then the body.
- Imperative mood ("Return the user", not "Returns the user").
- Describe behavior, not implementation.
- Document raised exceptions, not ones caught internally.
- Document side effects (I/O, events, global state) explicitly.
- Keep line length consistent with the rest of the file.

## Validation

- `python -m doctest path/to/file.py` — runs `>>>` blocks.
- `pytest --doctest-modules src/` — covers all modules.
- `ruff check --select D` — PEP 257 / pydocstyle rules.

## Common mistakes

- "This function does X" repeating the function name.
- Missing `Raises:` — document every exception in the public contract.
- Documenting private helpers in long detail; keep private docs brief.
- Drift between docstring and signature — validate on CI.
