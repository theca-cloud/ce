#!/usr/bin/env sh
# The smoke test: proves the CE image is core and web assembled right (their
# own suites test each side), run the way a self-hoster runs it, with the
# examples around it. Builds the image for this platform, lays out a
# self-hoster's folder in .smoke/ (the shipped docker-compose.yml, the
# examples' files, the secrets their READMEs make), runs it changed only by
# scripts/smoke*.yml, then checks with curl: the web app on / and on deep
# links, the expected core, the setup, a file through WebDAV into the storage.
# Leaves nothing behind.
#   scripts/smoke.sh [options]
#   --s3        examples/s3-garage/: the storage on Garage, and its CORS rule
#   --caddy     examples/caddy/ in front, over HTTPS (the test's own CA instead
#   --traefik   of Let's Encrypt; the server trusts it, as a private one)
#   --authelia  examples/authelia/ (with --caddy): a login through it
#   --keep      leave it running (stop it: docker compose -p theca-smoke down -v)
# SMOKE_HOST: where the published ports are reached (CI: the Docker daemon's
# host); curl still uses the instance's names (localhost, garage, or the
# example.com domains behind a proxy). Needs Docker, curl, jq, openssl, and
# docker login git.pband.ch.
set -eu
cd "$(dirname "$0")/.."

s3= proxy= authelia= keep=
for arg in "$@"; do
    case "$arg" in
    --s3) s3=1 ;;
    --caddy) proxy=caddy ;;
    --traefik) proxy=traefik ;;
    --authelia) authelia=1 ;;
    --keep) keep=1 ;;
    *)
        echo "usage: scripts/smoke.sh [--s3] [--caddy | --traefik] [--authelia] [--keep]" >&2
        exit 2
        ;;
    esac
done
[ -z "$authelia" ] || [ "$proxy" = caddy ] || { echo "--authelia goes with --caddy" >&2; exit 2; }

export SMOKE_HOST=${SMOKE_HOST:-localhost}
export SMOKE_PORT=${SMOKE_PORT:-8099}
export SMOKE_S3_PORT=${SMOKE_S3_PORT:-8098}
export SMOKE_HTTPS_PORT=${SMOKE_HTTPS_PORT:-8443}
# Locally only on the loopback; a remote daemon (CI) must publish them.
[ "$SMOKE_HOST" = localhost ] && export SMOKE_BIND=127.0.0.1 || export SMOKE_BIND=0.0.0.0
# In the repository: a remote daemon sharing the workspace (CI) finds the
# files at the same path.
dir="$PWD/.smoke"
export SMOKE_TLS="$dir/tls"
if [ -n "$proxy" ]; then
    export DOMAIN=cloud.example.com S3_DOMAIN=s3.example.com AUTH_DOMAIN=auth.example.com ACME_EMAIL=smoke@example.com
    url=https://$DOMAIN
    s3url=https://$S3_DOMAIN
else
    url=http://localhost:$SMOKE_PORT
    s3url=http://garage:3900
fi
export PUBLIC_URL=$url
# Until the provider exists (the README's order): Authelia isn't started yet.
export OIDC_CALLBACK=$url/unknown-yet
curl() {
    command curl --connect-to "localhost:$SMOKE_PORT:$SMOKE_HOST:$SMOKE_PORT" \
        --connect-to "garage:3900:$SMOKE_HOST:$SMOKE_S3_PORT" \
        --connect-to "cloud.example.com:443:$SMOKE_HOST:$SMOKE_HTTPS_PORT" \
        --connect-to "s3.example.com:443:$SMOKE_HOST:$SMOKE_HTTPS_PORT" \
        --connect-to "auth.example.com:443:$SMOKE_HOST:$SMOKE_HTTPS_PORT" \
        ${proxy:+--cacert "$SMOKE_TLS/ca.pem"} "$@"
}
files="-f $dir/docker-compose.yml"
[ -z "$s3" ] || files="$files -f $dir/compose.s3.yml"
[ -z "$proxy" ] || files="$files -f $dir/compose.$proxy.yml"
[ -z "$authelia" ] || files="$files -f $dir/compose.authelia.yml"
[ -z "$s3" ] || files="$files -f $PWD/scripts/smoke.s3.yml"
[ -z "$proxy" ] || files="$files -f $PWD/scripts/smoke.proxy.yml -f $dir/smoke.$proxy.yml"
files="$files -f $PWD/scripts/smoke.yml"
# shellcheck disable=SC2086 # $files: one word per file and flag
compose() { docker compose --progress quiet -p theca-smoke $files "$@"; }

core=$(scripts/core-version.sh)
echo "Building the image (core $core)..."
docker build -q --build-arg CORE_VERSION="$core" -t theca-ce:smoke . >/dev/null

# A self-hoster's folder: the compose and the examples' files, secrets/ as the
# compose's header and the examples' READMEs say.
rm -rf "$dir"
mkdir -p "$dir/secrets"
cp docker-compose.yml "$dir/"
password=$(openssl rand -hex 24)
printf %s "$password" >"$dir/secrets/postgres_password"
printf postgres://theca:%s@postgres:5432/theca "$password" >"$dir/secrets/database_url"
openssl rand -hex 32 >"$dir/secrets/server.key"
openssl rand -hex 32 >"$dir/secrets/data.key"
chmod 644 "$dir"/secrets/*
if [ -n "$s3" ]; then
    cp examples/s3-garage/compose.s3.yml examples/s3-garage/garage.toml examples/s3-garage/garage-init.sh "$dir/"
    echo "GK$(openssl rand -hex 12)" >"$dir/secrets/s3_access_key"
    openssl rand -hex 32 >"$dir/secrets/s3_secret_key"
    openssl rand -hex 32 >"$dir/secrets/garage_rpc_secret"
    openssl rand -hex 32 >"$dir/secrets/garage_admin_token"
    chmod 644 "$dir"/secrets/s3_*
    chmod 600 "$dir"/secrets/garage_*
fi
if [ -n "$proxy" ]; then
    # The test's CA, and one certificate for every domain.
    mkdir -p "$SMOKE_TLS"
    openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=theca-smoke-ca -keyout "$SMOKE_TLS/ca.key" \
        -out "$SMOKE_TLS/ca.pem" -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign 2>/dev/null
    openssl req -newkey rsa:2048 -nodes -subj /CN=$DOMAIN -keyout "$SMOKE_TLS/cert.key" -out "$SMOKE_TLS/cert.csr" 2>/dev/null
    printf 'subjectAltName=DNS:%s,DNS:%s,DNS:%s\nextendedKeyUsage=serverAuth\n' "$DOMAIN" "$S3_DOMAIN" "$AUTH_DOMAIN" \
        >"$SMOKE_TLS/ext"
    openssl x509 -req -in "$SMOKE_TLS/cert.csr" -CA "$SMOKE_TLS/ca.pem" -CAkey "$SMOKE_TLS/ca.key" -CAcreateserial \
        -days 2 -out "$SMOKE_TLS/cert.pem" -extfile "$SMOKE_TLS/ext" 2>/dev/null
    chmod 644 "$SMOKE_TLS"/*
fi
if [ "$proxy" = caddy ]; then
    cp examples/caddy/compose.caddy.yml "$dir/"
    cp scripts/smoke.caddy.yml "$dir/"
    # The Caddyfile as its README says to use it (the S3 and Authelia blocks
    # uncommented), each site on the test's certificate.
    uncomment=
    [ -z "$s3" ] || uncomment='/S3_DOMAIN} {/,/^# }/s/^# \{0,1\}//'
    [ -z "$authelia" ] || uncomment="$uncomment
/AUTH_DOMAIN} {/,/^# }/s/^# \{0,1\}//"
    sed -e "$uncomment" -e '/^{\$[A-Z0-9_]*} {$/a\
	tls /smoke-tls/cert.pem /smoke-tls/cert.key' examples/caddy/Caddyfile >"$dir/Caddyfile"
fi
if [ "$proxy" = traefik ]; then
    cp examples/traefik/compose.traefik.yml "$dir/"
    # Its command as shipped, plus the test's certificate as the default one
    # (Let's Encrypt pointed nowhere, so it falls back on it).
    printf 'tls:\n  stores:\n    default:\n      defaultCertificate:\n        certFile: /smoke-tls/cert.pem\n        keyFile: /smoke-tls/cert.key\n' \
        >"$SMOKE_TLS/traefik.yml"
    command=$(docker compose -f "$dir/docker-compose.yml" -f "$dir/compose.traefik.yml" config --format json |
        jq -r '.services.traefik.command[] | "      - " + @json')
    {
        echo "# Generated by scripts/smoke.sh: examples/traefik/ for the test."
        echo "services:"
        echo "  traefik:"
        echo "    command: !override"
        echo "$command"
        echo "      - --providers.file.filename=/smoke-tls/traefik.yml"
        echo "      - --certificatesresolvers.letsencrypt.acme.caserver=https://localhost:1/directory"
        echo "    ports: !override"
        echo "      - \${SMOKE_BIND}:\${SMOKE_HTTPS_PORT}:443"
        echo "    volumes:"
        echo "      - \${SMOKE_TLS}:/smoke-tls:ro"
        echo "    networks:"
        echo "      default:"
        echo "        aliases: [cloud.example.com, s3.example.com, auth.example.com]"
        if [ -n "$s3" ]; then
            # Garage's labels, as the README gives them.
            echo "  garage:"
            echo "    labels:"
            echo "      - traefik.enable=true"
            echo "      - traefik.http.routers.garage.rule=Host(\`\${S3_DOMAIN}\`)"
            echo "      - traefik.http.routers.garage.entrypoints=websecure"
            echo "      - traefik.http.routers.garage.tls.certresolver=letsencrypt"
            echo "      - traefik.http.services.garage.loadbalancer.server.port=3900"
        fi
    } >"$dir/smoke.traefik.yml"
fi
if [ -n "$authelia" ]; then
    cp examples/authelia/compose.authelia.yml examples/authelia/authelia.yml "$dir/"
    for s in session_secret storage_key oidc_hmac reset_jwt; do openssl rand -hex 32 >"$dir/secrets/authelia_$s"; done
    openssl genrsa -out "$dir/secrets/authelia_jwks_key" 2048 2>/dev/null
    openssl rand -hex 32 >"$dir/secrets/oidc_client_secret"
    docker run --rm authelia/authelia:4.39 authelia crypto hash generate pbkdf2 --variant sha512 \
        --password "$(cat "$dir/secrets/oidc_client_secret")" | sed -n 's/^Digest: //p' >"$dir/secrets/oidc_client_secret_hash"
    chmod 600 "$dir"/secrets/authelia_* "$dir/secrets/oidc_client_secret_hash"
    chmod 644 "$dir/secrets/oidc_client_secret"
    # One user, with the admin's email: linked to the admin's account.
    oidc_password=$(openssl rand -hex 16)
    hash=$(docker run --rm authelia/authelia:4.39 authelia crypto hash generate argon2 --password "$oidc_password" |
        sed -n 's/^Digest: //p')
    printf 'users:\n  admin:\n    displayname: Admin\n    email: admin@example.com\n    password: "%s"\n' "$hash" \
        >"$dir/users.yml"
fi

cleanup() {
    status=$?
    [ "$status" -eq 0 ] || compose logs theca ${s3:+garage-init} ${proxy} ${authelia:+authelia} | tail -60
    compose down -v >/dev/null 2>&1
    rm -rf "$dir"
}
[ -n "$keep" ] || trap cleanup EXIT
services=$(compose config --services | grep -vx authelia | tr '\n' ' ')
# shellcheck disable=SC2086 # $services: one word per service
compose up -d --wait --quiet-pull $services

fail() {
    echo "smoke test failed: $1" >&2
    exit 1
}
api() { # method path [json]
    curl -fsS -X "$1" -b "$dir/cookies" -c "$dir/cookies" -H 'Content-Type: application/json' \
        ${3:+-d "$3"} "$url/api/v1$2"
}

echo "Checking $url${s3:+ with S3}${proxy:+ behind $proxy}${authelia:+ and Authelia}..."
# The web app's index.html on / and on any path the API doesn't use.
curl -fsS "$url/" | grep -q '/_app/immutable/entry/start\.' || fail "/ is not the web app"
curl -fsS "$url/some/deep/link" | grep -q '/_app/immutable/entry/start\.' || fail "a deep link is not the web app"
status=$(curl -s -o /dev/null -w '%{http_code}' "$url/api/v1/no-such-route")
[ "$status" = 404 ] || fail "an unknown API path answered $status, not 404"

server=$(curl -fsS "$url/api/version" | jq -r .server)
[ "$server" = "$core" ] || fail "the server is core $server, not $core"

if [ -n "$s3" ]; then
    # The URL browsers use too (the storage has one host).
    storage=$(jq -n --arg h "$s3url" '{name: "garage", implementation: "s3", host: $h, region: "garage",
        bucket: "theca", access_key_file: "/run/secrets/s3_access_key",
        secret_key_file: "/run/secrets/s3_secret_key", path_style: true}')
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
        -H "Access-Control-Request-Headers: x-amz-checksum-sha256,if-none-match" "$s3url/theca/chunks/x")
    printf %s "$preflight" | grep -qi "^access-control-allow-origin: $url" || fail "the bucket's preflight refuses the app"
    s3() { curl -fsS --aws-sigv4 "aws:amz:garage:s3" --user "$(cat "$dir/secrets/s3_access_key"):$(cat "$dir/secrets/s3_secret_key")" "$@"; }
    s3 -X PUT --data-binary cors "$s3url/theca/smoke-cors" >/dev/null
    get=$(s3 -o /dev/null -D - -H "Origin: $url" "$s3url/theca/smoke-cors")
    s3 -X DELETE "$s3url/theca/smoke-cors" >/dev/null
    printf %s "$get" | grep -qi "^access-control-expose-headers:.*etag" || fail "the bucket doesn't expose ETag to the app"
fi

if [ -n "$authelia" ]; then
    # The README's order: the provider in Theca, its callback URL to
    # Authelia, then Authelia started.
    api PATCH /admin/settings '{"oidc_link_by_email": "true"}' >/dev/null || fail "turning oidc_link_by_email on"
    provider=$(api POST /admin/identity-providers "$(jq -n --arg i "https://$AUTH_DOMAIN" '{name: "Authelia",
        issuer: $i, client_id: "theca", client_secret_file: "/run/secrets/oidc_client_secret", enabled: true}')" |
        jq -r .id) || fail "creating the provider"
    export OIDC_CALLBACK=$url/api/v1/auth/oidc/$provider/callback
    compose up -d --wait authelia

    # A browser logging in: Theca sends it to Authelia, it logs in there, and
    # comes back to Theca's callback with a code the server redeems.
    location() { sed -n 's/^[Ll]ocation: *//p' | tr -d '\r'; }
    authorize=$(curl -sS -o /dev/null -D - -c "$dir/browser" "$url/api/v1/auth/oidc/$provider/start" | location)
    case "$authorize" in "https://$AUTH_DOMAIN/"*) ;; *) fail "the login didn't go to Authelia: $authorize" ;; esac
    curl -fsS -b "$dir/authelia" -c "$dir/authelia" -H 'Content-Type: application/json' \
        -d "$(jq -n --arg p "$oidc_password" '{username: "admin", password: $p, keepMeLoggedIn: false}')" \
        "https://$AUTH_DOMAIN/api/firstfactor" >/dev/null || fail "logging in to Authelia"
    callback=$(curl -sS -o /dev/null -D - -b "$dir/authelia" -c "$dir/authelia" "$authorize" | location)
    case "$callback" in "$OIDC_CALLBACK?"*) ;; *) fail "Authelia didn't send back to Theca: $callback" ;; esac
    home=$(curl -sS -o /dev/null -D - -b "$dir/browser" -c "$dir/browser" "$callback" | location)
    [ "$home" = "$url/" ] || fail "Theca refused the login: $home"
    me=$(curl -fsS -b "$dir/browser" "$url/api/v1/me" | jq -r .email)
    [ "$me" = "$email" ] || fail "the session through Authelia is $me's, not $email's"
fi

echo "Smoke test passed${s3:+ with S3}${proxy:+ behind $proxy}${authelia:+ and Authelia}: web $(sed -n 's/^ARG WEB_VERSION=//p' Dockerfile), core $core"
