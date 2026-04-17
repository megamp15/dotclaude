---
name: dockerfile-best-practices
description: Dockerfile authoring rules — caching, security, size
source: stacks/docker
alwaysApply: false
globs: ["**/Dockerfile", "**/Dockerfile.*", "**/*.Dockerfile"]
---

# Dockerfile rules

Treat a Dockerfile like production code. It runs as root by default, it
ends up in everyone's supply chain, and it's painful to fix after deploy.

## Base image

- **Pin by digest** for production: `FROM python:3.12-slim@sha256:abc...`. Tags are mutable; an upstream retag silently changes what's in your image.
- **Use a slim or distroless variant** for the runtime stage. `python:3.12` is ~1GB; `python:3.12-slim` is ~150MB; `gcr.io/distroless/python3` is ~50MB with no shell.
- **Match the CPU architecture you'll deploy to.** Building on Apple Silicon and deploying to x86_64 requires `--platform=linux/amd64` or a buildx multi-arch build.

## Layer ordering (cache strategy)

Order from least to most volatile:

```dockerfile
FROM python:3.12-slim@sha256:...

# 1. System deps (rarely changes)
RUN apt-get update && \
    apt-get install -y --no-install-recommends gcc libpq-dev && \
    rm -rf /var/lib/apt/lists/*

# 2. Create non-root user (never changes)
RUN adduser --system --group app
WORKDIR /app

# 3. Dependency manifests only (changes on dep bump)
COPY --chown=app:app pyproject.toml uv.lock ./

# 4. Install deps (cached on manifest stability)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

# 5. Source (changes every commit)
COPY --chown=app:app src/ ./src/

USER app
CMD ["python", "-m", "src.main"]
```

Copying source before installing deps means every source edit re-installs everything. Don't.

## Multi-stage builds

Required when:

- You need a compiler/toolchain (Rust, Go, C extensions) that shouldn't be in the runtime image.
- You have dev dependencies (test frameworks, linters) that production doesn't need.
- You're publishing a base image someone else builds on.

```dockerfile
# --- builder ---
FROM node:20-slim AS builder
WORKDIR /build
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY . .
RUN pnpm build

# --- runtime ---
FROM node:20-slim
WORKDIR /app
RUN adduser --system --group app
COPY --from=builder --chown=app:app /build/dist ./dist
COPY --from=builder --chown=app:app /build/node_modules ./node_modules
USER app
CMD ["node", "dist/main.js"]
```

## `RUN` discipline

- **Combine related steps:** `apt-get update && apt-get install -y ... && rm -rf /var/lib/apt/lists/*` — as one `RUN`. Splitting them caches a stale index.
- **`--no-install-recommends`** on apt. Saves hundreds of MB.
- **Clean up in the same layer**:
  ```
  RUN curl -o /tmp/thing.tgz https://... \
      && tar -xzf /tmp/thing.tgz -C /opt \
      && rm /tmp/thing.tgz
  ```
  Removing the tarball in a *later* `RUN` doesn't shrink the image — the bytes are still in the earlier layer.
- **Don't over-combine.** A 20-line `RUN` is unreadable and a cache miss in any line invalidates the rest.

## Secrets

- **Never** in `ENV`, `ARG`, `RUN echo "..." > ...`, or any layer that persists.
- **Build-time secrets** use BuildKit mounts:
  ```
  # syntax=docker/dockerfile:1.4
  RUN --mount=type=secret,id=npm_token \
      NPM_TOKEN=$(cat /run/secrets/npm_token) npm install
  ```
  The token never lands in a layer.
- **Runtime secrets** come from env, mounted files, or the orchestrator's secret manager — not the image.

## User

- **Non-root by default.** Last `USER` line in the file should not be root.
- Create a dedicated user with known UID/GID if volume permissions matter:
  ```
  RUN groupadd -r app -g 1000 && useradd -r -u 1000 -g app app
  ```
  Stable UIDs mean bind mounts don't produce root-owned files on the host.

## Entry point

- **Use exec form.** `CMD ["python", "-m", "app"]`, `ENTRYPOINT ["/app/run.sh"]`. Shell form (`CMD python -m app`) wraps in `/bin/sh -c` and breaks signal forwarding.
- **Use `dumb-init` or `tini`** if the process doesn't reap children correctly. Orchestrators that send SIGTERM expect a graceful shutdown; many language runtimes swallow it without an init.

## Healthcheck

- Add `HEALTHCHECK` for long-running services:
  ```
  HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -f http://localhost:8080/healthz || exit 1
  ```
- Don't healthcheck the thing the service depends on; healthcheck the service itself. "Is the DB reachable?" is a readiness concern for an orchestrator, not the container.

## `.dockerignore`

Always present. Typical content:

```
.git
.gitignore
node_modules
__pycache__
*.pyc
.venv
.env
.env.*
dist
build
target
*.log
.DS_Store
.idea
.vscode
coverage
```

Without this, every build copies `.git/` (often 100MB+), local secrets, and node_modules you were going to reinstall anyway.

## Scan before merge

- Run Trivy / Grype / Snyk on the resulting image. Fail on high/critical with a CVE age > 30 days.
- Lint the Dockerfile: `hadolint`. Catches most of the above automatically.

## Common smells

| Smell | Why it's a problem |
|---|---|
| `FROM ubuntu:latest` | Mutable, bloated, no reason picked |
| `COPY . .` before `RUN pip install` | Busts cache on every source change |
| `USER root` at the end | Container is root — post-exploit amplifier |
| `ENV API_KEY=...` | Secret in an image layer forever |
| `RUN apt-get update` alone | Stale package index on later layers |
| Missing `--no-install-recommends` | Hundreds of MB of unneeded packages |
| No `.dockerignore` | Leaks, slow builds, bloated images |
| `CMD python app.py` (shell form) | Signals don't propagate |
| `:latest` on a service image | Non-reproducible builds and deploys |
