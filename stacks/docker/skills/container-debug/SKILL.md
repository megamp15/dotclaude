---
name: container-debug
description: Investigate why a container is crashing, hanging, misbehaving, or slow
source: stacks/docker
---

# Container debugging

Use when: a container doesn't start, keeps restarting, or behaves
differently than expected. This is the "tight loop" debug skill;
follow `core/skills/debug-fix` for root-cause discipline.

## Step 0 — get the facts

Before touching anything:

```bash
docker ps -a                     # is it running? exited? restarting?
docker logs <id> --tail 200      # last 200 lines of logs
docker inspect <id> | less       # full state: exit code, env, mounts, networks
docker stats --no-stream <id>    # cpu, mem, i/o right now
```

Read the exit code from `docker inspect` — `State.ExitCode`:

- `0` — clean exit. Something told the process to stop.
- `1` — generic error. Check logs.
- `125` — docker daemon error (bad command, can't start).
- `126` — CMD not executable.
- `127` — CMD not found.
- `137` — SIGKILL. OOM or `docker kill`.
- `139` — segfault.
- `143` — SIGTERM. Usually a graceful shutdown or an orchestrator stop.

## Can't start

### Immediate crash on `up`

```bash
docker compose logs <service> --no-log-prefix
```

Common causes:

- **Missing env var** — `KeyError`, `undefined is not an object`, or a config loader bailing. Check `env_file:` and `environment:`.
- **Image doesn't have the CMD binary** — `exec: "python": executable file not found in $PATH`. Wrong image or wrong path.
- **Port already in use** — `bind: address already in use`. Another container or host process is on that port.
- **Volume permission** — container runs as non-root, host-mounted directory is owned by root. `chown` on host or adjust UID.

### Restart loop

If the container starts then dies immediately:

```bash
docker logs <id> --tail 50
```

Almost always one of:

- **Dependency not ready** — DB, cache, message broker. Add a healthcheck on the dep and `depends_on: { condition: service_healthy }`.
- **Init code throws** — bad config at startup. Usually visible in the first 20 log lines.
- **Entrypoint returns immediately** — `CMD` is a one-shot instead of a long-running process. Check that the container's main process actually blocks.

## Running but wrong

### "Connection refused" from another container

- Are they on the same network? `docker inspect <id> | grep -i network`.
- Is the target actually listening on `0.0.0.0`, not `127.0.0.1`? Inside the container, `127.0.0.1` is the container itself, not the host or a sibling.
- Is the port correct? Compose auto-exposes ports declared in `ports:`; inter-container traffic goes to the *container* port, not the host-published port.

### Can reach from host but not between containers

- Default bridge network vs custom network — containers on the default bridge can't resolve each other by name. Put them on a named network.

### Changes to code don't appear

- Is the code baked into the image, or bind-mounted? Images cache; you need to rebuild (`--no-cache` if the layer is stubborn).
- For bind mounts: is the mount actually covering the path you expect?
  ```bash
  docker exec <id> ls -la /app/src
  ```

### Slow

```bash
docker stats <id>              # live resource view
docker top <id>                # processes inside
docker exec <id> top           # same, from inside
```

- **CPU pinned** — inefficient code, or something looping on error. Profile inside.
- **Memory climbing** — leak or cache growing unbounded. Check for `mem_limit`; without one, OOM-kills by host.
- **Disk I/O** — often log spam filling overlay2. Check `logging:` limits.

## Inside the container

```bash
docker exec -it <id> sh        # or bash, depending on image
```

If the image has no shell (distroless):

```bash
docker run --rm -it --pid=container:<id> --net=container:<id> \
  --cap-add=SYS_PTRACE nicolaka/netshoot
```

`netshoot` mounts into the target container's namespaces with a full debug toolbelt (curl, dig, tcpdump, strace, lsof).

Common once inside:

- `env` — what env did this process actually see?
- `ps auxf` — what's actually running?
- `ls -la /proc/1/fd/` — what file descriptors are open?
- `cat /etc/resolv.conf` — DNS pointing where you expect?
- `getent hosts <service>` — does service discovery resolve?

## Network

```bash
docker network ls
docker network inspect <name>
```

- Is the service on the network?
- Is the DNS alias what you think?
- Can it ping / curl the target?

For TLS / HTTP issues inside containers, `netshoot` has `curl -v` and `openssl s_client`.

## Volumes

```bash
docker volume ls
docker volume inspect <name>
```

Check:

- Mount path matches what the service expects.
- Permissions (UID/GID) on the path match the container's user.
- For bind mounts on Docker Desktop (mac/windows), file system performance is slow; use a named volume where possible.

## Build cache

If builds are slow or producing unexpected images:

```bash
docker builder prune            # clear build cache
docker build --no-cache -t ...  # force full rebuild
docker build --progress=plain   # see every line of every layer
```

The `--progress=plain` flag is invaluable for "why is my build hanging on this layer" — you see stdout.

## Images and disk

```bash
docker system df                # overall usage
docker images                   # all images
docker image prune              # dangling only (safe)
docker system prune             # DANGEROUS if unscoped — never pass -a without thinking
```

## Post-fix checklist

- Root cause identified (don't stop at "restarting fixed it").
- Compose healthcheck or entrypoint change committed if the fix is config.
- Dockerfile change committed if the fix is image-level.
- Run the full up from clean state (`docker compose down && docker compose up`) to verify it's fixed for the next person who clones the repo.
