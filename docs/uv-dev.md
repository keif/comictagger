# Local development with uv

This fork uses [uv](https://docs.astral.sh/uv/) for local development. Upstream's
packaging (`setup.cfg`, `tox`) is unchanged — uv is a faster runner/installer layered on
top, so upstream merges never conflict on packaging.

## One-time: system dependencies

`PyICU` is a C extension that builds against system ICU.

**macOS:**
```bash
brew install pkg-config icu4c
# icu4c is keg-only and versioned (e.g. icu4c@78), so point the build tools at it:
ICU_PREFIX="$(brew --prefix icu4c 2>/dev/null || brew --prefix icu4c@78)"
export PKG_CONFIG_PATH="$ICU_PREFIX/lib/pkgconfig"
export PATH="$ICU_PREFIX/bin:$PATH"
```
(Add the `export` lines to your shell profile to persist them.)

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
