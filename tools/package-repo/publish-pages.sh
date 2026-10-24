#!/usr/bin/env bash
# publish-pages.sh - puts a repository that build.sh made into the `pages` branch, the one that GitHub Pages serves.
#
#   tools/package-repo/build.sh                 # signs with the key of Total.js on this computer
#   tools/package-repo/publish-pages.sh         # prepares build/pages and shows what would be published
#   tools/package-repo/publish-pages.sh --push  # and pushes it (a new commit on top of the published branch)
#   tools/package-repo/publish-pages.sh --fresh # a single commit with no history, which replaces the branch (needs --push to be a forced push)
#
# By default the new version is a commit on top of the one that is published: the branch moves forward, so it can be published with any
# tool (GitHub Desktop included) and nobody has to force anything. --fresh starts the history again, because old versions of binary files
# only make the repository grow. The signing key never leaves this computer: only signed files are published.
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

FRESH=0
PUSH=0
for arg in "$@"; do
  case "${arg}" in
    --fresh) FRESH=1 ;;
    --push) PUSH=1 ;;
    *) echo "unknown option ${arg}" >&2; exit 1 ;;
  esac
done
REMOTE="$(git -C "${ROOT}" remote get-url origin)"
MESSAGE="Package repository $(date -u +%Y-%m-%dT%H:%M:%SZ)"

cd "${PAGES}"
git init -q -b pages
git add -A
git -c user.name="${GIT_AUTHOR_NAME:-Total.js}" -c user.email="${GIT_AUTHOR_EMAIL:-repository@totaljs.com}" commit -q -m "${MESSAGE}"
if [ "${FRESH}" = 0 ] && git fetch -q "${REMOTE}" pages 2>/dev/null; then
  # the same files, on top of what is published
  NEW="$(git -c user.name="${GIT_AUTHOR_NAME:-Total.js}" -c user.email="${GIT_AUTHOR_EMAIL:-repository@totaljs.com}" commit-tree 'HEAD^{tree}' -p FETCH_HEAD -m "${MESSAGE}")"
  git update-ref refs/heads/pages "${NEW}"
fi

echo "prepared ${PAGES}: $(git ls-files | wc -l | tr -d ' ') files, $(du -sh . | cut -f1)"

# The prepared branch is also made a branch of this repository (`pages`), so that it can be published with the same tool that publishes `main`
# (the terminal does not always have the credentials: see the README). It is replaced every time: it is a copy, not a place to work.
if [ "$(git -C "${ROOT}" branch --show-current)" = pages ]; then
  echo "this repository is on the branch pages: it was not updated from build/pages. Go back to main (git checkout main) and run this again"
else
  git -C "${ROOT}" fetch --quiet --force "${PAGES}" pages:pages
  echo "the branch pages of this repository is now the prepared one ($(git -C "${ROOT}" rev-parse --short pages))"
fi

if [ "${PUSH}" = 1 ]; then
  if [ "${FRESH}" = 1 ]; then git push --force "${REMOTE}" pages; else git push "${REMOTE}" pages; fi
  echo "published to the branch pages of ${REMOTE}"
else
  echo "nothing was pushed. To publish it: $0 --push"
fi
