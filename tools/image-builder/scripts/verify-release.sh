#!/usr/bin/env bash
# Confirm the server exposes the exact artifact described by each manifest.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_cmd curl
require_cmd jq
require_cmd shasum

BASE_URL="${TOTALVM_RELEASE_URL:-https://totalvm.totaljs.es}"
IDS=("$@")
[ "${#IDS[@]}" -gt 0 ] || IDS=(developer-ubuntu developer-arch)

for image_id in "${IDS[@]}"; do
    manifest_url="${BASE_URL}/${image_id}/manifest.json"
    log "checking ${image_id}"
    manifest="$(curl -fsSL --retry 3 "${manifest_url}")"
    expected_size="$(jq -er '.size' <<<"${manifest}")"
    download_url="$(jq -er '.download' <<<"${manifest}")"

    headers="$(mktemp)"
    trap 'rm -f "${headers}"' EXIT
    curl -fsS --retry 3 --range 0-0 -D "${headers}" -o /dev/null "${download_url}"
    actual_size="$(tr -d '\r' <"${headers}" \
        | sed -nE 's|^[Cc]ontent-[Rr]ange: bytes [0-9]+-[0-9]+/([0-9]+)$|\1|p' \
        | tail -1)"
    rm -f "${headers}"
    trap - EXIT

    [ -n "${actual_size}" ] \
        || die "${image_id}: server did not return a total size for a range request"
    [ "${actual_size}" = "${expected_size}" ] \
        || die "${image_id}: manifest declares ${expected_size} bytes, server exposes ${actual_size}"

    artifact_name="$(basename "${download_url%%\?*}")"
    local_artifact="${DIST_DIR}/${image_id}/${artifact_name}"
    local_manifest="${DIST_DIR}/${image_id}/manifest.json"
    if [ -f "${local_artifact}" ] && [ -f "${local_manifest}" ]; then
        local_size="$(stat -f%z "${local_artifact}")"
        local_sha="$(shasum -a 256 "${local_artifact}" | awk '{print $1}')"
        expected_local_size="$(jq -r '.size' "${local_manifest}")"
        expected_local_sha="$(jq -r '.sha256' "${local_manifest}")"
        [ "${local_size}" = "${expected_local_size}" ] \
            || die "${image_id}: local artifact and manifest sizes differ"
        [ "${local_sha}" = "${expected_local_sha}" ] \
            || die "${image_id}: local artifact and manifest checksums differ"
    fi

    log "${image_id}: release size is consistent (${actual_size} bytes)"
done

log "release verification complete"
