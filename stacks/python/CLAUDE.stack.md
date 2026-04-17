## Python conventions

- Target Python 3.11+. Use modern typing (`list[int]`, not `List[int]`; `X | None`, not `Optional[X]`).
- Prefer `pathlib.Path` over `os.path`.
- Dependencies are managed with `uv` — never call `pip` directly.
- Format with `ruff format`; lint with `ruff check`. No `black`, no `isort`.
- Type-check with `mypy --strict` on library code.
- Tests live in `tests/`, run with `pytest`. Use `pytest.mark.parametrize` over loops in tests.
- No `print()` in library code — use `logging`.
- Dataclasses over dicts for structured data. `pydantic` only at I/O boundaries.
