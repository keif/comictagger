# Staying in sync with upstream

This fork tracks [`comictagger/comictagger`](https://github.com/comictagger/comictagger)
`develop`.

## Automated sync PRs

`.github/workflows/sync-upstream.yaml` runs every Monday (and on-demand via the Actions
tab → "Sync upstream develop" → "Run workflow"). When upstream is ahead, it opens a
**cross-fork pull request** whose head is upstream's own `develop` branch
(`base: keif:develop`, `head: comictagger:develop`).

Because the PR head is upstream's live branch:

- The PR tracks upstream automatically — new upstream commits update the same PR, so the
  workflow only needs to open it once (it is idempotent and reuses an open sync PR).
- Nothing is pushed to this fork, so no unreviewed upstream code ever runs in a
  same-repository context with access to secrets.

## One-time: SYNC_PAT for pre-merge CI

A PR opened with the default `GITHUB_TOKEN` does not trigger `pull_request` CI (GitHub
suppresses workflow runs from token-created events). To get pre-merge CI, store a
fine-grained personal access token with **Pull requests: write** (no contents/push scope
needed) as a secret:

```bash
gh secret set SYNC_PAT --repo <owner>/comictagger
```

The workflow uses this token only to *open* the PR. If the secret is absent the workflow
still runs (it falls back to the default token), but the sync PR gets no pre-merge CI and
you rely on CI running post-merge on `develop`.

## Merging a sync PR

- **Clean merge:** review the diff, then click **Merge**.
- **Conflicts:** you cannot push to upstream's branch, so resolve locally and push to
  `develop` directly — the PR closes automatically once no diff remains:
  ```bash
  git fetch upstream
  git checkout develop
  git merge upstream/develop      # resolve conflicts, commit
  git push origin develop
  ```
- **After merging:** if the sync changed dependencies (`setup.cfg`), regenerate the lock:
  ```bash
  ./scripts/relock.sh
  git add requirements-dev.lock && git commit -m "build: relock after upstream sync"
  ```

## Security note: upstream CI runs without secrets

Pre-merge CI runs on the sync PR in the **fork `pull_request` context**: GitHub gives it a
read-only `GITHUB_TOKEN` and **no access to repository secrets** (including `SYNC_PAT`).
So even a compromised upstream commit that adds a malicious workflow cannot exfiltrate a
secret through this path. `SYNC_PAT` is only ever used by the sync job itself, which runs
trusted code from this fork's default branch — never upstream's code.

The bot never auto-merges. Review the diff before merging.

## One-time local setup (for resolving conflicts by hand)

```bash
git remote add upstream https://github.com/comictagger/comictagger.git
git fetch upstream
```
