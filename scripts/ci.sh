#!/usr/bin/env sh
# Every CI check (the pipeline and the pre-push hook): the shipped compose is
# valid, alone and with each example; then the smoke test runs it, with the
# filesystem storage and with S3 (scripts/smoke.sh).
set -eu
cd "$(dirname "$0")/.."

# The variables the files require, with example values.
export PUBLIC_URL=https://cloud.example.com DOMAIN=cloud.example.com ACME_EMAIL=admin@example.com \
    AUTH_DOMAIN=auth.example.com OIDC_CALLBACK=https://cloud.example.com/api/v1/auth/oidc/x/callback
config() { docker compose -f docker-compose.yml "$@" config -q; }
config
config -f examples/s3-garage/compose.s3.yml
config -f examples/caddy/compose.caddy.yml
config -f examples/traefik/compose.traefik.yml
config -f examples/caddy/compose.caddy.yml -f examples/authelia/compose.authelia.yml
echo "Compose files valid"

scripts/smoke.sh
scripts/smoke.sh --s3
