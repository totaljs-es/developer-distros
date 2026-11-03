#!/usr/bin/env bash
# Run as an unprivileged user on native Arch/Arch Linux ARM with build deps installed.
set -euo pipefail
[ "$(id -u)" != 0 ] || { echo 'makepkg must run as an unprivileged user' >&2; exit 1; }
OUT="${1:?usage: build-packages.sh <output-directory>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "${OUT}"
OUT="$(cd "${OUT}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
for component in ckbcomp calamares; do
    mkdir "${WORK}/${component}"
    if [ "${component}" = calamares ]; then
        cp "${HERE}/PKGBUILD" "${WORK}/${component}/"
    else
        cp "${HERE}/ckbcomp/PKGBUILD" "${WORK}/${component}/"
    fi
    (cd "${WORK}/${component}" && makepkg --noconfirm)
    # Arch Linux ARM may use .pkg.tar.xz while Arch uses .pkg.tar.zst.
    # Ask makepkg for its outputs rather than assuming a compression format.
    (cd "${WORK}/${component}" && makepkg --packagelist) > "${WORK}/packages.list"
    [ -s "${WORK}/packages.list" ] || { echo 'makepkg reported no outputs' >&2; exit 1; }
    while IFS= read -r package; do cp "${package}" "${OUT}/"; done < "${WORK}/packages.list"
done
