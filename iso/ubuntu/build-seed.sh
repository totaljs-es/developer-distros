#!/usr/bin/env bash
# build-seed.sh - makes the seed image of the installer: a few kilobytes, with the volume label CIDATA, that the installer of Ubuntu reads next to
# the official ISO (a USB stick, or a second virtual drive). Nothing of Ubuntu is inside, so it can be published.
#
#   iso/ubuntu/build-seed.sh <desktop|server> <output.iso>
#
# Environment:
#   REPO_URL   the address of the repository of packages that the seed installs from (default: GitHub Pages)
set -euo pipefail

EDITION="${1:?usage: build-seed.sh <desktop|server> <output.iso>}"
OUT="${2:?usage: build-seed.sh <desktop|server> <output.iso>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_URL="${REPO_URL:-https://totaljs-es.github.io/developer-distros/repo}"

case "${EDITION}" in
    desktop) PACKAGE=totaljs-developer-desktop ;;
    server) PACKAGE=totaljs-developer-server ;;
    *) echo "the edition is desktop or server" >&2; exit 1 ;;
esac
command -v xorriso >/dev/null || { echo "xorriso is needed (apt install xorriso)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

python3 - "${HERE}" "${WORK}" "${EDITION}" "${PACKAGE}" "${REPO_URL}" <<'PY'
import sys
here, work, edition, package, repo = sys.argv[1:6]
template = open(here + '/seed-image/user-data.in').read()
script = open(here + '/install-layer.sh').read().rstrip('\n')
# the script goes inside a block of YAML: every line has the indentation of the block
block = '\n'.join(('      ' + line) if line else '' for line in script.split('\n'))
text = (template.replace('__INSTALL_LAYER__', block).replace('__EDITION__', edition)
        .replace('__REPO_URL__', repo).replace('__PACKAGE__', package))
if any(token in text for token in ('__INSTALL_LAYER__', '__REPO_URL__', '__PACKAGE__', '__EDITION__')):
    sys.exit('the seed still has placeholders')
open(work + '/user-data', 'w').write(text)
open(work + '/meta-data', 'w').write('instance-id: totaljs-developer-' + edition + '\n')
PY

mkdir -p "$(dirname "${OUT}")"
rm -f "${OUT}"
xorriso -as mkisofs -quiet -volid CIDATA -joliet -rational-rock -o "${OUT}" "${WORK}" >/dev/null 2>&1
echo "seed image: ${OUT} ($(wc -c < "${OUT}" | tr -d ' ') bytes), edition ${EDITION}, packages from ${REPO_URL}"
