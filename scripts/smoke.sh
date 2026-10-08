#!/usr/bin/env sh
# The smoke test: proves the CE image is core and web assembled right (their
# own suites test each side), run the way a self-hoster runs it. Builds the
# image for this platform, lays out a self-hoster's folder in .smoke/ (the
# shipped docker-compose.yml, its secrets), runs it changed only by
# scripts/smoke.yml, then checks with curl: the web app on / and on deep links,
# the expected core, the setup, a file through WebDAV into the storage.
# Leaves nothing behind.
#   scripts/smoke.sh          the filesystem storage
#   scripts/smoke.sh --s3     with examples/s3-garage/: the storage on Garage,
#                             and its CORS rule
#   --keep                    leave the instance running (stop it with
#                             docker compose -p theca-smoke down -v)
# SMOKE_HOST: where the published ports are reached (CI: the Docker daemon's
# host); curl still says localhost (and garage), the only plain-HTTP origin it
# keeps the session's Secure cookie for. Needs Docker, curl, jq, openssl, and
# docker login git.pband.ch.
set -eu
cd "$(dirname "$0")/.."

s3=
keep=
for arg in "$@"; do
    case "$arg" in
    --s3) s3=1 ;;
    --keep) keep=1 ;;
    *)
        echo "usage: scripts/smoke.sh [--s3] [--keep]" >&2
        exit 2
        ;;
    esac
done

export SMOKE_HOST=${SMOKE_HOST:-localhost}
export SMOKE_PORT=${SMOKE_PORT:-8099}
export SMOKE_S3_PORT=${SMOKE_S3_PORT:-8098}
# Locally only on the loopback; a remote daemon (CI) must publish them.
[ "$SMOKE_HOST" = localhost ] && export SMOKE_BIND=127.0.0.1 || export SMOKE_BIND=0.0.0.0
# In the repository: a remote daemon sharing the workspace (CI) finds the
# files at the same path.
dir="$PWD/.smoke"
url=http://localhost:$SMOKE_PORT
export PUBLIC_URL=$url
curl() {
    command curl --connect-to "localhost:$SMOKE_PORT:$SMOKE_HOST:$SMOKE_PORT" \
        --connect-to "garage:3900:$SMOKE_HOST:$SMOKE_S3_PORT" "$@"
}
files="-f $dir/docker-compose.yml${s3:+ -f $dir/compose.s3.yml -f $PWD/scripts/smoke.s3.yml} -f $PWD/scripts/smoke.yml"
# shellcheck disable=SC2086 # $files: one word per file and flag
compose() { docker compose --progress quiet -p theca-smoke $files "$@"; }

core=$(scripts/core-version.sh)
echo "Building the image (core $core)..."
docker build -q --build-arg CORE_VERSION="$core" -t theca-ce:smoke . >/dev/null

# A self-hoster's folder: the compose (and the example's files), secrets/ as
# the compose's header and the example's README say.
rm -rf "$dir"
mkdir -p "$dir/secrets"
cp docker-compose.yml "$dir/"
password=$(openssl rand -hex 24)
printf %s "$password" >"$dir/secrets/postgres_password"
printf postgres://theca:%s@postgres:5432/theca "$password" >"$dir/secrets/database_url"
openssl rand -hex 32 >"$dir/secrets/server.key"
openssl rand -hex 32 >"$dir/secrets/data.key"
if [ -n "$s3" ]; then
    cp examples/s3-garage/compose.s3.yml examples/s3-garage/garage.toml examples/s3-garage/garage-init.sh "$dir/"
    echo "GK$(openssl rand -hex 12)" >"$dir/secrets/s3_access_key"
    openssl rand -hex 32 >"$dir/secrets/s3_secret_key"
    openssl rand -hex 32 >"$dir/secrets/garage_rpc_secret"
    openssl rand -hex 32 >"$dir/secrets/garage_admin_token"
fi
chmod 644 "$dir"/secrets/*
[ -z "$s3" ] || chmod 600 "$dir"/secrets/garage_*

cleanup() {
    status=$?
    [ "$status" -eq 0 ] || compose logs theca ${s3:+garage-init} | tail -50
    compose down -v >/dev/null 2>&1
    rm -rf "$dir"
}
[ -n "$keep" ] || trap cleanup EXIT
compose up -d --wait --quiet-pull

fail() {
    echo "smoke test failed: $1" >&2
    exit 1
}
api() { # method path [json]
    curl -fsS -X "$1" -b "$dir/cookies" -c "$dir/cookies" -H 'Content-Type: application/json' \
        ${3:+-d "$3"} "$url/api/v1$2"
}

echo "Checking $url${s3:+ with S3}..."
# The web app's index.html on / and on any path the API doesn't use.
curl -fsS "$url/" | grep -q '/_app/immutable/entry/start\.' || fail "/ is not the web app"
curl -fsS "$url/some/deep/link" | grep -q '/_app/immutable/entry/start\.' || fail "a deep link is not the web app"
status=$(curl -s -o /dev/null -w '%{http_code}' "$url/api/v1/no-such-route")
[ "$status" = 404 ] || fail "an unknown API path answered $status, not 404"

server=$(curl -fsS "$url/api/version" | jq -r .server)
[ "$server" = "$core" ] || fail "the server is core $server, not $core"

if [ -n "$s3" ]; then
    # The URL browsers would use too (the storage has one host).
    storage='{"name": "garage", "implementation": "s3", "host": "http://garage:3900", "region": "garage",
        "bucket": "theca", "access_key_file": "/run/secrets/s3_access_key",
        "secret_key_file": "/run/secrets/s3_secret_key", "path_style": true}'
else
    storage='{"name": "local", "implementation": "filesystem", "path": "/data/files"}'
fi
email=admin@example.com
admin=$(openssl rand -hex 16)
api POST /setup "$(jq -n --arg e "$email" --arg p "$admin" --argjson s "$storage" \
    '{admin_email: $e, admin_password: $p, organization: "Smoke", storages: [$s]}')" >/dev/null || fail "the setup"
org=$(api POST /auth/login "$(jq -n --arg e "$email" --arg p "$admin" '{email: $e, password: $p}')" |
    jq -r '.organizations[0].organization')
api POST /libraries "$(jq -n --arg o "$org" '{organization: $o, name: "Files"}')" >/dev/null || fail "creating a library"
app=$(api POST /auth/app-passwords '{"name": "smoke"}' | jq -r .password)

# A file in and out through WebDAV: the storage is writable by the server.
head -c 3000000 /dev/urandom >"$dir/file"
curl -fsS -u "smoke:$app" -T "$dir/file" "$url/dav/Smoke/Files/file" || fail "WebDAV PUT"
curl -fsS -u "smoke:$app" -o "$dir/file.back" "$url/dav/Smoke/Files/file" || fail "WebDAV GET"
cmp -s "$dir/file" "$dir/file.back" || fail "the file came back different"

if [ -n "$s3" ]; then
    # The bucket's CORS rule, as a browser meets it: the preflight of a
    # presigned PUT from the app, then a GET whose ETag the page can read.
    preflight=$(curl -fsS -o /dev/null -D - -X OPTIONS -H "Origin: $url" -H "Access-Control-Request-Method: PUT" \
        -H "Access-Control-Request-Headers: x-amz-checksum-sha256,if-none-match" http://garage:3900/theca/chunks/x)
    printf %s "$preflight" | grep -qi "^access-control-allow-origin: $url" || fail "the bucket's preflight refuses the app"
    s3() { curl -fsS --aws-sigv4 "aws:amz:garage:s3" --user "$(cat "$dir/secrets/s3_access_key"):$(cat "$dir/secrets/s3_secret_key")" "$@"; }
    s3 -X PUT --data-binary cors http://garage:3900/theca/smoke-cors >/dev/null
    get=$(s3 -o /dev/null -D - -H "Origin: $url" http://garage:3900/theca/smoke-cors)
    s3 -X DELETE http://garage:3900/theca/smoke-cors >/dev/null
    printf %s "$get" | grep -qi "^access-control-expose-headers:.*etag" || fail "the bucket doesn't expose ETag to the app"
fi

echo "Smoke test passed${s3:+ with S3}: web $(sed -n 's/^ARG WEB_VERSION=//p' Dockerfile), core $core"
