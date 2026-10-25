#!/usr/bin/env bash
# arch/build.sh - builds the packages of Arch from packages/ and a repository of pacman with them.
#
# It runs on Arch Linux (or in a container of it), as a normal user: makepkg does not run as root. Needs base-devel and python.
#
#   KEY_FILE=public-key.gpg arch/build.sh                 # the repository in build/arch/x86_64, not signed
#   KEY_FILE=... SIGN_KEY=<fingerprint> arch/build.sh     # the packages and the database signed with that key
#
# KEY_FILE is the public key that the package totaljs-developer-release installs. BASE_URL is where the repository is published.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ARCH_OUT:-${ROOT}/build/arch/x86_64}"
WORK="${ROOT}/build/arch-work"
BASE_URL="${BASE_URL:-https://totaljs-es.github.io/developer-distros}"
KEY_FILE="${KEY_FILE:?KEY_FILE is the public key of the repository}"
SIGN_KEY="${SIGN_KEY:-}"

[ "$(id -u)" != 0 ] || { echo "run this as a normal user: makepkg does not run as root" >&2; exit 1; }

rm -rf "${WORK}" "${OUT}"
mkdir -p "${WORK}" "${OUT}"

python3 "${ROOT}/arch/mkpkg.py" --all "${WORK}"

cp -r "${ROOT}/arch/extra/totaljs-developer-release" "${WORK}/"
cp "${KEY_FILE}" "${WORK}/totaljs-developer-release/totaljs-developer.gpg"
printf 'Server = %s/arch/$arch\n' "${BASE_URL}" > "${WORK}/totaljs-developer-release/totaljs-developer-mirrorlist"

SIGN=()
[ -z "${SIGN_KEY}" ] || SIGN=(--sign --key "${SIGN_KEY}")

for dir in "${WORK}"/*/; do
    echo "==> $(basename "${dir}")"
    (cd "${dir}" && PKGDEST="${OUT}" makepkg --noconfirm --nodeps --force --nocheck "${SIGN[@]}")
done

repo-add "${SIGN[@]}" "${OUT}/totaljs-developer.db.tar.zst" "${OUT}"/*.pkg.tar.zst
ls -la "${OUT}"
