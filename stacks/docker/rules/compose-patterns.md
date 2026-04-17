---
name: compose-patterns
description: docker-compose.yml rules — services, volumes, networks, dependencies
source: stacks/docker
alwaysApply: false
globs: ["**/docker-compose*.yml", "**/docker-compose*.yaml", "**/compose*.yml", "**/compose*.yaml"]
---

# Compose rules

Compose is great for local dev and small single-host deploys. For
production orchestration across hosts, prefer Swarm or Kubernetes. For
anything beyond a few containers, break into override files.

## File structure

- **`compose.yaml`** (new canonical name) or **`docker-compose.yml`** — one committed file per environment or one base + overrides.
- **Base + override pattern:**
  ```
  compose.yaml              # shared service definitions
  compose.override.yaml     # local-dev-only (gitignored or opt-in)
  compose.prod.yaml         # production overrides (if using compose in prod)
  ```
  Load with `docker compose -f compose.yaml -f compose.prod.yaml up`.
- **Version field is optional** in modern Compose (spec v2+). Omit or use `version: "3.9"` only if tooling demands it.

## Services

### Images and builds

- **Production:** `image: myservice:${TAG}` pointing at an immutable tag (commit SHA). Never rely on `latest`.
- **Dev:** `build:` with a context. Can also have `image:` to name the local build.
- **Explicitly set `platform`** if you need to cross-build: `platform: linux/amd64`.

### Ports

- **Bind to localhost** in dev to avoid accidental exposure:
  ```yaml
  ports:
    - "127.0.0.1:5432:5432"
  ```
- **Don't expose DB / cache ports to `0.0.0.0`** on a shared dev machine. Assume someone on the network is curious.
- **In production, publish only what must be external.** Inter-service comms should go over the Compose network, no published port needed.

### Environment

- **`env_file:`** for non-secret config: `.env`, `.env.dev`, etc.
- **`environment:`** for inline overrides — never for secrets in committed files.
- **Secrets:**
  - Swarm: use `secrets:` block with external secrets.
  - Non-swarm: mount a secrets file via `volumes:` or rely on the host's env.

### Resource limits

For production or memory-constrained dev hosts:

```yaml
deploy:
  resources:
    limits:
      memory: 512M
      cpus: "0.5"
    reservations:
      memory: 256M
```

Without limits, one leaky service OOMs the host.

### Restart policies

- `restart: unless-stopped` — most services.
- `restart: on-failure:3` — for one-shot jobs that might transient-fail.
- `restart: "no"` — dev-only; don't auto-restart while debugging a crash loop.

## Dependencies

**Always use `condition:`**. Without it, `depends_on` only waits for the container to *start*, not for the service to be *ready*.

```yaml
services:
  app:
    depends_on:
      db:
        condition: service_healthy
      cache:
        condition: service_started

  db:
    image: postgres:16@sha256:...
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 10
```

Without the healthcheck + condition, `app` starts while `db` is still initializing, crashes on first query, then the restart loop masks the real issue.

## Volumes

- **Named volumes for data:**
  ```yaml
  services:
    db:
      volumes:
        - pgdata:/var/lib/postgresql/data
  volumes:
    pgdata:
  ```
- **Bind mounts only for source during dev:**
  ```yaml
  services:
    app:
      volumes:
        - ./src:/app/src  # dev only — in override file, not base
  ```
- **Never bind-mount** `./data:/var/lib/...` for a database in production. One `rm -rf ./data` wipes it.
- **Read-only where possible:** `- ./config:/etc/config:ro`.
- **Avoid** `:/var/run/docker.sock` mounts unless the service genuinely orchestrates containers — it's root-on-host.

## Networks

Explicit is better:

```yaml
services:
  app:
    networks: [frontend, backend]
  db:
    networks: [backend]

networks:
  frontend:
  backend:
    internal: true  # no external access
```

- `internal: true` on the backend network keeps the DB reachable from `app` but not exposed to the host or outside world.
- Services on the same network reach each other by service name (`app` connects to `db`).
- Don't rely on the default bridge — it's there, but implicit dependencies are harder to audit.

## Logs

- **`logging:` with size limits** in production. Unbounded `json-file` fills the disk.
  ```yaml
  logging:
    driver: json-file
    options:
      max-size: "10m"
      max-file: "3"
  ```
- **Ship logs to a collector** (Loki, CloudWatch, Datadog) for multi-host deployments. Tailing `docker logs` is for debugging, not operations.

## Compose v. Swarm v. K8s — know the line

- **Compose** is for single-host, dev, simple single-box services.
- **Swarm** if you want Compose-like YAML and multi-host — but the ecosystem is thin and Docker Inc's investment has shifted.
- **Kubernetes** if you want production orchestration with an ecosystem. Higher operational cost; higher ceiling.

Don't stretch Compose into what it isn't. If you're writing 500 lines of YAML and 6 override files, you've outgrown it.

## Common smells

| Smell | Fix |
|---|---|
| `ports: ["5432:5432"]` on a DB in shared dev | Bind to `127.0.0.1` |
| `depends_on` without `condition:` | Add healthcheck + condition |
| `image: postgres` (no tag) | Pin the tag / digest |
| Secrets in committed `.env` | Use `.env.example` + real `.env` gitignored |
| Bind-mounted DB data dir | Use a named volume |
| No `logging:` limits | Disk fills, host dies |
| `version: "2"` | Drop it; modern Compose ignores / it's legacy |
| `restart: always` on dev | Use `unless-stopped`; `always` re-runs stopped containers on reboot |
