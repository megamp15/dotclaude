# Packaging Python with `uv`

`uv` is the default; `pip`, `pip-tools`, and `poetry` are not.

## Project layout

Adopt **src-layout** — it prevents accidental imports from the repo root
during tests and mirrors what the installed package looks like.

```
myproj/
├── pyproject.toml
├── uv.lock
├── README.md
├── src/
│   └── myproj/
│       ├── __init__.py
│       ├── app.py
│       ├── config.py
│       └── cli.py
└── tests/
    ├── conftest.py
    └── test_app.py
```

## `pyproject.toml` minimum

```toml
[project]
name = "myproj"
version = "0.1.0"
description = "Short one-line description"
readme = "README.md"
requires-python = ">=3.11"
authors = [{ name = "You", email = "you@example.com" }]
dependencies = [
    "httpx>=0.27",
    "pydantic>=2.6",
]

[project.optional-dependencies]
dev = [
    "pytest>=8",
    "pytest-asyncio>=0.23",
    "mypy>=1.10",
    "ruff>=0.5",
]

[project.scripts]
myproj = "myproj.cli:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/myproj"]

[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
select = ["E", "F", "I", "N", "UP", "B", "SIM", "RUF"]

[tool.mypy]
python_version = "3.11"
strict = true
warn_unreachable = true

[tool.pytest.ini_options]
asyncio_mode = "auto"
addopts = "-ra --strict-markers"
testpaths = ["tests"]
```

## `uv` workflow

```bash
uv init                          # scaffold a new project
uv add httpx pydantic            # add a runtime dep
uv add --dev pytest mypy ruff    # add a dev dep
uv remove requests               # remove a dep
uv lock                          # regenerate uv.lock
uv sync                          # install exactly what uv.lock says
uv sync --dev                    # install including dev deps
uv run pytest                    # run a command in the project env
uv run myproj --help             # entry point
uv tree                          # dependency tree
uv python install 3.12           # install a Python interpreter
```

Rules:

- Commit `uv.lock`. Always.
- Never mix `uv` with manual `pip install` in the same venv — the lockfile
  stops being the source of truth.
- `uv run <cmd>` implies `uv sync` first — you don't need to activate a venv.

## Entry points

CLI:

```toml
[project.scripts]
myproj = "myproj.cli:main"
```

Then `uv run myproj` calls `myproj.cli:main()` with no args.

Plugin discovery (rare):

```toml
[project.entry-points."myproj.plugins"]
postgres = "myproj_postgres:Plugin"
```

## Private / mirror indices

```toml
[[tool.uv.index]]
name = "internal"
url = "https://pkg.internal.example.com/simple/"
default = false      # only for packages that explicitly reference it

[tool.uv.sources]
mycorp-lib = { index = "internal" }
```

For auth, use `UV_INDEX_<NAME>_USERNAME` / `UV_INDEX_<NAME>_PASSWORD` env
vars — never commit credentials.

## Editable installs

For local development across repos:

```bash
uv pip install -e /path/to/sibling-pkg
```

Or as a project dependency (in `pyproject.toml`):

```toml
[tool.uv.sources]
sibling-pkg = { path = "../sibling-pkg", editable = true }
```

## Versioning

- Start at `0.1.0`. Use semver once the API is public.
- For libraries, bump on every release; for apps, bump when you tag.
- Consider `hatch-vcs` if you want version derived from git tags.

## Publishing

```bash
uv build                                            # produces dist/*.whl and dist/*.tar.gz
uv publish --token $PYPI_TOKEN dist/*               # push to PyPI
```

Pre-publish checklist:

- `README.md` renders on PyPI (Markdown, no GitHub-flavored admonitions).
- `LICENSE` file present.
- `python -m twine check dist/*` passes.
- Version bumped and tagged.
- `pyproject.toml` has `classifiers` (OSI license, Python versions).

## Type stubs for your package

Add a `py.typed` marker so downstream users get your types:

```
src/myproj/py.typed          # empty file
```

```toml
[tool.hatch.build.targets.wheel.force-include]
"src/myproj/py.typed" = "myproj/py.typed"
```

## Environment vs. application split

- **Library**: broad version ranges (`httpx>=0.27,<1`), no lockfile shipped.
- **Application / service**: pin upper bounds loosely, commit `uv.lock`.

Never pin exact versions in a library's dependencies — it makes conflict
resolution impossible for consumers.
