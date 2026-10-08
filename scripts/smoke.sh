#!/usr/bin/env sh
# The smoke test: proves the CE image is core and web assembled right (their
# own suites test each side). Builds the image for this platform, runs it with
# Postgres (docker-compose.yml, as shipped, changed by scripts/smoke.yml), then checks with curl: the web app on / and on
# deep links, the expected core, the setup, a file through WebDAV into the
# filesystem storage. Leaves nothing behind.
#   scripts/smoke.sh          run it
#   scripts/smoke.sh --keep   leave the instance running (stop it with
#                             docker compose -p theca-smoke down -v)
# SMOKE_HOST: where the published port is reached (CI: the Docker daemon's
# host); curl still says localhost, the only plain-HTTP origin it keeps the
# session's Secure cookie for. Needs Docker, curl, jq, and docker login
# git.pband.ch.
set -eu
cd "$(dirname "$0")/.."

export SMOKE_HOST=${SMOKE_HOST:-localhost}
export SMOKE_PORT=${SMOKE_PORT:-8099}
# Locally only on the loopback; a remote daemon (CI) must publish it.
[ "$SMOKE_HOST" = localhost ] && export SMOKE_BIND=127.0.0.1 || export SMOKE_BIND=0.0.0.0
# In the repository: a remote daemon sharing the workspace (CI) finds the
# secret files at the same path.
export SMOKE_DIR="$PWD/.smoke"
url=http://localhost:$SMOKE_PORT
export PUBLIC_URL=$url
curl() { command curl --connect-to "localhost:$SMOKE_PORT:$SMOKE_HOST:$SMOKE_PORT" "$@"; }
compose() { docker compose --progress quiet -p theca-smoke -f docker-compose.yml -f scripts/smoke.yml "$@"; }

core=$(scripts/core-version.sh)
echo "Building the image (core $core)..."
docker build -q --build-arg CORE_VERSION="$core" -t theca-ce:smoke . >/dev/null

rm -rf "$SMOKE_DIR"
mkdir -p "$SMOKE_DIR"
password=$(openssl rand -hex 24)
printf %s "$password" >"$SMOKE_DIR/postgres_password"
printf postgres://theca:%s@postgres:5432/theca "$password" >"$SMOKE_DIR/database_url"
openssl rand -hex 32 >"$SMOKE_DIR/server.key"
openssl rand -hex 32 >"$SMOKE_DIR/data.key"
# Readable by the containers' users (the server's is uid 65532).
chmod 644 "$SMOKE_DIR"/*

cleanup() {
    status=$?
    [ "$status" -eq 0 ] || compose logs theca | tail -50
    compose down -v >/dev/null 2>&1
    rm -rf "$SMOKE_DIR"
}
[ "${1:-}" = --keep ] || trap cleanup EXIT
compose up -d --wait --quiet-pull

fail() {
    echo "smoke test failed: $1" >&2
    exit 1
}
api() { # method path [json]
    curl -fsS -X "$1" -b "$SMOKE_DIR/cookies" -c "$SMOKE_DIR/cookies" -H 'Content-Type: application/json' \
        ${3:+-d "$3"} "$url/api/v1$2"
}

echo "Checking $url..."
# The web app's index.html on / and on any path the API doesn't use.
curl -fsS "$url/" | grep -q '/_app/immutable/entry/start\.' || fail "/ is not the web app"
curl -fsS "$url/some/deep/link" | grep -q '/_app/immutable/entry/start\.' || fail "a deep link is not the web app"
status=$(curl -s -o /dev/null -w '%{http_code}' "$url/api/v1/no-such-route")
[ "$status" = 404 ] || fail "an unknown API path answered $status, not 404"

server=$(curl -fsS "$url/api/version" | jq -r .server)
[ "$server" = "$core" ] || fail "the server is core $server, not $core"

email=admin@example.com
admin=$(openssl rand -hex 16)
api POST /setup "$(jq -n --arg e "$email" --arg p "$admin" '{admin_email: $e, admin_password: $p,
    organization: "Smoke", storages: [{name: "local", implementation: "filesystem", path: "/data/files"}]}')" >/dev/null ||
    fail "the setup"
org=$(api POST /auth/login "$(jq -n --arg e "$email" --arg p "$admin" '{email: $e, password: $p}')" |
    jq -r '.organizations[0].organization')
api POST /libraries "$(jq -n --arg o "$org" '{organization: $o, name: "Files"}')" >/dev/null || fail "creating a library"
app=$(api POST /auth/app-passwords '{"name": "smoke"}' | jq -r .password)

# A file in and out through WebDAV: the storage on /data/files is writable.
head -c 3000000 /dev/urandom >"$SMOKE_DIR/file"
curl -fsS -u "smoke:$app" -T "$SMOKE_DIR/file" "$url/dav/Smoke/Files/file" || fail "WebDAV PUT"
curl -fsS -u "smoke:$app" -o "$SMOKE_DIR/file.back" "$url/dav/Smoke/Files/file" || fail "WebDAV GET"
cmp -s "$SMOKE_DIR/file" "$SMOKE_DIR/file.back" || fail "the file came back different"

echo "Smoke test passed: web $(sed -n 's/^ARG WEB_VERSION=//p' Dockerfile), core $core"
