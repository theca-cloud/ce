#!/usr/bin/env sh
# Releases `dev` into `prod` (or a hotfix already on `prod`): runs scripts/ci.sh,
# merges with --no-ff, bumps the version in VERSION (and the compose's major
# version), prepends
# the release to CHANGELOG.md (git-cliff, cliff.toml), commits it all as the
# version (`1.2.3`), tags it, and fast-forwards `dev`. Never pushes.
#
# The version comes from the Conventional Commits on `dev` (cliff.toml's [bump]),
# except 1.0.0: going to 1.0.0 is a decision, so it is never automatic.
#   scripts/release.sh            the next version, from the commits
#   scripts/release.sh 1.0.0      that version
#   scripts/release.sh --dry-run  show the version and the changelog only
#
# From the global template, adapted: the version is VERSION's, and 0.x's tags
# had a `v` (vX.Y.Z), so they count as releases too.
set -eu
cd "$(dirname "$0")/.."

die() {
    echo "$1" >&2
    exit 1
}
command -v git-cliff >/dev/null 2>&1 || die "git-cliff is missing (brew install git-cliff)"
branch=$(git branch --show-current)
case "$branch" in
dev | prod) ;; # prod: a hotfix squashed into prod
*) die "releases start from dev (or prod, for a hotfix)" ;;
esac
[ -z "$(git status --porcelain)" ] || die "commit or stash your changes first"
git remote | grep -qx origin && git fetch -q --tags origin

dry=
next=
for arg in "$@"; do
    case "$arg" in
    --dry-run) dry=1 ;;
    *) next=$arg ;;
    esac
done

current=$(cat VERSION)

if [ -z "$next" ]; then
    if git tag --list '[0-9]*.*.*' 'v[0-9]*.*.*' | grep -q .; then
        next=$(git cliff --bumped-version | sed 's/^v//') # 0.x's tags carry the v
        [ "$next" != 1.0.0 ] || die "1.0.0 is your call: scripts/release.sh 1.0.0"
    else
        next=$current # the first release: the version the manifest already has
    fi
fi
echo "$next" | grep -Eqx '[0-9]+\.[0-9]+\.[0-9]+' || die "not a version: $next"
git rev-parse -q --verify "refs/tags/$next" >/dev/null && die "$next is already released"
git rev-parse -q --verify "refs/tags/v$next" >/dev/null && die "$next is already released"

# The changelog section, written now: dev's commits aren't on prod until the merge.
changes=$(mktemp)
git cliff --unreleased --tag "$next" --strip header >"$changes"

if [ -n "$dry" ]; then
    echo "Next version: $next (now $current)"
    cat "$changes"
    exit 0
fi

[ -x scripts/ci.sh ] && { scripts/ci.sh || die "scripts/ci.sh failed: nothing released"; }

if [ "$branch" = dev ]; then
    git checkout -q prod
    git merge -q --no-ff --no-commit dev >/dev/null || die "merge conflict: resolve it, or git merge --abort"
fi

echo "$next" >VERSION
# The compose names the major version: a pull stays within it.
sed -i.bak "s|image: thecacloud/ce:.*|image: thecacloud/ce:${next%%.*}|" docker-compose.yml
rm docker-compose.yml.bak
if [ -s "$changes" ]; then # empty when only skipped commits (chore, test...)
    [ -f CHANGELOG.md ] || printf '# Changelog\n\n' >CHANGELOG.md
    { head -n 2 CHANGELOG.md; cat "$changes"; echo; tail -n +3 CHANGELOG.md; } >"$changes.new"
    mv "$changes.new" CHANGELOG.md
    git add CHANGELOG.md
fi
rm -f "$changes"

git add -u
git commit -q -m "$next"
git tag -a "$next" -m "$next"
git checkout -q dev
if [ "$branch" = dev ]; then
    git merge -q --ff-only prod
    echo "Released $next. Push: git push origin prod dev $next"
else
    echo "Released $next on prod. Bring it into dev: git merge prod, then push prod, dev and $next"
fi
