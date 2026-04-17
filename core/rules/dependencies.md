---
name: dependencies
description: Universal dependency hygiene — adding, pinning, auditing, removing
source: core
alwaysApply: true
---

# Dependencies

Every dependency is a cost: disk, bundle, attack surface, breakage risk,
transitive bloat. Treat them like an acquisition, not a purchase.

## Before adding a dependency

Ask:

1. **Is this in the standard library or already installed?** Both are free.
2. **Is it a trivial function I can write in a few lines?** `leftpad`-class dependencies are net-negative.
3. **Is it actively maintained?** Last commit > 18 months ago, no recent issue responses, single maintainer — red flags. Check weekly download trend, not just stars.
4. **Is the license compatible** with this project's license?
5. **What's its dependency tree?** Adding one thing can pull in fifty. Check with `npm ls`, `pip show`, `cargo tree`, `go mod graph`.
6. **Is there a simpler, smaller, better-established alternative?**

Write the answer in the commit or PR description for non-trivial additions.

## Pinning

- **Lock files are committed.** `package-lock.json`, `uv.lock`, `Cargo.lock`, `go.sum`, `Gemfile.lock`. Never in `.gitignore`.
- **Applications pin exact versions** via the lock. Libraries specify version ranges in their manifest, no lock shipped.
- **Distinguish direct from transitive.** Direct deps in `package.json`/`pyproject.toml` declare intent. Transitive are in the lock. Audit direct deps when upgrading; transitive ride along.
- **Never install floating `latest`** in CI or production. Builds must be reproducible.

## Updating

- **Regular cadence beats heroic bumps.** Weekly or monthly Dependabot/Renovate is easier than yearly catch-up.
- **Security updates first**, same day where possible. Everything else can batch.
- **Read the changelog**, not just the version number. `1.2.3 → 2.0.0` is a promise from the author that something broke; they get to be right about that.
- **Update one risky thing at a time.** Bundling a major framework bump with 20 other updates makes the inevitable rollback harder.

## Auditing

- Run the ecosystem's audit tool in CI: `npm audit`, `pip-audit`, `cargo audit`, `govulncheck`, `bundler-audit`.
- **Fail the build on high/critical** vulnerabilities by default. Allowlist specific known-false-positives with a comment explaining why.
- Review the audit output on every dependency change. Don't let "already had 37 warnings" be the excuse for adding the 38th.

## Pruning

- **Unused dependencies are bugs.** They pull in transitives, age, and hide real usage. Audit periodically with `depcheck`, `knip`, `pip-check`, or the language's equivalent.
- When removing a feature, remove its deps in the same commit.
- When a dep is used in one file for one function, reconsider — either inline it or keep it. "Used once" is a smell either way.

## Transitive risk

- **The security of your app is the union of every dep and every transitive dep.** A typo-squat or compromised maintainer anywhere in the tree is your problem.
- Prefer deps with small, well-known transitive trees over ones that pull in dozens of unfamiliar packages.
- Consider `npm ci` / `pip install --no-deps` patterns in production to guarantee only-locked installs.

## Package integrity

- **Verify checksums** — lock files with integrity hashes (`integrity` in npm lock, `hashes` in pip freeze output) are worth keeping.
- **Private registries** for internal packages. Public registries have had typo-squat and dependency-confusion attacks against names that matched internal package names.
- **Do not install from arbitrary URLs or git refs** without pinning to a commit hash and reviewing.

## Documentation

For non-obvious deps, leave a comment in the manifest explaining **why**
this one and not the alternatives. Future-you forgets the tradeoff, and
anyone auditing the tree will thank you.

```
# uvloop: ~2x throughput under load vs asyncio default loop; required by service SLO
uvloop~=0.22
```
