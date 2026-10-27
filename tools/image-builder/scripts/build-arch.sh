#!/usr/bin/env bash
# Build Total.js Developer (Arch) end to end with no interactive installer.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

IMAGE_ID="${1:-developer-arch}"
RAW_ONLY=0
RESUME=0
if [ "${2:-}" = "--raw-only" ] || [ "${2:-}" = "--no-package" ]; then
    RAW_ONLY=1
elif [ "${2:-}" = "--resume" ]; then
    RESUME=1
fi
IMAGE_DIR="${BUILDER_DIR}/images/${IMAGE_ID}"
CONFIG="${IMAGE_DIR}/image.json"
[ -d "${IMAGE_DIR}" ] || die "unknown image '${IMAGE_ID}'"

SHARED_ASSETS="${BUILDER_DIR}/images/developer-ubuntu/assets"
REQUIRES_PACKAGE_REPO="$(jq -r 'if (.build | has("requires_package_repo")) then .build.requires_package_repo else true end' "${CONFIG}")"
if [ "${REQUIRES_PACKAGE_REPO}" = "true" ]; then
    for bootstrap in totaljs-release.pkg.tar.zst totaljs-repository.gpg; do
        [ -f "${SHARED_ASSETS}/${bootstrap}" ] \
            || die "missing shared asset ${bootstrap}; run tools/package-repo/build.sh first"
    done
fi

require_cmd jq
require_cmd qemu-img "brew install qemu"
require_cmd expect
require_cmd python3

CPUS="$(image_get "${CONFIG}" .build.cpus)"
MEM_MB="$(image_get "${CONFIG}" .build.memory_mb)"
# Archboot loads its whole environment into RAM and refuses to start below
# ~2.2 GB; give the install phase comfortable headroom for pacman + extraction.
INSTALL_MEM=$(( MEM_MB > 6144 ? MEM_MB : 6144 ))
RAW_DISK="${WORK_DIR}/${IMAGE_ID}.raw"

build_runner

if [ "${RESUME}" -eq 1 ]; then
    [ -f "${RAW_DISK}" ] || die "cannot resume: ${RAW_DISK} does not exist"
    log "resuming existing Arch RAW; completed provisioning steps will be skipped"
else
    # Produce a clean image. Cached downloads remain untouched.
    rm -f "${RAW_DISK}" "${RAW_DISK}.nvram"
    "${SCRIPT_DIR}/arch-prepare.sh" "${IMAGE_ID}"

    INSTALLER_ISO="$(find "${CACHE_DIR}" -maxdepth 1 -name 'archboot-*-latest-aarch64.iso' -print | sort | tail -1)"
    ROOTFS="${CACHE_DIR}/ArchLinuxARM-aarch64-latest.tar.gz"
    [ -f "${INSTALLER_ISO}" ] || die "Archboot ISO was not prepared"
    [ -f "${ROOTFS}" ] || die "Arch Linux ARM rootfs was not prepared"

    # Apple Virtualization installs and provisions with the same EFI firmware.
    log "installing the Arch Linux ARM base automatically (Apple Virtualization)"
    "${SCRIPT_DIR}/arch-install-vz-expect.tcl" \
        "${RUNNER_BIN}" "${RAW_DISK}" "${INSTALLER_ISO}" \
        "${CPUS}" "${INSTALL_MEM}" "${CACHE_DIR}" \
        "${IMAGE_DIR}/installer/install-base.sh"
fi

# Fresh NVRAM for the installed system so the firmware boots the disk's own
# systemd-boot via the fallback path, not a stale entry left from the ISO.
rm -f "${RAW_DISK}.nvram"

log "provisioning the shared Total.js Developer experience"
touch "${IMAGE_DIR}/provision/skip-zero"
mkdir -p "${WORK_DIR}"
ASSETS_STAGE="$(mktemp -d "${WORK_DIR}/assets.XXXXXX")"
trap 'rm -f "${IMAGE_DIR}/provision/skip-zero"; rm -rf "${ASSETS_STAGE}"' EXIT
cp -a "${SHARED_ASSETS}/." "${ASSETS_STAGE}/"
stage_toto "${ASSETS_STAGE}"
STAGE_MENU_ICONS="$(jq -r 'if (.build | has("stage_menu_icons")) then .build.stage_menu_icons else true end' "${CONFIG}")"
if [ "${STAGE_MENU_ICONS}" = "true" ]; then
    stage_menu_icons "${ASSETS_STAGE}"
fi
"${SCRIPT_DIR}/arch-provision-expect.tcl" \
    "${RUNNER_BIN}" "${RAW_DISK}" "${CPUS}" "${MEM_MB}" \
    "${IMAGE_DIR}/provision" "${ASSETS_STAGE}"
rm -f "${IMAGE_DIR}/provision/skip-zero"
rm -rf "${ASSETS_STAGE}"
trap - EXIT

rm -f "${RAW_DISK}.nvram"
"${SCRIPT_DIR}/package.sh" "${IMAGE_ID}" "${RAW_DISK}"

log "Arch image complete"
