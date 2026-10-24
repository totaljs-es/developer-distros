#!/usr/bin/env bash
# build-iso.sh - remaster the latest Ubuntu LTS live-server ISO (amd64) with an autoinstall seed.
#
#   iso/ubuntu/build-iso.sh <seed-dir> <output.iso>
#
# The seed directory has the user-data and meta-data of cloud-init. It is copied into the ISO as /nocloud and the
# installer is told to use it (autoinstall). The ISO is downloaded from releases.ubuntu.com, and its checksum list is
# verified with the signing key of Ubuntu before anything else is trusted.
#
# Environment:
#   UBUNTU_RELEASE   the series to take the newest ISO of (default 26.04, the latest LTS)
#   WORK_DIR         where the downloads and the working files go (default build/iso)
#   GRUB_TIMEOUT     seconds before the first boot entry starts (unset: the menu of Ubuntu is kept)
#   EXTRA_KERNEL     more arguments for the kernel of the installer (the CI test adds the serial console)
#   REPO_URL         the address of the package repository that the seed installs from (default: GitHub Pages)
#   SLIM             1 (default) takes /pool and /dists out of the ISO: they are the packages for installing without a network,
#                    about 1.2 GiB, and the installer of this distro always has one. SLIM=0 keeps the ISO as Ubuntu made it.
set -euo pipefail

SEED="${1:?usage: build-iso.sh <seed-dir> <output.iso>}"
OUT="${2:?usage: build-iso.sh <seed-dir> <output.iso>}"
RELEASE="${UBUNTU_RELEASE:-26.04}"
BASE_URL="${UBUNTU_BASE_URL:-https://releases.ubuntu.com}/${RELEASE}"
WORK="${WORK_DIR:-build/iso}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

for tool in curl gpg xorriso python3 openssl; do
    command -v "${tool}" >/dev/null || die "${tool} is required"
done
[ -f "${SEED}/user-data" ] || die "${SEED}/user-data does not exist"
[ -f "${SEED}/meta-data" ] || die "${SEED}/meta-data does not exist"

mkdir -p "${WORK}"

sha256_check() {
    if command -v sha256sum >/dev/null; then sha256sum -c -; else shasum -a 256 -c -; fi
}

# 1. The list of checksums, and its signature
log "downloading the checksums of ${RELEASE}"
curl -fsSL -o "${WORK}/SHA256SUMS" "${BASE_URL}/SHA256SUMS"
curl -fsSL -o "${WORK}/SHA256SUMS.gpg" "${BASE_URL}/SHA256SUMS.gpg"

# The two signing keys of the CD images of Ubuntu: https://ubuntu.com/tutorials/how-to-verify-ubuntu
export GNUPGHOME="${WORK}/gnupg"
mkdir -p "${GNUPGHOME}" && chmod 700 "${GNUPGHOME}"
gpg --batch --quiet --keyserver hkps://keyserver.ubuntu.com --recv-keys 0x46181433FBB75451 0xD94AA3F0EFE21092 \
    || die "could not get the signing keys of Ubuntu"
gpg --batch --verify "${WORK}/SHA256SUMS.gpg" "${WORK}/SHA256SUMS" 2>&1 | tee "${WORK}/gpg.log"
grep -q "Good signature" "${WORK}/gpg.log" || die "the signature of SHA256SUMS is not good"

# 2. The newest live-server ISO of that series
ISO_NAME="$(sed -n -E 's/^[0-9a-f]{64} \*(ubuntu-[0-9.]+-live-server-amd64\.iso)$/\1/p' "${WORK}/SHA256SUMS" | sort -V | tail -1)"
[ -n "${ISO_NAME}" ] || die "no live-server amd64 ISO in the checksums of ${RELEASE}"
log "base ISO: ${ISO_NAME}"

if [ ! -f "${WORK}/${ISO_NAME}" ]; then
    curl -fL --retry 3 -o "${WORK}/${ISO_NAME}.part" "${BASE_URL}/${ISO_NAME}"
    mv "${WORK}/${ISO_NAME}.part" "${WORK}/${ISO_NAME}"
fi
grep -F " *${ISO_NAME}" "${WORK}/SHA256SUMS" | (cd "${WORK}" && sha256_check) || die "the checksum of ${ISO_NAME} does not match"

# 3. The seed, with a random password that nobody knows (the real user is created by the person who installs) and the
# address of the repository. The script that installs the Total.js layer travels with every seed.
rm -rf "${WORK}/nocloud"
cp -R "${SEED}" "${WORK}/nocloud"
cp "$(dirname "$0")/install-layer.sh" "${WORK}/nocloud/install-layer.sh"
HASH="$(openssl passwd -6 "$(openssl rand -hex 24)")"
python3 - "${WORK}/nocloud/user-data" "${HASH}" "${REPO_URL:-https://totaljs-es.github.io/developer-distros/repo}" <<'PY'
import re, sys
path, password, repository = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
text = text.replace('__PASSWORD_HASH__', password).replace('__REPO_URL__', repository)
left = re.findall(r'__[A-Z_]+__', text)
if left:
    sys.exit('the seed still has placeholders: ' + ', '.join(sorted(set(left))))
open(path, 'w').write(text)
PY

# 4. The boot menu: take autoinstall and the seed
xorriso -osirrox on -indev "${WORK}/${ISO_NAME}" -extract /boot/grub/grub.cfg "${WORK}/grub.cfg" >/dev/null 2>&1 \
    || die "could not read /boot/grub/grub.cfg from the ISO"
chmod u+w "${WORK}/grub.cfg"

python3 - "${WORK}/grub.cfg" "${GRUB_TIMEOUT:-}" "${EXTRA_KERNEL:-}" <<'PY'
import re, sys
path, timeout, extra = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path).read().split('\n')
args = r'autoinstall ds=nocloud\;s=/cdrom/nocloud/' + ((' ' + extra) if extra else '')
patched = 0
for i, line in enumerate(lines):
    if re.match(r'\s*linux\s+/casper/vmlinuz', line):
        lines[i] = line.replace(' ---', ' ' + args + ' ---', 1) if ' ---' in line else line + ' ' + args
        patched += 1
if patched == 0:
    sys.exit('no "linux /casper/vmlinuz" line in grub.cfg: the menu of this ISO is not the one that was expected')
text = '\n'.join(lines)
if timeout:
    text, count = re.subn(r'^set timeout=\d+', 'set timeout=' + timeout, text, flags=re.M)
    if count == 0:
        sys.exit('no "set timeout=" in grub.cfg')
open(path, 'w').write(text)
print('patched %d boot entries' % patched)
PY

# 5. The new ISO keeps the way that the original boots (BIOS and UEFI)
log "writing ${OUT}"
rm -f "${OUT}"
mkdir -p "$(dirname "${OUT}")"

ARGS=(-indev "${WORK}/${ISO_NAME}" -outdev "${OUT}" -boot_image any replay)

if [ "${SLIM:-1}" = 1 ]; then
    # The disk check of the installer reads md5sum.txt: it must not list what is no longer there
    xorriso -osirrox on -indev "${WORK}/${ISO_NAME}" -extract /md5sum.txt "${WORK}/md5sum.txt" >/dev/null 2>&1 \
        || die "could not read /md5sum.txt from the ISO"
    chmod u+w "${WORK}/md5sum.txt"
    grep -v -E '  \./(pool|dists)/' "${WORK}/md5sum.txt" > "${WORK}/md5sum.slim" || true
    [ -s "${WORK}/md5sum.slim" ] || die "md5sum.txt has nothing left once /pool and /dists are out"
    ARGS+=(-rm_r /pool /dists -- -map "${WORK}/md5sum.slim" /md5sum.txt)
    log "slim: /pool and /dists are taken out"
fi

ARGS+=(-map "${WORK}/grub.cfg" /boot/grub/grub.cfg -map "${WORK}/nocloud" /nocloud)
xorriso "${ARGS[@]}" >"${WORK}/xorriso.log" 2>&1 || { tail -20 "${WORK}/xorriso.log" >&2; die "xorriso failed"; }

# What makes an ISO big, of the original and of the result (informational: a failure here never fails the build)
report() {   # report <iso>
    echo "# $(basename "$1"): $(wc -c < "$1" | tr -d ' ') bytes"
    for dir in /casper /pool /dists /boot /EFI /nocloud; do
        xorriso -indev "$1" -dus "${dir}" 2>&1 | grep -v -E '^(xorriso|libisofs|libburn|Drive|Media|Boot|Volume)' | sed "s|^|${dir}  |" || true
    done
}
{
    echo "## the original of Ubuntu"
    report "${WORK}/${ISO_NAME}" || true
    echo
    echo "## the result"
    report "${OUT}" || true
    echo
    echo "## /casper of the result"
    xorriso -indev "${OUT}" -lsl /casper/ 2>&1 | grep -E "^-" || true
} > "${WORK}/contents.txt"

log "done: $(du -h "${OUT}" | cut -f1) $(basename "${OUT}") (from ${ISO_NAME})"
