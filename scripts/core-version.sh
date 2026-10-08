#!/usr/bin/env sh
# Prints the core version a web image is for: its label `org.theca.core`, read
# from the registry (decisions.md: web pins core, ce pins only web).
#   scripts/core-version.sh [web version]   default: the Dockerfile's WEB_VERSION
# Through the registry's API rather than `docker buildx imagetools inspect`: the
# release pipeline's tools image has no Docker. Needs GITEA_TOKEN, curl, jq.
set -eu
cd "$(dirname "$0")/.."
export GITEA_TOKEN="${GITEA_TOKEN:-$(cat .secrets/gitea_token 2>/dev/null)}"

registry=https://git.pband.ch/v2
version=${1:-$(sed -n 's/^ARG WEB_VERSION=//p' Dockerfile)}
token=$(curl -fsS -u "token:$GITEA_TOKEN" \
    "$registry/token?service=container_registry&scope=repository:theca/web:pull" | jq -r .token)
get() { # path [accept]
    curl -fsSL -H "Authorization: Bearer $token" ${2:+-H "Accept: $2"} "$registry/theca/web/$1"
}
index='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
manifest='application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
# Every platform carries the same label: the first one's is read.
digest=$(get "manifests/$version" "$index" | jq -r '[.manifests[] | select(.platform.os == "linux")][0].digest')
config=$(get "manifests/$digest" "$manifest" | jq -r .config.digest)
core=$(get "blobs/$config" | jq -r '.config.Labels["org.theca.core"] // empty')
[ -n "$core" ] || { echo "web:$version has no org.theca.core label" >&2; exit 1; }
echo "$core"
