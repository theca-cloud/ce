#!/usr/bin/env sh
# OPERATING.md's configuration reference: core's CONFIGURATION.md (its
# environment variables and instance settings) at the Dockerfile's
# CORE_VERSION, copied between the markers. core's test keeps that file
# complete; this keeps the copy faithful.
#   scripts/operating.sh          rewrite the copy
#   scripts/operating.sh --check  fail if it differs (scripts/ci.sh)
set -eu
cd "$(dirname "$0")/.."

core=$(sed -n 's/^ARG CORE_VERSION=//p' Dockerfile)
for marker in start end; do
    grep -q "<!-- core:CONFIGURATION.md $marker -->" OPERATING.md ||
        { echo "OPERATING.md lacks its '<!-- core:CONFIGURATION.md $marker -->' marker" >&2; exit 1; }
done
ref=$(curl -fsSL "https://raw.githubusercontent.com/theca-cloud/core/$core/CONFIGURATION.md" |
    awk '/^## /{on = ($0 == "## Environment variables" || $0 == "## Instance settings")} on')
[ -n "$ref" ] || { echo "core $core's CONFIGURATION.md has no such sections" >&2; exit 1; }
# Through the environment: awk's -v refuses a value with newlines (BSD awk).
new=$(REF=$ref awk '
    /^<!-- core:CONFIGURATION.md end -->$/   {skip = 0}
    !skip
    /^<!-- core:CONFIGURATION.md start -->$/ {print ENVIRON["REF"]; skip = 1}' OPERATING.md)

if [ "${1:-}" = --check ]; then
    [ "$new" = "$(cat OPERATING.md)" ] ||
        { echo "OPERATING.md's configuration reference isn't core $core's: run scripts/operating.sh" >&2; exit 1; }
else
    printf '%s\n' "$new" >OPERATING.md
fi
