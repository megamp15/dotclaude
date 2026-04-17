---
name: pytest-debug
description: Run and debug failing pytest tests in a Python project
---

# pytest-debug

When a test is failing or flaky, work through this checklist:

1. Run just the failing test with full traceback:
   `uv run pytest path/to/test.py::test_name -xvs --tb=long`
2. If it passes in isolation but fails in the suite, check for shared state
   (fixtures with `session`/`module` scope, env vars, tmpdir reuse).
3. Drop in `breakpoint()` and re-run with `-s` to land in pdb.
4. For flaky tests, run with `--count=20` (pytest-repeat) to reproduce.
5. Before declaring it fixed, run the full suite once: `uv run pytest`.
