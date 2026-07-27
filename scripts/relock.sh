#!/usr/bin/env bash
# Regenerate the fork-only requirements-dev.lock from setup.cfg's `all` extra.
# Run after any upstream sync that changed dependencies, then commit the result.
set -euo pipefail
cd "$(dirname "$0")/.."
uv pip compile --universal --extra all setup.cfg -o requirements-dev.lock
echo "requirements-dev.lock regenerated. Review the diff and commit it."
