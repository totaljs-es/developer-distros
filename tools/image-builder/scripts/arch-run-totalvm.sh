#!/usr/bin/env bash
# arch-run-totalvm.sh — boot an installed Arch RAW disk with totalvm-builder.
#
#   scripts/arch-run-totalvm.sh developer-arch
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

IMAGE_ID="${1:-developer-arch}"
IMAGE_DIR="${BUILDER_DIR}/images/${IMAGE_ID}"
[ -d "${IMAGE_DIR}" ] || die "unknown image '${IMAGE_ID}' (no images/${IMAGE_ID})"
CONFIG="${IMAGE_DIR}/image.json"

require_cmd jq

CPUS="$(image_get "${CONFIG}" .build.cpus)"
MEM_MB="$(image_get "${CONFIG}" .build.memory_mb)"
RAW_DISK="${WORK_DIR}/${IMAGE_ID}.raw"
[ -f "${RAW_DISK}" ] || die "RAW disk not found; run scripts/arch-prepare.sh ${IMAGE_ID}"

build_runner

# Expose the Arch provisioning scripts and the shared assets (reused from the
# Ubuntu image) so they can be mounted and run inside the booted Arch VM:
#     sudo mkdir -p /mnt/provision /mnt/assets
#     sudo mount -t virtiofs provision /mnt/provision
#     sudo mount -t virtiofs assets   /mnt/assets
#     sudo TOTALVM_ASSETS=/mnt/assets bash /mnt/provision/run.sh
PROVISION_DIR="${IMAGE_DIR}/provision"
ASSETS_DIR="${BUILDER_DIR}/images/developer-ubuntu/assets"

log "booting installed Arch RAW with Apple Virtualization"
exec "${RUNNER_BIN}" run \
    --disk "${RAW_DISK}" \
    --cpus "${CPUS}" \
    --memory "${MEM_MB}" \
    --share "provision=${PROVISION_DIR}" \
    --share "assets=${ASSETS_DIR}" \
    --interactive
