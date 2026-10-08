#!/usr/bin/env sh
# The release pipeline's steps (.woodpecker/release.yaml). The version is
# VERSION's (written by scripts/release.sh). Needs GITEA_TOKEN.
#   tags     the image tags in .tags: X.Y.Z, X.Y, X, latest on prod (refusing a
#            version already released); X.Y.Z-rc, X.Y-rc, X-rc, rc on dev; and
#            the core the pinned web is for, as CORE_VERSION's default in the
#            Dockerfile (the buildx plugin's build args are static)
#   publish  the tag and the Gitea release: the web and core it holds, this
#            version's changelog, and docker-compose.yml attached (prod)
#            DRY_RUN=1: prints the release, publishes nothing
set -eu
cd "$(dirname "$0")/.."

gitea=https://git.pband.ch
repo=theca/ce
version=$(cat VERSION)
web=$(sed -n 's/^ARG WEB_VERSION=//p' Dockerfile)
core=$(scripts/core-version.sh "$web")
branch=${CI_COMMIT_BRANCH:-$(git branch --show-current)}

case "${1:-}" in
tags)
    major=${version%%.*}
    minor=${version#*.}
    minor=$major.${minor%%.*}
    if [ "$branch" = prod ]; then
        if curl -fsS -o /dev/null -H "Authorization: token $GITEA_TOKEN" \
            "$gitea/api/v1/repos/$repo/releases/tags/v$version"; then
            echo "v$version is already released: run scripts/release.sh on dev first" >&2
            exit 1
        fi
        printf '%s\n' latest "$major" "$minor" "$version" >.tags
    else
        printf '%s\n' rc "$major-rc" "$minor-rc" "$version-rc" >.tags
    fi
    cat .tags
    sed -i "s/^ARG CORE_VERSION\$/ARG CORE_VERSION=$core/" Dockerfile
    grep '^ARG CORE_VERSION=' Dockerfile
    ;;
publish)
    notes=$(awk -v v="## [$version]" 'index($0, v) == 1 {on = 1; next} /^## \[/ {on = 0} on' CHANGELOG.md)
    notes=$(printf 'Holds [web %s](%s/theca/web/releases/tag/v%s) and [core %s](%s/theca/core/releases/tag/v%s).\n%s' \
        "$web" "$gitea" "$web" "$core" "$gitea" "$core" "$notes")
    release=$(jq -n --arg tag "v$version" --arg sha "${CI_COMMIT_SHA:-$(git rev-parse HEAD)}" --arg body "$notes" \
        '{tag_name: $tag, target_commitish: $sha, name: $tag, body: $body}')
    if [ -n "${DRY_RUN:-}" ]; then
        printf '%s\n' "$release"
        exit 0
    fi
    # printf, not echo: sh's echo turns the notes' \n into line breaks (invalid
    # JSON); --data-binary, not -d, which strips them.
    id=$(printf '%s\n' "$release" |
        curl -fsS -X POST -H "Authorization: token $GITEA_TOKEN" -H 'Content-Type: application/json' \
            --data-binary @- "$gitea/api/v1/repos/$repo/releases" | jq -r .id)
    # The compose self-hosters download: it names this release's image.
    curl -fsS -X POST -H "Authorization: token $GITEA_TOKEN" -F "attachment=@docker-compose.yml" \
        "$gitea/api/v1/repos/$repo/releases/$id/assets?name=docker-compose.yml" >/dev/null
    echo "Released v$version"
    ;;
*)
    echo "usage: scripts/release-ci.sh tags|publish" >&2
    exit 2
    ;;
esac
