#!/usr/bin/env bash
# check-versions.sh - a package whose files changed since the last release has to have a new version.
#
#   tools/package-repo/check-versions.sh            # against the last tag (v*); nothing to check before the first one
#   tools/package-repo/check-versions.sh v0.1.0     # against a tag or a commit
#
# apt only updates a package when its version is higher. If a file of a package changes and the version stays, everybody who has
# installed it keeps the old content, and a system that is installed from the repository later gets a different package with the same
# name and number. The revision after the dash (1.0.0-1, 1.0.0-2...) is what changes for a fix; the number before it, for a new feature.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}"

BASE="${1:-$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)}"
if [ -z "${BASE}" ]; then
    echo "no release yet (no tag v*): nothing to compare with"
    exit 0
fi
git rev-parse --verify --quiet "${BASE}^{commit}" >/dev/null || { echo "unknown reference: ${BASE}" >&2; exit 2; }

BAD=0
for dir in packages/*/; do
    pkg="$(basename "${dir}")"
    git diff --quiet "${BASE}" -- "packages/${pkg}" && continue
    new="$(sed -n 's/^Version: //p' "packages/${pkg}/control" | head -n 1)"
    old="$(git show "${BASE}:packages/${pkg}/control" 2>/dev/null | sed -n 's/^Version: //p' | head -n 1 || true)"
    if [ -z "${old}" ]; then echo "new package ${pkg} ${new}"; continue; fi
    if [ "${new}" = "${old}" ]; then
        echo "CHANGED WITH THE SAME VERSION: ${pkg} ${new} (since ${BASE})" >&2
        BAD=1
    elif command -v dpkg >/dev/null 2>&1 && ! dpkg --compare-versions "${new}" gt "${old}"; then
        echo "THE VERSION DID NOT GO UP: ${pkg} ${old} -> ${new}" >&2
        BAD=1
    else
        echo "${pkg}: ${old} -> ${new}"
    fi
done
exit "${BAD}"
