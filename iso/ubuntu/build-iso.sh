#!/usr/bin/env bash
# build-iso.sh - remaster the latest Ubuntu LTS live-server ISO (amd64 or arm64) with an autoinstall seed.
#
#   iso/ubuntu/build-iso.sh <seed-dir> <output.iso>
#
# The seed directory has the user-data and meta-data of cloud-init. It is copied into the ISO as /nocloud and the
# installer is told to use it (autoinstall). The ISO is downloaded from releases.ubuntu.com (amd64) or cdimage.ubuntu.com (arm64), and its checksum list is
# verified with the signing key of Ubuntu before anything else is trusted.
#
# Environment:
#   UBUNTU_RELEASE   the series to take the newest ISO of (default 26.04, the latest LTS)
#   ARCH             amd64 (default) or arm64
#   WORK_DIR         where the downloads and the working files go (default build/iso)
#   GRUB_TIMEOUT     seconds before the first boot entry starts (unset: the menu of Ubuntu is kept)
#   EXTRA_KERNEL     more arguments for the kernel of the installer (the CI test adds the serial console)
#   REPO_URL         the address of the package repository that the seed installs from (default: GitHub Pages)
#   SLIM             what to take out of the ISO, which is big because of the packages for installing without a network:
#                      pool   (default) /pool, about 1.2 GiB. /dists stays: the installer has the CD as a source of apt, and
#                             `apt-get update` fails if the Release file of that source is not there
#                      all    /pool and /dists (the installer failed in `apt-get update` with this one)
#                      0      nothing: the ISO as Ubuntu made it
set -euo pipefail

SEED="${1:?usage: build-iso.sh <seed-dir> <output.iso>}"
OUT="${2:?usage: build-iso.sh <seed-dir> <output.iso>}"
RELEASE="${UBUNTU_RELEASE:-26.04}"
ARCH="${ARCH:-amd64}"
# the ISO of amd64 is in releases.ubuntu.com; the one of arm64 is in cdimage.ubuntu.com, in another folder
case "${ARCH}" in
    amd64) BASE_URL="${UBUNTU_BASE_URL:-https://releases.ubuntu.com}/${RELEASE}" ;;
    arm64) BASE_URL="${UBUNTU_BASE_URL:-https://cdimage.ubuntu.com/ubuntu/releases}/${RELEASE}/release" ;;
    *) printf 'error: ARCH is amd64 or arm64\n' >&2; exit 1 ;;
esac
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
ISO_NAME="$(sed -n -E "s/^[0-9a-f]{64} \*(ubuntu-[0-9.]+-live-server-${ARCH}\.iso)\$/\1/p" "${WORK}/SHA256SUMS" | sort -V | tail -1)"
[ -n "${ISO_NAME}" ] || die "no live-server ${ARCH} ISO in the checksums of ${RELEASE}"
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
# Two ways in, which only differ in the edition that install-layer.sh reads from the command line: the first entry of the menu is
# copied, and the copy installs the desktop edition. The entries that were already there install the server edition.
start = next((i for i, line in enumerate(lines) if re.match(r'\s*menuentry\s', line)), None)
if start is None:
    sys.exit('no menuentry in grub.cfg: the menu of this ISO is not the one that was expected')
end, depth = start, 0
for j in range(start, len(lines)):
    depth += lines[j].count('{') - lines[j].count('}')
    if depth == 0 and j > start - 1 and '}' in lines[j]:
        end = j
        break
server = lines[start:end + 1]
desktop = list(server)
title = re.match(r"(\s*menuentry\s+)(['\"])(.*?)\2", server[0])
if title is None:
    sys.exit('the first menuentry has no title that can be read')
def retitle(block, label):
    block[0] = block[0].replace(title.group(0), title.group(1) + "'" + label + "'", 1)
retitle(server, 'Install Total.js Developer, server edition')
retitle(desktop, 'Install Total.js Developer, desktop edition')
for block, edition in ((server, 'server'), (desktop, 'desktop')):
    for i, line in enumerate(block):
        if re.match(r'\s*linux\s+/casper/vmlinuz', line):
            block[i] = line.replace(' ---', ' totaljs.edition=' + edition + ' ---', 1) if ' ---' in line else line + ' totaljs.edition=' + edition
lines[start:end + 1] = desktop + server
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

case "${SLIM:-pool}" in
    0|none) REMOVE=() ;;
    all|1) REMOVE=(/pool /dists) ;;
    pool) REMOVE=(/pool) ;;
    *) die "SLIM is pool, all or 0" ;;
esac

if [ "${#REMOVE[@]}" -gt 0 ]; then
    # The disk check of the installer reads md5sum.txt: it must not list what is no longer there
    xorriso -osirrox on -indev "${WORK}/${ISO_NAME}" -extract /md5sum.txt "${WORK}/md5sum.txt" >/dev/null 2>&1 \
        || die "could not read /md5sum.txt from the ISO"
    chmod u+w "${WORK}/md5sum.txt"
    PATTERN="$(printf '%s\n' "${REMOVE[@]}" | sed 's|^/||' | paste -sd'|' -)"
    grep -v -E "  \./(${PATTERN})/" "${WORK}/md5sum.txt" > "${WORK}/md5sum.slim" || true
    [ -s "${WORK}/md5sum.slim" ] || die "md5sum.txt has nothing left once ${REMOVE[*]} are out"
    ARGS+=(-rm_r "${REMOVE[@]}" -- -map "${WORK}/md5sum.slim" /md5sum.txt)
    log "slim: ${REMOVE[*]} taken out"
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
