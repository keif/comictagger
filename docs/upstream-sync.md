# Staying in sync with upstream

This fork tracks [`comictagger/comictagger`](https://github.com/comictagger/comictagger)
`develop`.

## Automated sync PRs

`.github/workflows/sync-upstream.yaml` runs every Monday (and on-demand via the Actions
tab → "Sync upstream develop" → "Run workflow"). It:

1. Fetches `upstream/develop`.
2. Force-updates the `sync/upstream-develop` branch to upstream's head.
3. Opens (or refreshes) a PR into `develop` summarizing the new commits.

For the sync PR to show **pre-merge** CI, a `SYNC_PAT` secret must be configured (see the
next section). Pushes made with the default `GITHUB_TOKEN` do not trigger workflow runs —
GitHub suppresses them to prevent recursion — so without the PAT the sync PR has no
pre-merge checks and CI runs only after you merge to `develop`.

## One-time: SYNC_PAT for pre-merge CI

Create a fine-grained personal access token scoped to this repository with
**Contents: write**, then store it as a secret:
```bash
gh secret set SYNC_PAT --repo <owner>/comictagger
```
The sync workflow checks out with this token, so its branch push triggers `build.yaml` on
the sync branch and the PR shows lint + test results for that exact commit. If the secret
is absent the workflow still runs (it falls back to the default token), but the sync PR
gets no pre-merge CI.

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

## Security note: pre-merge CI runs upstream code

When `SYNC_PAT` is configured, the sync branch push triggers `build.yaml`, which runs
upstream's code (`tox`, `pip install`, build steps) **before** a human reviews the diff.
This is an accepted, deliberate trade-off:

- The same upstream code runs in CI on `develop` after the sync PR is merged anyway, so
  pre-merge CI only moves execution earlier, it does not create new exposure.
- Blast radius is minimal: the fork holds **no repository secrets** other than the PAT,
  and the repo's default workflow token is **read-only** (the `build-and-test` job that
  runs upstream code declares no elevated permissions, so it inherits that read-only
  token — it cannot read `SYNC_PAT`, which is only exposed to the sync job's checkout).
- The bot never auto-merges. Review the diff — especially any changes under
  `.github/workflows/` or build scripts — before merging.

To stop running upstream code pre-review, delete the `SYNC_PAT` secret: the bot keeps
working and CI simply moves to post-merge (on `develop`, after your review).

## One-time local setup (for resolving conflicts by hand)

```bash
git remote add upstream https://github.com/comictagger/comictagger.git
git fetch upstream
```
