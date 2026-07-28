# ComicTagger (keif fork)

Fork of [comictagger/comictagger](https://github.com/comictagger/comictagger). It tracks
upstream `develop` and adds fork-only developer tooling.

**Keep upstream merges clean:** put fork-only changes in **new files**. Do not edit
`setup.cfg`, `pyproject.toml`, `tox` config, or `README.md` — those are upstream-maintained
and editing them causes merge conflicts on every sync.

## Local development

This fork uses `uv` (tooling-only; upstream packaging is untouched). Full guide:
**[docs/uv-dev.md](docs/uv-dev.md)**.

```bash
uv venv
uv pip sync requirements-dev.lock   # full dev + test env (project + all extras + pytest)
uv run comictagger
uv run pytest
```

Regenerate the fork-only lock after a dependency change with `./scripts/relock.sh`.

## Staying in sync with upstream

A weekly GitHub Action (`.github/workflows/sync-upstream.yaml`) opens a cross-fork PR from
upstream's `develop` into ours, with pre-merge CI running safely in the fork
`pull_request` context. Setup (the one-time `SYNC_PAT` secret), how it works, and conflict
resolution: **[docs/upstream-sync.md](docs/upstream-sync.md)**.
