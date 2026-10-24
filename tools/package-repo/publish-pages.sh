#!/usr/bin/env bash
# publish-pages.sh - puts a repository that build.sh made into the `pages` branch, the one that GitHub Pages serves.
#
#   tools/package-repo/build.sh                 # signs with the key of Total.js on this computer
#   tools/package-repo/publish-pages.sh         # prepares build/pages and shows what would be published
#   tools/package-repo/publish-pages.sh --push  # and pushes it (a single commit, replacing the branch)
#
# The branch has no history on purpose: a repository is a set of files that is replaced as a whole, and old versions of
# binary files would only make the repository grow. The signing key never leaves this computer: only signed files are published.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SITE="${REPO_OUT:-${ROOT}/build/site/repo}"
PAGES="${ROOT}/build/pages"
CNAME_VALUE="${PAGES_CNAME:-}"

[ -f "${SITE}/totaljs-developer.gpg" ] || { echo "No repository in ${SITE}: run tools/package-repo/build.sh first" >&2; exit 1; }
FOUND=0
for release in "${SITE}"/ubuntu/dists/*/InRelease; do
  [ -f "${release}" ] || continue
  FOUND=$((FOUND + 1))
done
[ "${FOUND}" -gt 0 ] || { echo "No signed series (InRelease) in ${SITE}/ubuntu/dists" >&2; exit 1; }

rm -rf "${PAGES}"
mkdir -p "${PAGES}/repo"
cp -R "${SITE}/." "${PAGES}/repo/"
touch "${PAGES}/.nojekyll"
[ -z "${CNAME_VALUE}" ] || printf '%s\n' "${CNAME_VALUE}" > "${PAGES}/CNAME"
cat > "${PAGES}/index.html" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>Total.js Developer packages</title>
<p>The APT and Pacman repository of the Total.js Developer Distros. It is used by the system, not by a browser.</p>
HTML

cd "${PAGES}"
git init -q -b pages
git add -A
git -c user.name="${GIT_AUTHOR_NAME:-Total.js}" -c user.email="${GIT_AUTHOR_EMAIL:-repository@totaljs.com}" commit -q -m "Package repository $(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "prepared ${PAGES}: $(git ls-files | wc -l | tr -d ' ') files, $(du -sh . | cut -f1)"

if [ "${1:-}" = "--push" ]; then
  REMOTE="$(git -C "${ROOT}" remote get-url origin)"
  git push --force "${REMOTE}" pages
  echo "published to the branch pages of ${REMOTE}"
else
  echo "nothing was pushed. To publish it: $0 --push"
fi
