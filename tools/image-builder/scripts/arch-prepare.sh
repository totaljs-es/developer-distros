#!/usr/bin/env bash
# arch-prepare.sh — download Archboot AArch64 and create a blank RAW disk.
#
#   scripts/arch-prepare.sh developer-arch
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

IMAGE_ID="${1:-developer-arch}"
IMAGE_DIR="${BUILDER_DIR}/images/${IMAGE_ID}"
[ -d "${IMAGE_DIR}" ] || die "unknown image '${IMAGE_ID}' (no images/${IMAGE_ID})"
CONFIG="${IMAGE_DIR}/image.json"

require_cmd jq
require_cmd curl
require_cmd qemu-img "brew install qemu"
require_cmd md5
require_cmd gpg "brew install gnupg"

ARCHBOOT_FINGERPRINT="5B7E3FB71B7F10329A1C03AB771DF6627EDF681F"
ARCHLINUXARM_FINGERPRINT="68B3537F39A313B3E574D06777193F152BDBE6A6"

verify_signature() {
    local file="$1" signature="$2" fingerprint="$3" label="$4"
    local gnupg_home key_file actual
    gnupg_home="$(mktemp -d)"
    key_file="${gnupg_home}/signing-key.asc"
    chmod 700 "${gnupg_home}"
    trap 'rm -rf "${gnupg_home}"' RETURN

    curl -fsSL --retry 5 --retry-delay 2 \
        "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${fingerprint}" \
        -o "${key_file}"
    GNUPGHOME="${gnupg_home}" gpg --batch --quiet --import "${key_file}"
    actual="$(GNUPGHOME="${gnupg_home}" gpg --batch --with-colons --fingerprint "${fingerprint}" \
        | awk -F: '$1 == "fpr" { print $10; exit }')"
    [ "${actual}" = "${fingerprint}" ] \
        || die "${label} signing key fingerprint mismatch"
    GNUPGHOME="${gnupg_home}" gpg --batch --verify "${signature}" "${file}" >/dev/null 2>&1 \
        || die "${label} signature verification failed"
    rm -rf "${gnupg_home}"
    trap - RETURN
    log "verified ${label} PGP signature"
}

INSTALLER_URL="$(image_get "${CONFIG}" .base_installer_url)"
ROOTFS_URL="$(image_get "${CONFIG}" .base_rootfs_url)"
DISK_GB="$(image_get "${CONFIG}" .disk_gb)"

mkdir -p "${WORK_DIR}" "${CACHE_DIR}"

if [[ "${INSTALLER_URL}" == */ ]]; then
    ISO_NAME="$(basename "$(curl -fsSL "${INSTALLER_URL}" \
        | sed -n 's/.*href="\([^"]*-latest-aarch64\.iso\)".*/\1/p' \
        | sort -u | tail -1)")"
    [ -n "${ISO_NAME}" ] || die "could not resolve the latest Archboot AArch64 ISO"
    INSTALLER_URL="${INSTALLER_URL}${ISO_NAME}"
fi

INSTALLER_ISO="${CACHE_DIR}/$(basename "${INSTALLER_URL}")"
if [ ! -f "${INSTALLER_ISO}" ]; then
    log "downloading Arch installer: ${INSTALLER_URL}"
    curl -fL --progress-bar -o "${INSTALLER_ISO}.part" "${INSTALLER_URL}"
    mv "${INSTALLER_ISO}.part" "${INSTALLER_ISO}"
else
    log "using cached installer: $(basename "${INSTALLER_ISO}")"
fi
INSTALLER_SIG="${INSTALLER_ISO}.sig"
curl -fL --retry 5 --retry-delay 2 -o "${INSTALLER_SIG}.part" "${INSTALLER_URL}.sig"
mv "${INSTALLER_SIG}.part" "${INSTALLER_SIG}"
verify_signature "${INSTALLER_ISO}" "${INSTALLER_SIG}" "${ARCHBOOT_FINGERPRINT}" "Archboot ISO"

ROOTFS="${CACHE_DIR}/$(basename "${ROOTFS_URL}")"
ROOTFS_MD5="$(curl -fsSL "${ROOTFS_URL}.md5" | awk '{print $1}')"
[ -n "${ROOTFS_MD5}" ] || die "could not fetch the Arch Linux ARM checksum"
if [ -f "${ROOTFS}" ] && [ "$(md5 -q "${ROOTFS}")" != "${ROOTFS_MD5}" ]; then
    warn "cached Arch rootfs is outdated; downloading the current rolling image"
    rm -f "${ROOTFS}"
fi
if [ ! -f "${ROOTFS}" ]; then
    log "downloading Arch Linux ARM root filesystem"
    curl -fL --progress-bar -o "${ROOTFS}.part" "${ROOTFS_URL}"
    mv "${ROOTFS}.part" "${ROOTFS}"
else
    log "using cached root filesystem: $(basename "${ROOTFS}")"
fi
[ "$(md5 -q "${ROOTFS}")" = "${ROOTFS_MD5}" ] || die "Arch Linux ARM rootfs checksum mismatch"
ROOTFS_SIG="${ROOTFS}.sig"
curl -fL --retry 5 --retry-delay 2 -o "${ROOTFS_SIG}.part" "${ROOTFS_URL}.sig"
mv "${ROOTFS_SIG}.part" "${ROOTFS_SIG}"
verify_signature "${ROOTFS}" "${ROOTFS_SIG}" "${ARCHLINUXARM_FINGERPRINT}" "Arch Linux ARM rootfs"

RAW_DISK="${WORK_DIR}/${IMAGE_ID}.raw"
if [ ! -f "${RAW_DISK}" ]; then
    log "creating blank RAW disk: ${RAW_DISK} (${DISK_GB}G)"
    # Keep the installer/build disk fully allocated. The final Apple Archive
    # preserves sparse holes, but provisioning directly onto a sparse RAW can
    # expose ext4 to discard/hole races during heavy package extraction.
    qemu-img create -f raw -o preallocation=full "${RAW_DISK}" "${DISK_GB}G"
else
    warn "RAW disk already exists, leaving it untouched: ${RAW_DISK}"
fi

cat <<EOF

Ready.

Installer: ${INSTALLER_ISO}
Rootfs:    ${ROOTFS}
Disk:      ${RAW_DISK}

The base install runs under Apple Virtualization (no QEMU). Normally you just
run: scripts/build-arch.sh ${IMAGE_ID}

EOF
