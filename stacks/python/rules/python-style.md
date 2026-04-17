---
name: python-style
description: Core Python style rules enforced across all Python files in this project
---

- No wildcard imports.
- Module-level constants are `UPPER_SNAKE_CASE`.
- Raise specific exceptions, never bare `Exception` or `BaseException`.
- Context managers over try/finally for resource cleanup.
- f-strings over `.format()` or `%`.
- Avoid `__all__` unless the module is a real public API surface.
- No mutable default arguments.
- Private helpers are prefixed with `_`; don't export them from `__init__.py`.
