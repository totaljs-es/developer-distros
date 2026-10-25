#!/usr/bin/env bash
# arch/stage-repo.sh - signs the repository of pacman that the CI built and puts it where publish-pages.sh publishes it.
#
#   arch/stage-repo.sh ~/Downloads/arch-repo-x86_64.zip       # the artifact `arch-repo-x86_64` of the workflow arch-repo (or a folder with the same files)
#
# The CI builds the packages but does not sign them: the key of Total.js never leaves this computer. Here every package and the database get their
# detached signature, and the result replaces build/site/repo/arch/x86_64 and aarch64 (the ones that tools/package-repo/build.sh made, with the packages of TotalVM).
# The order is: tools/package-repo/build.sh, then this, then tools/package-repo/publish-pages.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="${REPO_OUT:-${ROOT}/build/site/repo}"
KEY_FPR="${TOTALJS_REPO_KEY:-95454694523B8D18A376F7D5D722BA35C8427B40}"
# the same place of the key as tools/package-repo/build.sh
GNUPGHOME="${TOTALJS_REPO_GNUPGHOME:-${HOME}/.config/totaljs/repository-signing}"
[ -d "${GNUPGHOME}" ] || { echo "Signing key home not found: ${GNUPGHOME}" >&2; exit 1; }
export GNUPGHOME
SRC="${1:?the artifact of the workflow arch-repo: a .zip or a folder}"

[ -d "${SITE}" ] || { echo "No repository in ${SITE}: run tools/package-repo/build.sh first" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
if [ -d "${SRC}" ]; then cp -R "${SRC}/." "${WORK}/"; else unzip -q "${SRC}" -d "${WORK}"; fi

[ -f "${WORK}/totaljs-developer.db.tar.zst" ] || { echo "the artifact has no totaljs-developer.db.tar.zst" >&2; exit 1; }
PACKAGES=("${WORK}"/*.pkg.tar.zst)
[ -e "${PACKAGES[0]}" ] || { echo "the artifact has no packages" >&2; exit 1; }
gpg --batch --list-secret-keys "${KEY_FPR}" >/dev/null 2>&1 || { echo "the key ${KEY_FPR} is not on this computer" >&2; exit 1; }

# the release package of the artifact has the key that is committed: it has to be this one
RELEASE="$(ls "${WORK}"/totaljs-developer-release-*.pkg.tar.zst | head -n 1)"
bsdtar -xOf "${RELEASE}" usr/share/totaljs-developer/repository-key.gpg | gpg --show-keys --with-colons 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }' | grep -x "${KEY_FPR}" >/dev/null \
    || { echo "the package totaljs-developer-release carries another key than ${KEY_FPR}" >&2; exit 1; }

for package in "${PACKAGES[@]}"; do
    gpg --batch --yes --local-user "${KEY_FPR}" --detach-sign --output "${package}.sig" "${package}"
done
# pacman asks for totaljs-developer.db (and its .sig): a copy of the database, not a link, because the site is made of plain files
cp -f "${WORK}/totaljs-developer.db.tar.zst" "${WORK}/totaljs-developer.db"
[ ! -f "${WORK}/totaljs-developer.files.tar.zst" ] || cp -f "${WORK}/totaljs-developer.files.tar.zst" "${WORK}/totaljs-developer.files"
for db in totaljs-developer.db.tar.zst totaljs-developer.db; do
    gpg --batch --yes --local-user "${KEY_FPR}" --detach-sign --output "${WORK}/${db}.sig" "${WORK}/${db}"
done
for f in "${WORK}"/*.sig; do gpg --batch --verify "${f}" "${f%.sig}" 2>/dev/null; done

# the packages are Architecture: any: the same files serve x86_64 and aarch64 (Arch Linux ARM). What was in aarch64 (the packages of TotalVM) is replaced
for ARCH_DIR in x86_64 aarch64; do
    DEST="${SITE}/arch/${ARCH_DIR}"
    rm -rf "${DEST}"
    mkdir -p "${DEST}"
    cp -p "${WORK}"/* "${DEST}/"
done
# the configurations of archinstall, next to the repository (https://.../repo/arch/server.json)
cp -p "${ROOT}"/arch/archinstall/*.json "${SITE}/arch/"
cp -p "${ROOT}/arch/install-arm.sh" "${SITE}/arch/install-arm.sh"
echo "[arch] ${#PACKAGES[@]} packages, signed, in ${SITE}/arch/x86_64 and ${SITE}/arch/aarch64"
ls "${SITE}/arch/x86_64"
