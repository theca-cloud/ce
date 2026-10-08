#!/usr/bin/env sh
# Prepares a release on `dev`, or `prod` for a hotfix (docs/CONTRIBUTING.md,
# Releases): the next version from the Conventional Commits since the last
# release (git-cliff), written to VERSION, the compose's image tag and
# CHANGELOG.md, committed as
# `chore(release): X.Y.Z`. Then merge `dev` into `prod` (git merge --no-ff dev):
# its pipeline publishes the image and the release.
#   scripts/release.sh            prepare and commit
#   scripts/release.sh --dry-run  show the version and the changelog only
set -eu
cd "$(dirname "$0")/.."

die() {
    echo "$1" >&2
    exit 1
}
command -v git-cliff >/dev/null 2>&1 || die "git-cliff is missing (brew install git-cliff)"
case "$(git branch --show-current)" in
dev | prod) ;; # prod: a hotfix
*) die "releases are prepared on dev (or prod, for a hotfix)" ;;
esac
[ -z "$(git status --porcelain)" ] || die "commit or stash your changes first"
git fetch -q --tags origin

current=$(cat VERSION)
if git tag --list 'v*' | grep -q .; then
    next=$(git cliff --bumped-version | sed 's/^v//')
else
    next=$current # the first release: the version VERSION already has
fi
git tag --list | grep -qx "v$next" && die "v$next is already released: nothing new to release"

if [ "${1:-}" = --dry-run ]; then
    echo "Next version: $next (now $current)"
    git cliff --unreleased --tag "v$next" --strip header
    exit 0
fi

echo "$next" >VERSION
# The compose names its own release (the exact version until 1.0).
sed -i.bak "s|image: git.pband.ch/theca/ce:.*|image: git.pband.ch/theca/ce:$next|" docker-compose.yml
rm docker-compose.yml.bak
git cliff --tag "v$next" -o CHANGELOG.md
git add VERSION docker-compose.yml CHANGELOG.md
git commit -q -m "chore(release): $next"
echo "Release $next prepared on dev. Next: push dev, wait for its CI, then"
echo "  git checkout prod && git merge --no-ff dev && git push"
