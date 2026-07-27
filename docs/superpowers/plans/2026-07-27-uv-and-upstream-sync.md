# uv Dev Tooling + Upstream-Sync Bot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt `uv` for local development and add a scheduled GitHub Action that surfaces upstream `comictagger/comictagger` `develop` changes as reviewable PRs.

**Architecture:** Tooling-only uv adoption — `setup.cfg`/`tox` stay untouched as upstream's source of truth, so merges never conflict on packaging. A fork-only `requirements-dev.lock` (via `uv pip compile`) gives reproducible envs. A weekly `workflow_dispatch`-able Action force-updates a `sync/upstream-develop` branch to upstream's head and opens/refreshes a PR into `develop`; CI runs via the existing `push: '**'` trigger, so no PAT is needed.

**Tech Stack:** `uv` 0.11+, GitHub Actions, `gh` CLI, existing setuptools + tox packaging.

---

## Context the implementer needs

- Repo default branch is `develop`. `origin` = `keif/comictagger`. There is **no** `upstream` remote yet.
- Dependencies/extras/entry-points live in `setup.cfg` (`[options]`, `[options.extras_require]`), **not** in `pyproject.toml`. Do not move them.
- The `all` extra (`setup.cfg:79-87`) pulls GUI + archive + image plugins. That is the dev target.
- `PyICU` is a C extension needing system ICU. On macOS: `brew install icu4c pkg-config` and export `PKG_CONFIG_PATH`/`PATH` (see `build.yaml:66-80`).
- `build.yaml` runs on `pull_request:` **and** `push: branches: ['**']`. The push trigger is what gives sync branches CI coverage.
- `uv 0.11.19` and `gh 2.93.0` are already installed locally. `.venv` is already in `.gitignore` (line 128).

## File Structure

- Create: `requirements-dev.lock` — fork-only pinned dev environment (committed).
- Create: `scripts/relock.sh` — regenerates `requirements-dev.lock`.
- Create: `docs/uv-dev.md` — uv local-dev setup + lock regeneration.
- Create: `docs/upstream-sync.md` — how the sync bot works + conflict resolution.
- Create: `.github/workflows/sync-upstream.yaml` — the scheduled sync Action.
- No modifications to `setup.cfg`, `pyproject.toml`, `tox` config, or existing workflows.

---

### Task 1: Feature branch

**Files:** none (git only)

- [ ] **Step 1: Create and switch to the feature branch**

Run:
```bash
git checkout develop
git checkout -b feature/uv-and-upstream-sync
```
Expected: `Switched to a new branch 'feature/uv-and-upstream-sync'`

---

### Task 2: Verify uv dev install actually works (Component A smoke test)

This task produces no committed files — it proves the documented workflow works before we document it.

**Files:** none (creates gitignored `.venv/`)

- [ ] **Step 1: Export macOS ICU build env (macOS only)**

Run:
```bash
brew install icu4c pkg-config
export PKG_CONFIG_PATH="$(brew --prefix icu4c)/lib/pkgconfig"
export PATH="$(brew --prefix icu4c)/bin:$PATH"
```
Expected: `icu4c` and `pkg-config` present (already-installed is fine).

- [ ] **Step 2: Create the venv and install the project with all extras**

Run:
```bash
uv venv
uv pip install -e '.[all]'
```
Expected: resolves and installs including `PyQt6`, `pillow`, `pyicu`, `rarfile`, `py7zr`. No build error from `pyicu`.

- [ ] **Step 3: Verify the CLI entry point runs**

Run:
```bash
uv run comictagger --version
```
Expected: prints a version string, exit code 0.

- [ ] **Step 4: Verify the test suite runs**

Run:
```bash
uv pip install pytest pytest-qt
uv run pytest -q
```
Expected: tests collect and run (pre-existing `xfail`s are fine; no collection/import errors).

No commit — nothing tracked changed.

---

### Task 3: Generate the fork-only lock file

**Files:**
- Create: `requirements-dev.lock`

- [ ] **Step 1: Compile a universal lock from setup.cfg**

Run:
```bash
uv pip compile --universal --extra all setup.cfg -o requirements-dev.lock
```
Expected: writes `requirements-dev.lock`. If uv rejects `setup.cfg` as a source on this version, fall back to:
```bash
uv pip compile --universal --extra all pyproject.toml -o requirements-dev.lock
```
and if that yields no project deps (because `pyproject.toml` has no `[project]`), create a one-line `requirements.in` containing `-e .[all]` and compile that:
```bash
printf -- '-e .[all]\n' > requirements.in
uv pip compile --universal requirements.in -o requirements-dev.lock
rm requirements.in
```

- [ ] **Step 2: Verify the lock is populated and pinned**

Run:
```bash
grep -E '^(pyqt6|pillow|rarfile|beautifulsoup4)==' requirements-dev.lock
```
Expected: each line present with an `==` pin (case-insensitive match; adjust grep to `-i` if needed).

- [ ] **Step 3: Verify the lock installs cleanly into a throwaway env**

Run:
```bash
uv venv /tmp/ct-lock-check
VIRTUAL_ENV=/tmp/ct-lock-check uv pip sync requirements-dev.lock
rm -rf /tmp/ct-lock-check
```
Expected: sync completes with no resolution errors.

- [ ] **Step 4: Commit**

```bash
git add requirements-dev.lock
git commit -m "build: add fork-only requirements-dev.lock for uv"
```

---

### Task 4: Add the relock helper script

**Files:**
- Create: `scripts/relock.sh`

- [ ] **Step 1: Write the script**

Create `scripts/relock.sh`:
```bash
#!/usr/bin/env bash
# Regenerate the fork-only requirements-dev.lock from setup.cfg's `all` extra.
# Run after any upstream sync that changed dependencies, then commit the result.
set -euo pipefail
cd "$(dirname "$0")/.."
uv pip compile --universal --extra all setup.cfg -o requirements-dev.lock
echo "requirements-dev.lock regenerated. Review the diff and commit it."
```

- [ ] **Step 2: Make it executable and smoke-test it**

Run:
```bash
chmod +x scripts/relock.sh
./scripts/relock.sh
git diff --stat requirements-dev.lock
```
Expected: script runs clean; lock unchanged (or a benign diff) since it was just generated.

- [ ] **Step 3: Commit**

```bash
git add scripts/relock.sh
git commit -m "build: add relock.sh to regenerate requirements-dev.lock"
```

---

### Task 5: Write the uv dev-setup docs

**Files:**
- Create: `docs/uv-dev.md`

- [ ] **Step 1: Write the doc**

Create `docs/uv-dev.md`:
````markdown
# Local development with uv

This fork uses [uv](https://docs.astral.sh/uv/) for local development. Upstream's
packaging (`setup.cfg`, `tox`) is unchanged — uv is a faster runner/installer layered on
top, so upstream merges never conflict on packaging.

## One-time: system dependencies

`PyICU` is a C extension that builds against system ICU.

**macOS:**
```bash
brew install icu4c pkg-config
export PKG_CONFIG_PATH="$(brew --prefix icu4c)/lib/pkgconfig"
export PATH="$(brew --prefix icu4c)/bin:$PATH"
```
(Add the two `export` lines to your shell profile to persist them.)

**Linux (Debian/Ubuntu):**
```bash
sudo apt-get install pkg-config libicu-dev libqt6gui6
```

## Set up the environment

```bash
uv venv
uv pip install -e '.[all]'
```

Run the app or tests without activating the venv:
```bash
uv run comictagger
uv run pytest
```

## Reproducible environments

`requirements-dev.lock` is a fork-only, fully-pinned lock (it does not exist upstream, so
it never conflicts on merge). To install exactly what's pinned:
```bash
uv pip sync requirements-dev.lock
```

Regenerate it after any dependency change (including after merging an upstream sync that
touched `setup.cfg`):
```bash
./scripts/relock.sh
git add requirements-dev.lock && git commit -m "build: relock dev dependencies"
```

## Releases / parity with upstream

Building release artifacts still goes through upstream's tox pipeline:
```bash
tox run -m build
```
````

- [ ] **Step 2: Commit**

```bash
git add docs/uv-dev.md
git commit -m "docs: add uv local-development guide"
```

---

### Task 6: Write the sync-upstream workflow

**Files:**
- Create: `.github/workflows/sync-upstream.yaml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/sync-upstream.yaml`:
```yaml
name: Sync upstream develop

on:
  schedule:
    - cron: '0 6 * * 1'  # Mondays 06:00 UTC
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
          ref: develop

      - name: Configure git identity
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

      - name: Fetch upstream
        run: |
          git remote add upstream https://github.com/comictagger/comictagger.git
          git fetch upstream develop

      - name: Count new upstream commits
        id: check
        run: |
          count=$(git rev-list --count develop..upstream/develop)
          echo "count=$count" >> "$GITHUB_OUTPUT"
          echo "Found $count new upstream commit(s)."

      - name: Update sync branch (triggers CI via push)
        if: steps.check.outputs.count != '0'
        run: |
          git branch -f sync/upstream-develop upstream/develop
          git push --force origin sync/upstream-develop

      - name: Open or update sync PR
        if: steps.check.outputs.count != '0'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          git log --oneline --no-merges develop..upstream/develop > commits.txt || true
          {
            echo "Automated weekly sync from \`upstream/develop\`."
            echo
            echo "### New commits (${{ steps.check.outputs.count }})"
            echo '```'
            cat commits.txt
            echo '```'
            echo
            echo "**Merging:**"
            echo "- Clean → click **Merge**."
            echo "- Conflicts → \`git fetch origin && git checkout sync/upstream-develop\`, resolve, push."
            echo "- After merge: if dependencies changed, run \`./scripts/relock.sh\` and commit \`requirements-dev.lock\`."
          } > body.md
          existing=$(gh pr list --head sync/upstream-develop --base develop --state open --json number --jq '.[0].number')
          if [ -n "$existing" ]; then
            gh pr edit "$existing" \
              --title "Sync upstream develop (${{ steps.check.outputs.count }} commits)" \
              --body-file body.md
          else
            gh pr create \
              --base develop \
              --head sync/upstream-develop \
              --title "Sync upstream develop (${{ steps.check.outputs.count }} commits)" \
              --body-file body.md
          fi
```

- [ ] **Step 2: Lint the YAML locally**

Run:
```bash
python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/sync-upstream.yaml')); print('yaml ok')"
```
Expected: `yaml ok`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/sync-upstream.yaml
git commit -m "ci: add scheduled upstream-sync PR workflow"
```

---

### Task 7: Write the upstream-sync docs

**Files:**
- Create: `docs/upstream-sync.md`

- [ ] **Step 1: Write the doc**

Create `docs/upstream-sync.md`:
````markdown
# Staying in sync with upstream

This fork tracks [`comictagger/comictagger`](https://github.com/comictagger/comictagger)
`develop`.

## Automated sync PRs

`.github/workflows/sync-upstream.yaml` runs every Monday (and on-demand via the Actions
tab → "Sync upstream develop" → "Run workflow"). It:

1. Fetches `upstream/develop`.
2. Force-updates the `sync/upstream-develop` branch to upstream's head.
3. Opens (or refreshes) a PR into `develop` summarizing the new commits.

Pushing the branch fires the existing CI (`build.yaml` runs on `push` to any branch), so
the sync PR shows lint + test results for that exact commit — no personal access token
required.

## Merging a sync PR

- **Clean merge:** click **Merge** (a merge commit, matching this fork's history).
- **Conflicts:** GitHub flags the files. Resolve locally:
  ```bash
  git fetch origin
  git checkout sync/upstream-develop
  git merge develop      # or rebase, per preference
  # resolve conflicts, commit
  git push origin sync/upstream-develop
  ```
- **After merging:** if the sync changed dependencies (`setup.cfg`), regenerate the lock:
  ```bash
  ./scripts/relock.sh
  git add requirements-dev.lock && git commit -m "build: relock after upstream sync"
  ```

## One-time local setup (for resolving conflicts by hand)

```bash
git remote add upstream https://github.com/comictagger/comictagger.git
git fetch upstream
```
````

- [ ] **Step 2: Commit**

```bash
git add docs/upstream-sync.md
git commit -m "docs: document upstream-sync bot and conflict resolution"
```

---

### Task 8: Validate the workflow end-to-end

**Files:** none

- [ ] **Step 1: Push the feature branch**

Run:
```bash
git push -u origin feature/uv-and-upstream-sync
```
Expected: branch pushed.

- [ ] **Step 2: Trigger the workflow on the feature branch**

Run:
```bash
gh workflow run sync-upstream.yaml --ref feature/uv-and-upstream-sync
```
Expected: `Created workflow_dispatch event`. (Note: `workflow_dispatch` can target a
non-default branch as long as the workflow file exists on that ref.)

- [ ] **Step 3: Watch the run and confirm behavior**

Run:
```bash
gh run list --workflow=sync-upstream.yaml --limit 1
gh run watch
```
Expected: run succeeds. If upstream has commits ahead of our `develop`, a
`sync/upstream-develop` branch and a PR into `develop` are created; the PR shows CI checks
from the branch push. If upstream has no new commits, the run is a clean no-op.

- [ ] **Step 4: Confirm the PR (if one was created)**

Run:
```bash
gh pr list --head sync/upstream-develop
```
Expected: at most one open PR; re-running the workflow updates it rather than duplicating.

---

### Task 9: Open the integration PR

**Files:** none

- [ ] **Step 1: Open the PR into develop**

Run:
```bash
gh pr create --base develop --head feature/uv-and-upstream-sync \
  --title "Add uv dev tooling and upstream-sync bot" \
  --body "Implements docs/superpowers/specs/2026-07-27-uv-and-upstream-sync-design.md. Tooling-only uv adoption (setup.cfg/tox untouched), fork-only requirements-dev.lock, and a weekly upstream-sync PR workflow."
```
Expected: PR URL printed.

- [ ] **Step 2: Run the pre-merge review gate**

Per team policy, run `/codex review` on this branch before merging. `[P1]` findings block
the merge; `[P2]` are advisory.

---

## Self-Review

**Spec coverage:**
- uv dev workflow (`uv venv` / install / run) → Task 2, Task 5. ✓
- Fork-only `requirements-dev.lock` via `uv pip compile` → Task 3; relock helper → Task 4. ✓
- macOS ICU handling → Task 2 Step 1, Task 5. ✓
- `setup.cfg`/tox untouched → enforced by only creating new files; called out in File Structure. ✓
- Upstream remote (one-time) → documented in Task 7. ✓
- Weekly + `workflow_dispatch` sync workflow, `contents`/`pull-requests` perms, force-update branch, open/refresh PR, no auto-resolve/auto-merge → Task 6. ✓
- CI-via-push (no PAT) rationale → Task 6 workflow comment + Task 7 docs. ✓
- Weekly cadence → cron `0 6 * * 1` in Task 6. ✓
- Post-sync lock refresh as documented step → Task 5 + Task 7 + PR body. ✓
- Testing/validation of both components → Task 2 (A), Task 8 (B). ✓

**Placeholder scan:** No TBD/TODO; every code/doc step contains full content; lock-command fallbacks are concrete. ✓

**Consistency:** Branch name `sync/upstream-develop`, script `scripts/relock.sh`, and lock file `requirements-dev.lock` are used identically across the workflow, docs, and PR body. ✓
