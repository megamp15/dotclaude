<!-- source: stacks/docker -->

# Docker / Compose conventions

Applies to any project containing a `Dockerfile`, `docker-compose.yml`,
`docker-compose.yaml`, or equivalent. Kubernetes and Swarm are separate
stack layers that build on this one.

## Dockerfile baseline

- **Pin base images by digest** for production services: `FROM python:3.12-slim@sha256:...`. Tags are mutable. For dev/CI-only images, a version tag (`3.12-slim`) is fine — but never `:latest`.
- **Multi-stage builds** for compiled or toolchain-heavy languages. Build in one stage, copy artifacts into a minimal runtime image. Cuts image size 5–50× and removes compilers from the production attack surface.
- **Order layers by volatility** — least-changing at top, most-changing at bottom. System deps → language deps → source code → entrypoint. A source edit shouldn't re-pull apt packages.
- **Combine related `RUN` into one layer** with `&&` and `\`. Each `RUN` is a layer; layers have real cost. But don't over-combine — debugging a 20-command `RUN` is painful.
- **`.dockerignore` matters** — without it, every build copies `node_modules/`, `.git/`, `.venv/`, and local config. Big slowdown, sometimes a secret leak.

## Image content

- **Non-root user.** `RUN adduser --system app && USER app`. Containers running as root are a post-exploit accelerator.
- **No secrets at build time** — not in `ENV`, not in `ARG`, not in any layer. Use BuildKit secrets (`--mount=type=secret`) for build-time credentials (pip index, npm token) and runtime env for runtime secrets.
- **Minimal install.** `--no-install-recommends` on apt. No `curl`/`wget`/`git` in the final image unless the service actually uses them at runtime.
- **Clean up in the same layer** that installs: `apt-get update && apt-get install -y X && rm -rf /var/lib/apt/lists/*`. Clean-up in a later layer doesn't shrink the image.
- **Pin language dependency versions** via the language's lockfile (`requirements.txt`, `package-lock.json`, `go.sum`). Copy the lockfile first so dep install caches across code edits.

## Runtime

- **Single process per container.** Use a supervisor (pm2, supervisord) only when you genuinely have to. Split is easier to operate.
- **`CMD` uses exec form** (`CMD ["python", "-m", "app"]`) not shell form (`CMD python -m app`). Shell form doesn't forward signals cleanly; your container takes 10 seconds to die on SIGTERM.
- **Handle SIGTERM.** Services must close connections, drain queues, then exit. Bare Python/Node often ignores SIGTERM unless you wire it up.
- **HEALTHCHECK** — add one for long-running services. It's what orchestrators use to decide if the container is actually ready.

## Compose

- **Named volumes for data**, bind mounts only for source-during-dev. Bind-mounting `./data` to prod means losing data to a dev `rm -rf`.
- **Environment:** `env_file:` for non-secret config; `secrets:` (swarm) or external secret manager for secrets. Never `environment:` with literal secrets in committed YAML.
- **Depends_on with `condition`**, not bare `depends_on`. Without a condition it only waits for container start, not for the service to be ready.
  ```yaml
  depends_on:
    db:
      condition: service_healthy
  ```
- **Networks explicit.** The default bridge network lets containers reach each other by name, but explicit networks make intent clearer and let you isolate groups.
- **Resource limits** in production compose files: `mem_limit`, `cpus`. Otherwise a runaway container starves the host.

## Image tagging

- **Tag by immutable reference** for deploys: commit SHA (`myservice:a1b2c3d`) or semver + build number. Never deploy `:latest`.
- **Additional mutable tags are fine** for convenience: `:main`, `:prod`, `:v1.2` — but they're pointers to the SHA tag, not the deploy target itself.
- Retain production images. Don't prune blindly — rollback requires the previous image still existing somewhere.

## Caching

- **Order matters for cache hits:** copy dependency manifests first (`package.json`, `requirements.txt`, `go.mod`), install deps, *then* copy source. Source edits then hit a warm dep layer.
- **BuildKit cache mounts** for package manager state:
  ```
  RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt
  ```
  Massive speedup on local rebuilds; doesn't bloat the image.

## Security

- **Scan images in CI.** Trivy / Grype / Snyk. Fail the build on high/critical unfixable.
- **No package managers in prod images** when possible — use distroless or slim + no-install-recommends. Shell access to a breached container is worse if `apt`/`apk` is present.
- **Read-only root filesystem** (`read_only: true` in compose, `--read-only` at runtime). Forces any write path to a named volume or tmpfs; catches surprises.
- **Drop capabilities** you don't need (`cap_drop: [ALL]` then add back specifically).
- **seccomp + AppArmor/SELinux** profiles in production. Defaults are usually fine; custom profiles for high-risk workloads.

## Local dev ergonomics

- **Dev override file:** `docker-compose.override.yml` for local-only tweaks. Gitignored or committed separately.
- **Healthcheck + dep conditions** make `docker compose up` actually work the first time.
- **Named volumes for language caches** (`~/.cache/pip`, `/root/.npm`) so rebuilds don't re-download the world.

## What NOT to do

- `FROM ubuntu:latest`. Pick a specific base with a reason.
- `RUN apt-get update` on its own line — the next layer uses a stale cache.
- Committing `docker-compose.yml` with `image: postgres` (no version pin) for prod.
- Running as root in production.
- Bind-mounting `/var/run/docker.sock` into containers that don't genuinely need Docker-in-Docker. It's root-on-host.
- `ENV DEBUG=1` in a production image.
