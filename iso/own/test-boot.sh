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
ARCH="${ARCH:-amd64}"
MEMORY="${QEMU_MEMORY:-2048}"
MARKER="${MARKER_PATTERN:-TOTALJS-LIVE-OK Total\\.js Developer}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -f "${ISO}" ] || die "${ISO} does not exist"
mkdir -p "${WORK}"
rm -f "${WORK}/boot.log"

if [ -n "${QEMU_ACCEL:-}" ]; then
    ACCEL="${QEMU_ACCEL}"
elif [ -w /dev/kvm ]; then
    ACCEL=kvm
elif [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] && [ "${ARCH}" = arm64 ]; then
    ACCEL=hvf
else
    ACCEL=tcg
fi
case "${ACCEL}" in kvm|hvf|tcg) ;; *) die "unsupported acceleration: ${ACCEL}" ;; esac
log "QEMU acceleration: ${ACCEL}"

if [ "${ACCEL}" = tcg ]; then CPU=max; else CPU=host; fi
OPTIONS=(-accel "${ACCEL}" -cpu "${CPU}" -smp 2 -m "${MEMORY}" -nic user,model=virtio-net-pci
         -display none -no-reboot -serial "file:${WORK}/boot.log")
if [ "${UEFI:-0}" = 1 ] || [ "${ARCH}" = arm64 ]; then
    CODE="${QEMU_FIRMWARE:-}"
    if [ -z "${CODE}" ]; then
        if [ "${ARCH}" = arm64 ]; then
            CANDIDATES=(/usr/share/AAVMF/AAVMF_CODE.fd /usr/share/qemu-efi-aarch64/QEMU_EFI.fd
                        /opt/homebrew/share/qemu/edk2-aarch64-code.fd /usr/local/share/qemu/edk2-aarch64-code.fd)
        else
            CANDIDATES=(/usr/share/OVMF/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/ovmf/OVMF.fd
                        /opt/homebrew/share/qemu/edk2-x86_64-code.fd /usr/local/share/qemu/edk2-x86_64-code.fd)
        fi
        for candidate in "${CANDIDATES[@]}"; do
            if [ -f "${candidate}" ]; then CODE="${candidate}"; break; fi
        done
    fi
    [ -f "${CODE}" ] || die "UEFI firmware is missing; set QEMU_FIRMWARE to its path"
    OPTIONS+=(-bios "${CODE}")
    log "UEFI: ${CODE}"
fi

case "${ARCH}" in
    amd64) EMULATOR=qemu-system-x86_64; OPTIONS+=(-cdrom "${ISO}" -boot d) ;;
    arm64)
        EMULATOR=qemu-system-aarch64
        OPTIONS+=(-machine virt -device virtio-gpu-pci -device virtio-scsi-pci
                  -drive "file=${ISO},if=none,id=cdrom,media=cdrom,format=raw" -device scsi-cd,drive=cdrom)
        ;;
    *) die "unsupported architecture: ${ARCH}" ;;
esac

log "starting ${ISO} (up to ${TIMEOUT} s)"
START=$(date +%s)
"${EMULATOR}" "${OPTIONS[@]}" &
QEMU=$!
cleanup() { kill "${QEMU}" 2>/dev/null || true; wait "${QEMU}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

FOUND=0
for _ in $(seq 1 "${TIMEOUT}"); do
    if grep -a -q -E "${MARKER}" "${WORK}/boot.log" 2>/dev/null; then FOUND=1; break; fi
    kill -0 "${QEMU}" 2>/dev/null || break
    sleep 1
done
SECONDS_TAKEN=$(( $(date +%s) - START ))
cleanup
trap - EXIT INT TERM

if [ "${FOUND}" -ne 1 ]; then
    echo "--- the end of the console (the printable part) ---"
    tail -c 6000 "${WORK}/boot.log" 2>/dev/null | tr -cd '[:print:]\n' | tail -60 || true
    die "the live image did not say ${MARKER} in ${SECONDS_TAKEN} s"
fi
MATCH="$(grep -a -m1 -E "${MARKER}" "${WORK}/boot.log" || true)"
log "the live image booted in ${SECONDS_TAKEN} s: ${MATCH}"
printf 'accel=%s boot_seconds=%s\n' "${ACCEL}" "${SECONDS_TAKEN}" > "${WORK}/timings.txt"
