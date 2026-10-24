#!/usr/bin/env bash
# Update and reboot a disposable APFS clone of the completed Arch image.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

RAW="${1:-${WORK_DIR}/developer-arch.raw}"
[ -f "${RAW}" ] || die "RAW image not found: ${RAW}"

build_runner
require_cmd expect

RESCUE_ISO="$(ls -t "${CACHE_DIR}"/archboot-*-aarch64-ARCH-latest-aarch64.iso 2>/dev/null | head -n 1 || true)"
[ -f "${RESCUE_ISO}" ] || die "Archboot rescue ISO is required for the Arch update smoke test"

TEST_DIR="$(mktemp -d "${WORK_DIR}/developer-arch-update.XXXXXX")"
CLONE="${TEST_DIR}/developer.raw"
cleanup() { rm -rf "${TEST_DIR}"; }
trap cleanup EXIT INT TERM

log "creating disposable Arch update clone"
cp -c "${RAW}" "${CLONE}"
CPUS="$(image_get "${BUILDER_DIR}/images/developer-arch/image.json" .build.cpus)"
MEMORY="$(image_get "${BUILDER_DIR}/images/developer-arch/image.json" .build.memory_mb)"
"${SCRIPT_DIR}/arch-update-smoke-expect.tcl" \
    "${RUNNER_BIN}" "${CLONE}" "${RESCUE_ISO}" "${CPUS}" "${MEMORY}"
log "developer-arch survived a full update and reboot"
