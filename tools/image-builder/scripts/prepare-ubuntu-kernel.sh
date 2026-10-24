#!/usr/bin/env bash
# Download the current Ubuntu HWE kernel packages on the Mac so the guest can
# install them offline before its first apt invocation.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

RELEASE="${1:-noble}"
OUT_DIR="${2:?output directory required}"
INDEX_XZ="${CACHE_DIR}/${RELEASE}-updates-main-arm64-Packages.xz"
INDEX="${CACHE_DIR}/${RELEASE}-updates-main-arm64-Packages"
BASE_URL="https://ports.ubuntu.com/ubuntu-ports"

# ports.ubuntu.com occasionally leaves an HTTP connection idle for minutes and
# then resets it. Keep Ubuntu builds deterministic by using TLS, avoiding the
# unreliable IPv6 route seen on some Mac networks, and retrying every transfer
# error instead of only curl's small default set.
CURL_DOWNLOAD=(
    --fail
    --location
    --ipv4
    --retry 10
    --retry-all-errors
    --retry-delay 3
    --connect-timeout 15
    --speed-limit 1024
    --speed-time 30
)

mkdir -p "${OUT_DIR}" "${CACHE_DIR}"
curl "${CURL_DOWNLOAD[@]}" \
    -o "${INDEX_XZ}.part" \
    "${BASE_URL}/dists/${RELEASE}-updates/main/binary-arm64/Packages.xz"
mv "${INDEX_XZ}.part" "${INDEX_XZ}"
xz -dc "${INDEX_XZ}" > "${INDEX}"

SELECTION="$(mktemp)"
python3 - "${INDEX}" > "${SELECTION}" <<'PY'
import re
import sys

paragraphs = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n\n")
packages = {}
for paragraph in paragraphs:
    fields = {}
    current = None
    for line in paragraph.splitlines():
        if line.startswith(" ") and current:
            fields[current] += " " + line.strip()
        elif ": " in line:
            current, value = line.split(": ", 1)
            fields[current] = value
    if "Package" in fields:
        packages[fields["Package"]] = fields

selected = {"linux-image-virtual-hwe-24.04"}
queue = ["linux-image-virtual-hwe-24.04"]
while queue:
    name = queue.pop()
    fields = packages.get(name)
    if not fields:
        raise SystemExit(f"missing package in Ubuntu index: {name}")
    for group in fields.get("Depends", "").split(","):
        dependency = re.split(r"[ (|]", group.strip(), maxsplit=1)[0]
        if re.match(r"^linux-(image|modules)(-|$)", dependency) and dependency not in selected:
            selected.add(dependency)
            queue.append(dependency)

# The first guest boot only needs the versioned image and its core modules.
# Firmware, modules-extra and the HWE metapackage are installed by apt after
# rebooting into this kernel; keeping the bootstrap small avoids stressing the
# original Noble kernel with nearly a gigabyte of writes.
bootstrap = sorted(
    name for name in selected
    if re.match(r"^linux-image-[0-9]", name)
    or re.match(r"^linux-modules-[0-9]", name)
)
for name in bootstrap:
    fields = packages.get(name)
    if not fields or "Filename" not in fields or "SHA256" not in fields:
        raise SystemExit(f"incomplete package metadata: {name}")
    print(f'{fields["Filename"]}\t{fields["SHA256"]}')
PY

EXPECTED="$(mktemp)"
while IFS=$'\t' read -r filename sha256; do
    target="${OUT_DIR}/$(basename "${filename}")"
    echo "$(basename "${target}")" >> "${EXPECTED}"
    if [ ! -f "${target}" ] || [ "$(shasum -a 256 "${target}" | awk '{print $1}')" != "${sha256}" ]; then
        log "downloading Ubuntu bootstrap package: $(basename "${target}")"
        curl "${CURL_DOWNLOAD[@]}" -o "${target}.part" "${BASE_URL}/${filename}"
        mv "${target}.part" "${target}"
    fi
    actual="$(shasum -a 256 "${target}" | awk '{print $1}')"
    [ "${actual}" = "${sha256}" ] || die "kernel package checksum mismatch: ${target}"
done < "${SELECTION}"

for old in "${OUT_DIR}"/*.deb; do
    [ -e "${old}" ] || continue
    grep -Fxq "$(basename "${old}")" "${EXPECTED}" || rm -f "${old}"
done
rm -f "${SELECTION}" "${EXPECTED}"

log "Ubuntu HWE bootstrap ready ($(find "${OUT_DIR}" -name '*.deb' | wc -l | tr -d ' ') packages)"
