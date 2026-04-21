---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/code-documenter/references/coverage-reports.md
ported-at: 2026-04-17
adapted: true
---

# Coverage reports

Every run of `code-documenter` ends with a coverage report. It is how the
user knows what's left to do.

## Minimum shape

```markdown
## Documentation coverage

**Scope:** <module or path>
**Format:** <Google docstrings / JSDoc / OpenAPI 3.1>
**Date:** <ISO date>

| Module | Public symbols | Documented | % |
|---|---:|---:|---:|
| src/api/orders | 12 | 12 | 100% |
| src/domain/orders | 22 | 20 | 91% |
| src/infra/db | 8 | 4 | 50% |
| **Total** | **42** | **36** | **86%** |

### Gaps
- `src/infra/db.retry_policy` — undocumented public fn.
- `src/domain/orders.cancel_reason` — missing `Raises:` section.

### Validation
- Python doctests: 14 passed, 0 failed.
- OpenAPI: 0 errors, 2 warnings (`redocly lint`).
```

## What counts as "documented"

A public symbol is documented when it has:

- A one-line summary.
- Parameter descriptions (unless none).
- A return description (unless `None`/`void`).
- `Raises:` / `@throws` for the public error contract.
- A runnable example for non-obvious APIs.

Missing any of these → count as "partial" and list under gaps, not as
"documented".

## Generating numbers

### Python

```bash
# Docstring presence (pydocstyle via ruff)
ruff check --select D src/ > docstyle.txt

# Count public symbols missing docs
python - <<'PY'
import ast, pathlib
roots = ["src"]
total = documented = 0
gaps = []
for r in roots:
    for path in pathlib.Path(r).rglob("*.py"):
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                if node.name.startswith("_"):
                    continue
                total += 1
                if ast.get_docstring(node):
                    documented += 1
                else:
                    gaps.append(f"{path}:{node.lineno}:{node.name}")
print(f"{documented}/{total} ({documented/total:.0%})")
print("\n".join(gaps[:20]))
PY
```

### TypeScript

```bash
# ESLint-jsdoc missing-jsdoc rule
npx eslint --no-eslintrc --rule '{"jsdoc/require-jsdoc":"error"}' \
  --plugin jsdoc src/
```

Or run TypeDoc and read its `--validation.notDocumented` output.

### OpenAPI

```bash
# Redocly: schema lint + stats
npx @redocly/cli lint openapi.yaml
npx @redocly/cli stats openapi.yaml
```

Stats give operation count, parameter count, schema count — sanity-check
before declaring coverage.

## Thresholds (suggested)

| Scope | Target | Failure threshold |
|---|---|---|
| Public library API | 100% | < 95% |
| Internal service API (OpenAPI) | 100% of routes, every response code | any missing response |
| Domain / app code | ≥ 80% | < 60% |
| Infra / glue | ≥ 50% | none — note, don't block |

## Gap triage

Group gaps into buckets:

1. **Critical** — public library symbol, route missing response codes,
   schema missing required `description`.
2. **High** — undocumented public function with non-obvious error path.
3. **Medium** — present but shallow (missing `Raises:` / `@throws`).
4. **Low** — internal helpers, generated code.

Fix critical and high within the session; list medium/low as follow-ups.

## Automating the report

- Store `coverage.md` at repo root or in `docs/coverage.md`.
- In CI, fail if coverage regresses (`diff` against last commit).
- For OpenAPI, commit `openapi.yaml` and check it for drift (`redocly
  diff` between branches).

## Anti-patterns

- Reporting "100% coverage" after adding empty `"""TODO"""` docstrings.
- Counting private helpers in the denominator.
- Skipping `Raises:` / `@throws` because "the happy path is documented".
- Treating generated docs as documentation (they're rendering, not content).
