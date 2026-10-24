#!/usr/bin/env bash
# Update and reboot a disposable APFS clone of the completed Ubuntu image.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

RAW="${1:-${WORK_DIR}/developer-ubuntu.raw}"
[ -f "${RAW}" ] || die "RAW image not found: ${RAW}"

build_runner
require_cmd expect

RESCUE_ISO="$(ls -t "${CACHE_DIR}"/archboot-*-aarch64-ARCH-latest-aarch64.iso 2>/dev/null | head -n 1 || true)"
[ -f "${RESCUE_ISO}" ] || die "Archboot rescue ISO is required for the Ubuntu update smoke test"

TEST_DIR="$(mktemp -d "${WORK_DIR}/developer-ubuntu-update.XXXXXX")"
CLONE="${TEST_DIR}/developer.raw"
cleanup() { rm -rf "${TEST_DIR}"; }
trap cleanup EXIT INT TERM

log "creating disposable Ubuntu update clone"
cp -c "${RAW}" "${CLONE}"
CPUS="$(image_get "${BUILDER_DIR}/images/developer-ubuntu/image.json" .build.cpus)"
MEMORY="$(image_get "${BUILDER_DIR}/images/developer-ubuntu/image.json" .build.memory_mb)"
"${SCRIPT_DIR}/ubuntu-update-smoke-expect.tcl" \
    "${RUNNER_BIN}" "${CLONE}" "${RESCUE_ISO}" "${CPUS}" "${MEMORY}"
log "developer-ubuntu survived a full update and reboot"
