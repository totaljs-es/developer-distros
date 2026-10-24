#!/usr/bin/env bash
# Validate a completed Total.js Developer RAW without modifying the source.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

IMAGE_ID="${1:-}"
[ -n "${IMAGE_ID}" ] || die "usage: smoke-test.sh <developer-ubuntu|developer-arch> [raw]"
CONFIG="${BUILDER_DIR}/images/${IMAGE_ID}/image.json"
[ -f "${CONFIG}" ] || die "unknown image '${IMAGE_ID}'"
RAW="${2:-${WORK_DIR}/${IMAGE_ID}.raw}"
[ -f "${RAW}" ] || die "RAW image not found: ${RAW}"

build_runner
require_cmd expect

RESCUE_ISO="$(ls -t "${CACHE_DIR}"/archboot-*-aarch64-ARCH-latest-aarch64.iso 2>/dev/null | head -n 1 || true)"
[ -f "${RESCUE_ISO}" ] || die "Archboot rescue ISO is required for the protected image smoke test"

SMOKE_DIR="$(mktemp -d "${WORK_DIR}/${IMAGE_ID}-smoke.XXXXXX")"
CLONE="${SMOKE_DIR}/developer.raw"
WWW="${SMOKE_DIR}/www"
cleanup() {
    rm -rf "${SMOKE_DIR}"
}
trap cleanup EXIT INT TERM
mkdir -p "${WWW}"

log "creating disposable APFS clone for ${IMAGE_ID}"
cp -c "${RAW}" "${CLONE}"

case "${IMAGE_ID}" in
    developer-ubuntu)
        USERNAME=root
        PASSWORD=root
        ;;
    developer-ubuntu-server)
        USERNAME=totalvm
        PASSWORD=totalvm
        RESCUE_ISO="-"
        ;;
    developer-arch-server)
        USERNAME=totalvm
        PASSWORD=totalvm
        RESCUE_ISO="-"
        ;;
    developer-arch)
        USERNAME=root
        PASSWORD=root
        ;;
    *)
        die "no smoke-test login is defined for ${IMAGE_ID}"
        ;;
esac

MEMORY="$(image_get "${CONFIG}" .build.memory_mb)"
log "booting ${IMAGE_ID} and validating its release services"
"${SCRIPT_DIR}/smoke-test-expect.tcl" \
    "${RUNNER_BIN}" "${CLONE}" "${WWW}" "${IMAGE_ID}" \
    "${USERNAME}" "${PASSWORD}" "${MEMORY}" "${RESCUE_ISO}"
log "${IMAGE_ID} passed the boot smoke test"
