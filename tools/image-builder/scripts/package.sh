#!/usr/bin/env bash
# package.sh — emit an Apple Archive containing a sparse RAW disk and its manifest.
#
#   scripts/package.sh developer-ubuntu build/work/developer-ubuntu.raw
#
# Produces, under dist/<id>/:
#   developer.raw.aar        LZFSE-compressed Apple Archive
#   manifest.json            filled from manifest.template.json
#   icon.png                 copied from the image dir if present
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_cmd jq
require_cmd shasum
require_cmd qemu-img "brew install qemu"
require_cmd aa

IMAGE_ID="${1:?usage: package.sh <image-id> <raw-disk>}"
RAW_DISK="${2:?usage: package.sh <image-id> <raw-disk>}"
IMAGE_DIR="${BUILDER_DIR}/images/${IMAGE_ID}"
CONFIG="${IMAGE_DIR}/image.json"
[ -f "${RAW_DISK}" ] || die "raw disk not found: ${RAW_DISK}"

OUT_DIR="${DIST_DIR}/${IMAGE_ID}"
mkdir -p "${OUT_DIR}"
ARTIFACT="${OUT_DIR}/developer.raw.aar"
ARTIFACT_PART="${ARTIFACT}.part"
PACKAGE_DIR="$(mktemp -d "${OUT_DIR}/.package.XXXXXX")"
SPARSE_RAW="${PACKAGE_DIR}/developer.raw"
trap 'rm -rf "${PACKAGE_DIR}" "${ARTIFACT_PART}"' EXIT

VERSION="$(image_get "${CONFIG}" .version)"
RUNTIME_MEMORY="$(image_get "${CONFIG}" .runtime.memory)"
RUNTIME_CPUS="$(image_get "${CONFIG}" .runtime.cpus)"
RUNTIME_DISK="$(image_get "${CONFIG}" .runtime.disk)"

# Never archive the mutable work disk itself. Recreate it first so APFS records
# zero ranges as holes, then ask Apple Archive to preserve those holes and use
# native LZFSE compression. TotalVM extracts with `aa -enable-holes`, restoring
# a sparse developer.raw instead of allocating its full virtual capacity.
log "creating normalized sparse RAW…"
qemu-img convert -f raw -O raw -S 4k "${RAW_DISK}" "${SPARSE_RAW}"

SIZE_RAW="$(stat -f%z "${SPARSE_RAW}")"
log "compressing Apple Archive -> ${ARTIFACT}…"
rm -f "${ARTIFACT_PART}"
aa archive \
    -i "${SPARSE_RAW}" \
    -o "${ARTIFACT_PART}" \
    -a lzfse \
    -b 4m \
    -enable-holes
mv "${ARTIFACT_PART}" "${ARTIFACT}"
# Remove artifacts from the old direct-RAW publishing format after the new
# archive exists successfully.
rm -f "${OUT_DIR}/developer.raw"

SIZE="$(stat -f%z "${ARTIFACT}")"
SHA="$(shasum -a 256 "${ARTIFACT}" | awk '{print $1}')"
BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log "filling manifest…"
sed \
    -e "s|__VERSION__|${VERSION}|g" \
    -e "s|__MEMORY__|${RUNTIME_MEMORY}|g" \
    -e "s|__CPUS__|${RUNTIME_CPUS}|g" \
    -e "s|__DISK__|${RUNTIME_DISK}|g" \
    -e "s|__DOWNLOAD_URL__|https://totalvm.totaljs.es/${IMAGE_ID}/developer.raw.aar|g" \
    -e "s|__SIZE__|${SIZE}|g" \
    -e "s|__SIZE_UNCOMPRESSED__|${SIZE_RAW}|g" \
    -e "s|__SHA256__|${SHA}|g" \
    -e "s|__BUILT_AT__|${BUILT_AT}|g" \
    "${IMAGE_DIR}/manifest.template.json" > "${OUT_DIR}/manifest.json"

# Validate the JSON we just produced.
jq empty "${OUT_DIR}/manifest.json" || die "generated manifest is not valid JSON"

for icon in icon.png icon.svg; do
    [ -f "${IMAGE_DIR}/${icon}" ] && cp "${IMAGE_DIR}/${icon}" "${OUT_DIR}/${icon}" || true
done

log "packaged ${IMAGE_ID} v${VERSION}"
# LC_ALL=C so the dot-decimal from awk isn't rejected by a comma-decimal
# locale (that bug showed the size as "0,0 MiB").
log "  artifact : ${ARTIFACT} ($(LC_ALL=C awk -v s="${SIZE}" 'BEGIN{printf "%.1f", s/1048576}') MiB)"
log "  sha256   : ${SHA}"
log "  manifest : ${OUT_DIR}/manifest.json"
