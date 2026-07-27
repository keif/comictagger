# Design: uv dev tooling + upstream-sync bot

**Date:** 2026-07-27
**Status:** Approved

## Goal

Two related changes to the `keif/comictagger` fork:

1. Adopt `uv` for local development (faster venv + installs, reproducible lock).
2. Continuously track upstream `comictagger/comictagger` `develop` and surface its
   changes as reviewable pull requests into our `develop`.

The two goals are in tension: the more we rewrite packaging files, the harder every
future upstream merge becomes. The design resolves this by keeping `uv` adoption
**tooling-only** so upstream's packaging files stay byte-identical and merges stay clean.

## Constraints & context

- **No `upstream` remote exists yet.** Only `origin` → `keif/comictagger`.
- **Packaging lives in `setup.cfg`**, not `pyproject.toml`'s `[project]` table. Upstream
  declares all dependencies, extras, and entry points there and orchestrates via `tox`.
  Their CI (`build.yaml`, `package.yaml`) is tox-based.
- **`build.yaml` triggers on both `pull_request:` and `push: branches: ['**']`.** This is
  load-bearing for Component B (see below).
- Our default branch is `develop`; upstream changes historically land on `develop` via
  merge commits.

## Component A — uv as dev tooling (zero packaging changes)

`setup.cfg`, `pyproject.toml`'s `build-system`, and `tox` remain **exactly as upstream
ships them**. This is the key decision: it guarantees upstream merges never conflict on
packaging, and `tox run -m build` still gives release parity.

### Developer workflow

```bash
uv venv
uv pip install -e '.[all]'
uv run comictagger
```

uv installs directly from `setup.cfg` (a valid setuptools PEP-517 project); no metadata
migration is required.

### Reproducible lock (fork-only)

- Generate `requirements-dev.lock` with `uv pip compile` against the project metadata
  with `--extra all`.
- Developers reproduce the environment with `uv pip sync requirements-dev.lock`.
- The lock is a **fork-only artifact** — upstream (tox-based) has no equivalent, so it
  never conflicts. It is regenerated after any sync that changes dependencies.
- Rationale: a native `uv.lock` would require moving metadata into `[project]` (the full
  migration we ruled out). `uv pip compile` is the tooling-only equivalent.
- The exact compile invocation (source path / flags to read `setup.cfg` extras) is
  verified during implementation.

### macOS ICU handling

`PyICU` is a C extension that builds against ICU. Document the `icu4c` + `pkg-config` +
`PKG_CONFIG_PATH` / `PATH` setup, mirroring what CI already does at `build.yaml:66-80`:

```bash
brew install icu4c pkg-config
export PKG_CONFIG_PATH="$(brew --prefix icu4c)/lib/pkgconfig"
export PATH="$(brew --prefix icu4c)/bin:$PATH"
```

### Surface area

- `docs/uv-dev.md` — dev setup + lock regeneration instructions.
- Optionally one thin helper script for lock regeneration.
- No edits to files upstream also edits.

## Component B — Scheduled upstream-sync PR bot

### One-time setup

Add the upstream remote (documented; the Action fetches by URL and does not depend on a
persisted local remote):

```bash
git remote add upstream https://github.com/comictagger/comictagger.git
```

### Workflow: `.github/workflows/sync-upstream.yaml`

- **Triggers:** `schedule` (weekly cron) + `workflow_dispatch` (manual run button).
- **Permissions:** `contents: write`, `pull-requests: write` (built-in `GITHUB_TOKEN`, no
  PAT required).
- **Logic:**
  1. Check out `develop` at full depth.
  2. Fetch `upstream/develop` by URL.
  3. Force-update a `sync/upstream-develop` branch to upstream's head.
  4. Push the branch — this fires CI via the `push: '**'` trigger.
  5. Open or refresh a PR into `develop` using `gh`, with a body summarizing the new
     commits. Idempotent: reuse the existing open PR if one exists.
- **Conflict policy:** the bot **never auto-resolves conflicts and never auto-merges.**
  - Clean merge → maintainer clicks Merge (same merge-commit pattern already in history).
  - Conflict → GitHub flags the files; maintainer pulls the branch and resolves locally.

### Why CI still runs (design-critical)

PRs opened by the built-in `GITHUB_TOKEN` do **not** trigger `pull_request` workflows (an
anti-recursion safety measure). Normally that would leave a sync PR with zero checks.
Because `build.yaml` **also** runs on `push` to any branch, pushing `sync/upstream-develop`
triggers CI on that exact commit, and the results attach to the PR by commit SHA. This
gives us tested sync PRs **without** a personal access token.

### Cadence

Weekly.

### Post-sync lock refresh

When a sync changes dependencies, regenerate `requirements-dev.lock` via `uv pip compile`.
Kept as a documented manual/scripted step rather than baked into the bot — this keeps the
bot's responsibility to exactly one thing (surface upstream as a PR).

## Explicitly out of scope

- Rewriting `setup.cfg` into `pyproject.toml` `[project]`.
- Replacing or wrapping `tox`.
- Auto-merging sync PRs.
- Auto-resolving merge conflicts.

## Testing

- **Component A:** verify `uv venv` + `uv pip install -e '.[all]'` produces a working
  `comictagger` launch and that `uv run pytest` passes; verify `uv pip compile` yields a
  lock that `uv pip sync` installs cleanly.
- **Component B:** validate the workflow with `workflow_dispatch` (manual run) before
  relying on the schedule; confirm a `sync/*` push produces CI checks visible on the PR;
  confirm the idempotent path reuses an existing PR rather than erroring.
