#!/usr/bin/env bash
# Regenerate the fork-only requirements-dev.lock from requirements-dev.in.
# Run after any upstream sync that changed dependencies, then commit the result.
set -euo pipefail
command -v uv >/dev/null || { echo "error: uv not found. See docs/uv-dev.md" >&2; exit 1; }
cd "$(dirname "$0")/.."
uv pip compile --universal requirements-dev.in -o requirements-dev.lock
echo "requirements-dev.lock regenerated. Review the diff and commit it."
