#!/usr/bin/env bash
# build.sh — build a TotalVM image end to end.
#
#   scripts/build.sh developer-ubuntu [--raw-only|--resume]
#
# Steps:
#   1. build + sign the Swift VM runner
#   2. download the Ubuntu cloud image (cached)
#   3. convert qcow2 -> RAW and grow to the target disk size
#   4. assemble the cloud-init seed ISO
#   5. boot the VM; cloud-init provisions it, then powers off
#   6. optionally hand off to package.sh to produce dist/<id>/...
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

IMAGE_ID="${1:-developer-ubuntu}"
RAW_ONLY=0
RESUME=0
if [ "${2:-}" = "--raw-only" ] || [ "${2:-}" = "--no-package" ]; then
    RAW_ONLY=1
elif [ "${2:-}" = "--resume" ]; then
    RESUME=1
fi
IMAGE_DIR="${BUILDER_DIR}/images/${IMAGE_ID}"
[ -d "${IMAGE_DIR}" ] || die "unknown image '${IMAGE_ID}' (no images/${IMAGE_ID})"
CONFIG="${IMAGE_DIR}/image.json"

if [ "$(image_get "${CONFIG}" .os)" = "arch" ]; then
    exec "${SCRIPT_DIR}/build-arch.sh" "$@"
fi

REQUIRES_PACKAGE_REPO="$(jq -r 'if (.build | has("requires_package_repo")) then .build.requires_package_repo else true end' "${CONFIG}")"
SHARED_UBUNTU_ASSETS="${BUILDER_DIR}/images/developer-ubuntu/assets"
if [ "${REQUIRES_PACKAGE_REPO}" = "true" ]; then
    for bootstrap in totaljs-release.deb totaljs-repository.gpg; do
        [ -f "${IMAGE_DIR}/assets/${bootstrap}" ] || [ -f "${SHARED_UBUNTU_ASSETS}/${bootstrap}" ] \
            || die "missing assets/${bootstrap}; run tools/package-repo/build.sh first"
    done
fi

# --- tool checks -----------------------------------------------------------
require_cmd jq
require_cmd qemu-img "brew install qemu"
require_cmd hdiutil
require_cmd shasum
require_cmd python3

BASE_URL="$(image_get "${CONFIG}" .base_image_url)"
BASE_SHA256="$(jq -r '.base_image_sha256 // empty' "${CONFIG}")"
RELEASE="$(image_get "${CONFIG}" .release)"
DISK_GB="$(image_get "${CONFIG}" .disk_gb)"
CPUS="$(image_get "${CONFIG}" .build.cpus)"
MEM_MB="$(image_get "${CONFIG}" .build.memory_mb)"

mkdir -p "${WORK_DIR}" "${CACHE_DIR}"

# --- 1. runner -------------------------------------------------------------
build_runner

# --- 2. download base image (cached) --------------------------------------
BASE_IMG="${CACHE_DIR}/$(basename "${BASE_URL}")"
if [ ! -f "${BASE_IMG}" ]; then
    log "downloading base image: ${BASE_URL}"
    curl -fL --ipv4 --retry 10 --retry-all-errors --retry-delay 3 \
        --connect-timeout 15 --speed-limit 1024 --speed-time 30 \
        --progress-bar -o "${BASE_IMG}.part" "${BASE_URL}"
    mv "${BASE_IMG}.part" "${BASE_IMG}"
else
    log "using cached base image: $(basename "${BASE_IMG}")"
fi

if [ -n "${BASE_SHA256}" ]; then
    ACTUAL_BASE_SHA256="$(shasum -a 256 "${BASE_IMG}" | awk '{print $1}')"
    [ "${ACTUAL_BASE_SHA256}" = "${BASE_SHA256}" ] \
        || die "base image checksum mismatch (expected ${BASE_SHA256}, got ${ACTUAL_BASE_SHA256})"
    log "verified base image sha256"
fi

KERNEL_BOOTSTRAP="${CACHE_DIR}/${IMAGE_ID}-hwe-bootstrap"
USE_KERNEL_BOOTSTRAP="$(jq -r 'if (.build | has("kernel_bootstrap")) then .build.kernel_bootstrap else true end' "${CONFIG}")"
if [ "${USE_KERNEL_BOOTSTRAP}" = "true" ]; then
    # Bootstrap the HWE kernel without invoking apt under Noble's original kernel.
    bash "${SCRIPT_DIR}/prepare-ubuntu-kernel.sh" "${RELEASE}" "${KERNEL_BOOTSTRAP}"
else
    rm -rf "${KERNEL_BOOTSTRAP}"
    mkdir -p "${KERNEL_BOOTSTRAP}"
fi

# --- 3. qcow2 -> RAW, then grow -------------------------------------------
RAW_DISK="${WORK_DIR}/${IMAGE_ID}.raw"
if [ "${RESUME}" -eq 1 ]; then
    [ -f "${RAW_DISK}" ] || die "cannot resume: ${RAW_DISK} does not exist"
    log "resuming existing RAW disk; completed provisioning steps will be skipped"
else
    log "creating a fully allocated ${DISK_GB}G build disk…"
    rm -f "${RAW_DISK}" "${RAW_DISK}.nvram"
    # A sparse work disk plus the cloud image's first-boot `discard` mount can
    # corrupt ext4 directory blocks under sustained dpkg/Docker extraction in
    # Virtualization.framework (random SIGILL plus "Structure needs cleaning").
    # Preallocate the BUILD disk completely; package.sh creates the compact,
    # hole-aware release archive afterwards.
    qemu-img create -f raw -o preallocation=full "${RAW_DISK}" "${DISK_GB}G"
    qemu-img convert -f qcow2 -O raw -n -S 0 "${BASE_IMG}" "${RAW_DISK}"
fi

# --- 4. cloud-init seed ----------------------------------------------------
SEED_ISO="${WORK_DIR}/seed.iso"
SEED_SRC="$(mktemp -d)"
cp "${IMAGE_DIR}/cloud-init/user-data" "${SEED_SRC}/user-data"
cp "${IMAGE_DIR}/cloud-init/meta-data" "${SEED_SRC}/meta-data"
cp -a "${IMAGE_DIR}/provision" "${SEED_SRC}/provision"
cp -a "${KERNEL_BOOTSTRAP}" "${SEED_SRC}/kernel"
log "building cloud-init seed (NoCloud, label CIDATA)…"
rm -f "${SEED_ISO}"

# --- 5. boot + provision ---------------------------------------------------
# Fresh NVRAM each build so a stale boot entry can't wedge the install.
rm -f "${RAW_DISK}.nvram"
ASSETS_DIR="${IMAGE_DIR}/assets"
mkdir -p "${ASSETS_DIR}"
# Direct RAW publishing does not benefit from guest-side zero filling. The
# packaging stage sparsifies the copy without first writing gigabytes of zeros.
echo 1 > "${SEED_SRC}/provision/skip-zero"
cp -a "${ASSETS_DIR}" "${SEED_SRC}/assets"
if [ "${REQUIRES_PACKAGE_REPO}" = "true" ]; then
    for bootstrap in totaljs-release.deb totaljs-repository.gpg; do
        if [ ! -f "${SEED_SRC}/assets/${bootstrap}" ] && [ -f "${SHARED_UBUNTU_ASSETS}/${bootstrap}" ]; then
            cp "${SHARED_UBUNTU_ASSETS}/${bootstrap}" "${SEED_SRC}/assets/${bootstrap}"
        fi
    done
    if [ ! -f "${SEED_SRC}/assets/provision/package-repository.sh" ] \
        && [ -f "${SHARED_UBUNTU_ASSETS}/provision/package-repository.sh" ]; then
        mkdir -p "${SEED_SRC}/assets/provision"
        cp "${SHARED_UBUNTU_ASSETS}/provision/package-repository.sh" \
            "${SEED_SRC}/assets/provision/package-repository.sh"
    fi
fi
STAGE_MENU_ICONS="$(jq -r 'if (.build | has("stage_menu_icons")) then .build.stage_menu_icons else true end' "${CONFIG}")"
if [ "${STAGE_MENU_ICONS}" = "true" ]; then
    stage_menu_icons "${SEED_SRC}/assets"
fi
stage_toto "${SEED_SRC}/assets"
hdiutil makehybrid -iso -joliet -default-volume-name CIDATA -o "${SEED_ISO}" "${SEED_SRC}" >/dev/null
rm -rf "${SEED_SRC}"
# hdiutil appends .iso if missing.
[ -f "${SEED_ISO}" ] || SEED_ISO="${SEED_ISO}.iso"

log "booting VM for provisioning (this runs cloud-init, then powers off)…"
log "  follow progress on the serial console below; build completes on poweroff"
"${RUNNER_BIN}" run \
    --disk "${RAW_DISK}" \
    --seed "${SEED_ISO}" \
    --cpus "${CPUS}" \
    --memory "${MEM_MB}"

log "provisioning VM exited; packaging…"

# --- 6. package ------------------------------------------------------------
"${SCRIPT_DIR}/package.sh" "${IMAGE_ID}" "${RAW_DISK}"

log "done. artifacts in ${DIST_DIR}/${IMAGE_ID}/"
