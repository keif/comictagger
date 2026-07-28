# Design: uv dev tooling + upstream-sync bot

**Date:** 2026-07-27
**Status:** Implemented

> **Revision note (post code-review):** Component B was redesigned during implementation.
> The original plan pushed a `sync/upstream-develop` branch and relied on the existing
> `push:` CI trigger for pre-merge testing. Code review found this both non-functional
> (pushes made with the built-in `GITHUB_TOKEN` do not trigger workflow runs) and
> insecure (forcing CI via a PAT-authenticated push would run unreviewed upstream
> workflows with access to repository secrets). The shipped design uses a **cross-fork
> pull request** instead. This document describes what was built; see the plan's
> "Post-review amendments" for the full deltas.

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
- **`build.yaml` triggers on both `pull_request:` and `push: branches: ['**']`.** But note
  the GitHub rule below: events created with the built-in `GITHUB_TOKEN` do not start new
  workflow runs, which is why the sync bot needs a cross-fork PR + a PAT to get CI.
- Our default branch is `develop`; upstream changes historically land on `develop` via
  merge commits.

## Component A — uv as dev tooling (zero packaging changes)

`setup.cfg`, `pyproject.toml`'s `build-system`, and `tox` remain **exactly as upstream
ships them**. This is the key decision: it guarantees upstream merges never conflict on
packaging, and `tox run -m build` still gives release parity.

### Developer workflow

```bash
uv venv
uv pip install -e '.[all]'   # app only
uv run comictagger
```

uv installs directly from `setup.cfg` (a valid setuptools PEP-517 project); no metadata
migration is required.

### Reproducible lock (fork-only)

- `requirements-dev.lock` is compiled from `requirements-dev.in`, which lists the editable
  project plus test tools:
  ```
  -e .[all]
  pytest>=7
  pytest-qt
  ```
- Compiled with `uv pip compile --universal requirements-dev.in -o requirements-dev.lock`
  (wrapped in `scripts/relock.sh`). The editable entry resolves to a portable `-e .`.
- `uv pip sync requirements-dev.lock` therefore yields a **full dev + test environment**
  (editable project + all extras + pytest/pytest-qt), not just runtime dependencies.
- The lock and `requirements-dev.in` are **fork-only artifacts** — upstream (tox-based)
  has no equivalent, so they never conflict. Regenerated after any dependency change.
- uv's native `uv.lock` is gitignored: it would require moving metadata into `[project]`
  (the full migration we ruled out), and `uv run` regenerates it as a byproduct.
- Rationale: `uv pip compile` is the tooling-only equivalent of a native lock.

### macOS ICU handling

`PyICU` is a C extension that builds against ICU. `docs/uv-dev.md` documents the `icu4c` +
`pkg-config` setup, mirroring CI at `build.yaml:66-80`. On modern Homebrew the formula is
versioned (`icu4c@78`), so the doc resolves the prefix resiliently:

```bash
brew install pkg-config icu4c
ICU_PREFIX="$(brew --prefix icu4c 2>/dev/null || brew --prefix icu4c@78)"
export PKG_CONFIG_PATH="$ICU_PREFIX/lib/pkgconfig"
export PATH="$ICU_PREFIX/bin:$PATH"
```

### Surface area

- `docs/uv-dev.md` — dev setup + lock regeneration instructions.
- `requirements-dev.in` + `requirements-dev.lock` — fork-only lock source and output.
- `scripts/relock.sh` — thin lock-regeneration helper (with a `uv`-presence guard).
- `.gitignore` — ignores uv's native `uv.lock`.
- No edits to files upstream also edits.

## Component B — Scheduled upstream-sync PR bot (cross-fork model)

### One-time setup

- Add the upstream remote locally (for hand-resolving conflicts):
  ```bash
  git remote add upstream https://github.com/comictagger/comictagger.git
  ```
- Create a fine-grained PAT with **Pull requests: write** only, stored as the `SYNC_PAT`
  secret. Needed because a PR opened with the default `GITHUB_TOKEN` does not trigger
  `pull_request` CI. The workflow falls back to the default token if the secret is absent
  (the PR still opens, just without pre-merge CI).

### Workflow: `.github/workflows/sync-upstream.yaml`

- **Triggers:** `schedule` (weekly, Mondays 06:00 UTC) + `workflow_dispatch`.
- **Permissions:** `contents: read`, `pull-requests: write`. A `concurrency` group
  serializes overlapping runs.
- **Logic (single job, no checkout, no branch push):**
  1. Compare `develop...comictagger:develop` via the REST API to count how far upstream is
     ahead (using the default token, which has `contents: read`). Exit if zero.
  2. Check for an existing open sync PR with a server-side filter
     (`head=comictagger:develop&base=develop`) — idempotent and exhaustive.
  3. If none, open a **cross-fork PR** (`base: develop`, `head: comictagger:develop`) via
     `POST repos/{repo}/pulls` (the REST API accepts an org-owned cross-repo head where
     `gh pr create` may not). This call uses `SYNC_PAT` so the PR triggers CI.
- **Why cross-fork:** the PR head is upstream's own branch, so (a) nothing is pushed to the
  fork, (b) the PR tracks upstream live (new upstream commits update the same PR), and
  (c) pre-merge CI runs in the **fork `pull_request` context** — read-only token, **no
  access to repository secrets**. A compromised upstream commit cannot exfiltrate `SYNC_PAT`
  or any secret through this path.
- **Conflict policy:** the bot **never auto-resolves conflicts and never auto-merges.**
  - Clean merge → maintainer clicks Merge.
  - Conflict → you cannot push to upstream's branch, so merge locally and push to
    `develop` (`git fetch upstream && git merge upstream/develop`); the PR closes when no
    diff remains.

### Cadence

Weekly.

### Post-sync lock refresh

When a sync changes dependencies, regenerate `requirements-dev.lock` via `scripts/relock.sh`.
Kept as a documented manual/scripted step rather than baked into the bot — this keeps the
bot's responsibility to exactly one thing (surface upstream as a PR).

## Explicitly out of scope

- Rewriting `setup.cfg` into `pyproject.toml` `[project]`.
- Replacing or wrapping `tox`.
- Auto-merging sync PRs.
- Auto-resolving merge conflicts.

## Testing

- **Component A:** `uv venv` + `uv pip install -e '.[all]'` produces a working
  `comictagger` launch; `uv pip sync requirements-dev.lock` yields an env that imports the
  project + `pytest`; `uv run pytest` passes (435 passed at implementation).
- **Component B:** the cross-fork PR direction was verified against the live API (a 422
  "no commits between" confirms the direction is accepted, only the diff was empty). The
  workflow becomes dispatchable only once merged to `develop` (GitHub gates
  `workflow_dispatch` on the default branch); validate with a manual dispatch after merge.
