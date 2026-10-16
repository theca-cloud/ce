#!/usr/bin/env sh
# Until GitHub has core and web: clones them from Gitea at the Dockerfile's
# pins into .sources/core and .sources/web (no .git), for the build to use
# instead of its GitHub ADD. With GITEA_TOKEN (CI): over HTTPS as GITEA_USER;
# without: over SSH, as you.
set -eu
cd "$(dirname "$0")/.."

base=git@git.pband.ch:theca
[ -z "${GITEA_TOKEN:-}" ] || base="https://$GITEA_USER:$GITEA_TOKEN@git.pband.ch/theca"
rm -rf .sources
for repo in core web; do
    version=$(sed -n "s/^ARG $(echo $repo | tr a-z A-Z)_VERSION=//p" Dockerfile)
    # 1.0 on: tags are the version; 0.x's had a `v`.
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$version" "$base/$repo.git" ".sources/$repo" 2>/dev/null ||
        git -c advice.detachedHead=false clone -q --depth 1 --branch "v$version" "$base/$repo.git" ".sources/$repo"
    rm -rf ".sources/$repo/.git"
done
