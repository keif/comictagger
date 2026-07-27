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

## Security note: sync PRs run upstream code in CI

Pushing the `sync/upstream-develop` branch triggers the existing CI (`build.yaml` on
`push`), which runs upstream's code (`tox`, `pip install`, build steps) **before** a human
reviews the diff. This is an accepted, deliberate trade-off:

- The same upstream code runs in CI on `develop` after the sync PR is merged anyway, so
  push-CI only moves execution earlier, it does not create new exposure.
- Blast radius is minimal: the fork holds **no repository secrets**, and the repo's
  default workflow token is **read-only** (the `build-and-test` job that runs upstream
  code declares no elevated permissions, so it inherits that read-only token).
- The bot never auto-merges. Review the diff — especially any changes under
  `.github/workflows/` or build scripts — before merging.

If upstream trust ever changes, exclude the sync branch from push CI by setting the
`push` trigger in `build.yaml` to `branches: ['**', '!sync/**']` (note: that edits an
upstream-maintained file and removes pre-merge CI on sync PRs).

## One-time local setup (for resolving conflicts by hand)

```bash
git remote add upstream https://github.com/comictagger/comictagger.git
git fetch upstream
```
