#!/usr/bin/env bash
# Boot the kernel and initramfs of the x86_64 medium against its own ISO.
# This checks the live system, not the BIOS/UEFI boot menus or installation.
set -euo pipefail

ISO="${1:?usage: test-boot.sh <image.iso>}"
WORK="${WORK_DIR:-build/arch-iso/boot}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-600}"
for tool in xorriso python3 qemu-system-x86_64; do
    command -v "${tool}" >/dev/null || { echo "${tool} is required" >&2; exit 1; }
done
[ -f "${ISO}" ] || { echo "${ISO} does not exist" >&2; exit 1; }
mkdir -p "${WORK}/kernel"
xorriso -indev "${ISO}" -pvd_info > "${WORK}/pvd.txt" 2>&1
# xorriso prints Volume Id : 'TOTALJS_...'. Those quotes are formatting,
# not part of the label that archiso must find in /dev/disk/by-label.
LABEL="$(python3 - "${WORK}/pvd.txt" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
match = re.search(r"^Volume Id\s*:\s*'([A-Za-z0-9_-]+)'\s*$", text, re.M)
if not match:
    sys.exit('no supported ISO volume label in xorriso output')
print(match[1])
PY
)"
xorriso -osirrox on -indev "${ISO}" -extract /arch/boot/x86_64 "${WORK}/kernel" > "${WORK}/extract.log" 2>&1
ACCEL=tcg
[ ! -w /dev/kvm ] || ACCEL=kvm
QEMU=""
cleanup() {
    if [ -n "${QEMU}" ]; then
        kill "${QEMU}" 2>/dev/null || true
        wait "${QEMU}" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
echo "==> booting label=${LABEL} accel=${ACCEL} (up to ${BOOT_TIMEOUT} s)"
qemu-system-x86_64 -accel "${ACCEL}" -cpu max -m 3072 -nographic -no-reboot \
    -kernel "${WORK}/kernel/vmlinuz-linux" -initrd "${WORK}/kernel/initramfs-linux.img" \
    -append "archisobasedir=arch archisolabel=${LABEL} console=ttyS0,115200 totaljs.edition=server" \
    -drive "file=${ISO},format=raw,media=cdrom,readonly=on" > "${WORK}/boot.log" 2>&1 &
QEMU=$!
# Read the entire pipe: grep -q can close it early and give sed/tr SIGPIPE,
# which makes a successful match fail under pipefail on a large boot log.
seen() { sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "${WORK}/boot.log" | tr -d '\r' | grep -F "$1" >/dev/null; }
START=$(date +%s)
while true; do
    if seen 'Total.js Developer, installation medium' || { seen 'Reached target Multi-User System' && seen 'Started Getty on tty1'; }; then
        echo "booted: the live system reached its banner or multi-user target with getty"
        printf 'accel=%s boot_seconds=%s\n' "${ACCEL}" "$(( $(date +%s) - START ))" > "${WORK}/timings.txt"
        exit 0
    fi
    kill -0 "${QEMU}" 2>/dev/null || break
    [ "$(( $(date +%s) - START ))" -lt "${BOOT_TIMEOUT}" ] || break
    sleep 2
done
tail -n 80 "${WORK}/boot.log"
echo "the medium did not reach its banner or multi-user target with getty" >&2
exit 1
