#!/usr/bin/env sh
# Every CI check (the pipeline and the pre-push hook): the smoke test, the only
# one while this repository holds no code (scripts/smoke.sh).
set -eu
exec "$(dirname "$0")/smoke.sh"
