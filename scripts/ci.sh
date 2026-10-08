#!/usr/bin/env sh
# Every CI check (the pipeline and the pre-push hook): the shipped compose is
# valid on its own, then the smoke test runs it (scripts/smoke.sh).
set -eu
cd "$(dirname "$0")/.."
PUBLIC_URL=https://cloud.example.com docker compose -f docker-compose.yml config -q
exec scripts/smoke.sh
