#!/usr/bin/env sh
# Every CI check: the shipped compose is valid, alone and with each example;
# then the smoke test runs it (scripts/smoke.sh): with two-way sync through
# rclone, then with every example (S3 behind Caddy with an Authelia login, S3
# behind Traefik).
#   scripts/ci.sh          everything (the pipeline)
#   scripts/ci.sh quick    the compose files and the plain smoke test (the
#                          pre-push hook: the examples' runs take minutes)
set -eu
cd "$(dirname "$0")/.."

case "${1:-all}" in
all | quick) ;;
*)
    echo "usage: scripts/ci.sh [quick]" >&2
    exit 2
    ;;
esac

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
if [ "${1:-all}" = quick ]; then
    exec scripts/smoke.sh
fi
scripts/smoke.sh --bisync
scripts/smoke.sh --s3 --caddy --authelia
scripts/smoke.sh --s3 --traefik
