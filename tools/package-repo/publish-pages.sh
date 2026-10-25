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
# The front page: what this is, how to add it, and the packages with their descriptions (GitHub Pages lists no folders, so the page is the list).
cp "${ROOT}/shared/branding/logo-totaljs.svg" "${PAGES}/logo.svg"
FINGERPRINT="$(gpg --show-keys --with-colons "${SITE}/totaljs-developer.gpg" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
python3 - "${SITE}" "${PAGES}/index.html" "${FINGERPRINT}" <<'PY'
import glob, html, sys
site, out, fingerprint = sys.argv[1:4]
series = sorted(glob.glob(site + '/ubuntu/dists/*/main/binary-amd64/Packages'))
packages = []
if series:
    for block in open(series[-1]).read().strip().split('\n\n'):
        fields, last = {}, None
        for line in block.split('\n'):
            if line.startswith(' ') and last == 'Description':
                continue
            key, _, value = line.partition(': ')
            fields[key] = value
            last = key
        if 'Package' in fields:
            packages.append(fields)
packages.sort(key=lambda p: p['Package'])
suite = series[-1].split('/')[-4] if series else 'resolute'
rows = ''.join(
    '<tr><td><a href="repo/ubuntu/%s"><code>%s</code></a></td><td>%s</td><td>%s</td></tr>\n'
    % (html.escape(p['Filename']), html.escape(p['Package']), html.escape(p['Version']), html.escape(p.get('Description', '')))
    for p in packages)
page = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Total.js Developer packages</title>
<link rel="icon" href="logo.svg" type="image/svg+xml">
<style>
:root { color-scheme: dark light; --bg:#0b0f0d; --card:#131a16; --line:#25322a; --text:#e8efe9; --muted:#93a399; --green:#9ad959; }
@media (prefers-color-scheme: light) { :root { --bg:#f6f8f4; --card:#fff; --line:#d6e0d0; --text:#14201a; --muted:#5a6b60; --green:#2e6d14; } }
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--text); font:16px/1.6 system-ui,-apple-system,'Segoe UI',Ubuntu,sans-serif; }
main { width:min(900px, 100% - 32px); margin:0 auto; padding:32px 0 56px; }
header { display:flex; align-items:center; gap:16px; margin-bottom:8px; }
h1 { margin:0; font-size:28px; } h2 { margin:36px 0 12px; font-size:20px; }
p { color:var(--muted); margin:8px 0; } a { color:var(--green); }
pre, code { font-family:ui-monospace,'Fira Code',Menlo,monospace; font-size:.92em; }
pre { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:14px 16px; overflow:auto; color:var(--text); }
table { width:100%; border-collapse:collapse; background:var(--card); border:1px solid var(--line); border-radius:10px; overflow:hidden; }
th, td { text-align:left; padding:10px 14px; border-bottom:1px solid var(--line); vertical-align:top; font-size:14px; }
th { color:var(--muted); font-weight:600; } tr:last-child td { border-bottom:0; }
@media (max-width:640px) { th:nth-child(2), td:nth-child(2) { display:none; } }
</style>
</head>
<body>
<main>
<header><img src="logo.svg" width="48" height="48" alt=""><h1>Total.js Developer packages</h1></header>
<p>The signed repository of <a href="https://github.com/totaljs-es/developer-distros">Total.js Developer</a>: a development environment for Total.js on Ubuntu 26.04 LTS. It is used by <code>apt</code>, and this page is its index.</p>

<h2>Add it to Ubuntu 26.04</h2>
<pre>curl -fsSL https://totaljs-es.github.io/developer-distros/repo/totaljs-developer.gpg | sudo tee /usr/share/keyrings/totaljs-developer-archive-keyring.gpg &gt;/dev/null
echo "deb [signed-by=/usr/share/keyrings/totaljs-developer-archive-keyring.gpg] https://totaljs-es.github.io/developer-distros/repo/ubuntu SUITE main" | sudo tee /etc/apt/sources.list.d/totaljs-developer.list
sudo apt update
sudo apt install totaljs-developer-release totaljs-docker-source
sudo rm /etc/apt/sources.list.d/totaljs-developer.list
sudo apt update
sudo apt install totaljs-developer-server</pre>
<p>For the desktop edition, install <code>totaljs-mozilla-source</code> with the other two sources, and <code>totaljs-developer-desktop</code> at the end. To install from nothing, with the Ubuntu installer, see the <a href="https://github.com/totaljs-es/developer-distros/blob/main/docs/install.md">installation guide</a>.</p>

<h2>Packages</h2>
<table>
<tr><th>Package</th><th>Version</th><th>What it is</th></tr>
ROWS</table>

<h2>The key</h2>
<p>Everything is signed with one key: <a href="repo/totaljs-developer.gpg">totaljs-developer.gpg</a> (<a href="repo/totaljs-developer.asc">armored</a>).<br>Fingerprint: <code>FINGERPRINT</code></p>
<p>An Arch Linux (Pacman) repository is served from <code>repo/arch</code>.</p>
</main>
</body>
</html>
"""
open(out, 'w').write(page.replace('SUITE', suite).replace('ROWS', rows).replace('FINGERPRINT', html.escape(fingerprint)))
PY

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
