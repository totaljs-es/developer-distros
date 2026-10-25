#!/usr/bin/env bash
# test-boot.sh - starts the live image in QEMU and waits for the marker that it writes on the serial console.
#
#   iso/own/test-boot.sh <image.iso>
#
# It needs qemu-system-x86_64. The log of the console stays in WORK_DIR (boot.log). With UEFI=1 it starts with OVMF (the package ovmf) instead of the BIOS.
set -euo pipefail

ISO="${1:?usage: test-boot.sh <image.iso>}"
WORK="${WORK_DIR:-build/own}"
TIMEOUT="${BOOT_TIMEOUT:-600}"
MARKER="${MARKER_PATTERN:-TOTALJS-LIVE-OK Total\\.js Developer}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -f "${ISO}" ] || die "${ISO} does not exist"
mkdir -p "${WORK}"
rm -f "${WORK}/boot.log"

if [ -w /dev/kvm ]; then ACCEL=kvm; else ACCEL=tcg; log "KVM is NOT available: QEMU emulates the CPU and this is slow"; fi

FIRMWARE=()
if [ "${UEFI:-0}" = 1 ]; then
    CODE="$(ls /usr/share/OVMF/OVMF_CODE*.fd /usr/share/ovmf/OVMF.fd 2>/dev/null | head -1)"
    [ -n "${CODE}" ] || die "OVMF is not installed (apt install ovmf)"
    FIRMWARE=(-bios "${CODE}")
    log "UEFI: ${CODE}"
fi

log "starting ${ISO} (up to ${TIMEOUT} s)"
START=$(date +%s)
qemu-system-x86_64 -accel "${ACCEL}" -cpu max -smp 2 -m 2048 "${FIRMWARE[@]}" \
    -cdrom "${ISO}" -boot d -nic user,model=virtio-net-pci \
    -display none -no-reboot -serial "file:${WORK}/boot.log" &
QEMU=$!

FOUND=0
for _ in $(seq 1 "${TIMEOUT}"); do
    if grep -a -q -E "${MARKER}" "${WORK}/boot.log" 2>/dev/null; then FOUND=1; break; fi
    kill -0 "${QEMU}" 2>/dev/null || break
    sleep 1
done
SECONDS_TAKEN=$(( $(date +%s) - START ))
kill "${QEMU}" 2>/dev/null || true
wait "${QEMU}" 2>/dev/null || true

if [ "${FOUND}" -ne 1 ]; then
    echo "--- the end of the console (the printable part) ---"
    tail -c 6000 "${WORK}/boot.log" 2>/dev/null | tr -cd '[:print:]\n' | tail -60 || true
    die "the live image did not say ${MARKER} in ${SECONDS_TAKEN} s"
fi
log "the live image booted in ${SECONDS_TAKEN} s: $(grep -a -o -E 'TOTALJS-LIVE-OK[^[:cntrl:]]*' "${WORK}/boot.log" | head -1)"
printf 'accel=%s boot_seconds=%s\n' "${ACCEL}" "${SECONDS_TAKEN}" > "${WORK}/timings.txt"
