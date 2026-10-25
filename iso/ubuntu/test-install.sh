#!/usr/bin/env bash
# test-install.sh - installs an ISO unattended in QEMU, then boots the installed system and waits for its marker.
#
#   iso/ubuntu/test-install.sh <image.iso>
#   SEED_ISO=<seed.iso> iso/ubuntu/test-install.sh <official-ubuntu.iso>   # the way people install: the official ISO and a seed image
#
# It needs qemu-system-x86_64 and qemu-img. With /dev/kvm it takes minutes; without it QEMU emulates the CPU and it takes
# much longer. The logs of the serial console stay in WORK_DIR (install.log and boot.log).
set -euo pipefail

ISO="${1:?usage: test-install.sh <image.iso>}"
WORK="${WORK_DIR:-build/iso}"
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-1500}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-600}"
# What the installed system says on the serial console: a regular expression, so a test can ask for more than "it booted"
MARKER="${MARKER_PATTERN:-TOTALJS-ISO-TEST-OK}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -f "${ISO}" ] || die "${ISO} does not exist"
mkdir -p "${WORK}"

DISK="${WORK}/disk.qcow2"
rm -f "${DISK}" "${WORK}/install.log" "${WORK}/boot.log"
qemu-img create -f qcow2 "${DISK}" 20G >/dev/null

if [ -w /dev/kvm ]; then
    ACCEL="kvm"
    log "KVM is available"
else
    ACCEL="tcg"
    log "KVM is NOT available: QEMU will emulate the CPU and this will be slow"
fi

run_qemu() {
    qemu-system-x86_64 -accel "${ACCEL}" -cpu max -smp 4 -m 4096 \
        -drive "file=${DISK},if=virtio,format=qcow2" \
        -nic user,model=virtio-net-pci \
        -display none -no-reboot "$@"
}

# 1. The install: the autoinstall seed ends with a power off, and -no-reboot makes that end QEMU
log "installing (up to ${INSTALL_TIMEOUT} s)"
START=$(date +%s)
set +e
if [ -n "${SEED_ISO:-}" ]; then
    # The official ISO as it is, and a seed image (label CIDATA) as a second drive: what people do. The kernel is started from the files of the
    # ISO so that the command line can have `autoinstall` and the console (the menu of the ISO has neither; the person confirms the autoinstall).
    [ -f "${SEED_ISO}" ] || die "${SEED_ISO} does not exist"
    xorriso -osirrox on -indev "${ISO}" -extract /casper/vmlinuz "${WORK}/vmlinuz" -extract /casper/initrd "${WORK}/initrd" >/dev/null 2>&1 \
        || die "could not read the kernel and the initrd from ${ISO}"
    qemu-system-x86_64 -accel "${ACCEL}" -cpu max -smp 4 -m 4096 \
        -drive "file=${DISK},if=virtio,format=qcow2" \
        -drive "file=${ISO},media=cdrom,if=ide,index=2,readonly=on" -drive "file=${SEED_ISO},media=cdrom,if=ide,index=3,readonly=on" \
        -kernel "${WORK}/vmlinuz" -initrd "${WORK}/initrd" -append "autoinstall console=ttyS0,115200n8 ---" \
        -nic user,model=virtio-net-pci -display none -no-reboot \
        -serial "file:${WORK}/install.log" &
else
    qemu-system-x86_64 -accel "${ACCEL}" -cpu max -smp 4 -m 4096 \
        -drive "file=${DISK},if=virtio,format=qcow2" -cdrom "${ISO}" -boot d \
        -nic user,model=virtio-net-pci -display none -no-reboot \
        -serial "file:${WORK}/install.log" &
fi
QEMU=$!

# The installer powers the machine off when it is done. When it fails it stays on an error screen and never ends, so the test
# does not wait for the limit: it looks at the console, and when it sees the error it gives the commands of the seed a moment
# to say what they know and stops.
STATUS=""
LAST_SIGN=0
while kill -0 "${QEMU}" 2>/dev/null; do
    sleep 5
    ELAPSED=$(( $(date +%s) - START ))

    if grep -a -q "An error occurred. Press enter to start a shell" "${WORK}/install.log" 2>/dev/null; then
        log "the installer reports an error: waiting 25 s for its error commands, then stopping"
        sleep 25
        STATUS=99
        break
    fi
    if [ "${ELAPSED}" -ge "${INSTALL_TIMEOUT}" ]; then STATUS=124; break; fi

    if [ $(( ELAPSED - LAST_SIGN )) -ge 60 ]; then
        LAST_SIGN=${ELAPSED}
        printf -- '--- %s s: install.log is %s bytes; its end: %s\n' "${ELAPSED}" \
            "$(wc -c < "${WORK}/install.log" 2>/dev/null | tr -d ' ')" \
            "$(tail -c 400 "${WORK}/install.log" 2>/dev/null | tr -cd '[:print:]' | tail -c 200)"
    fi
done

if [ -n "${STATUS}" ]; then
    kill "${QEMU}" 2>/dev/null
    wait "${QEMU}" 2>/dev/null
else
    wait "${QEMU}"
    STATUS=$?
fi
set -e
INSTALL_SECONDS=$(( $(date +%s) - START ))

if [ "${STATUS}" -ne 0 ]; then
    echo "--- the end of the install log (the printable part) ---"; tail -c 12000 "${WORK}/install.log" | tr -cd '[:print:]\n' | tail -80 || true
    die "the install did not finish (status ${STATUS}) after ${INSTALL_SECONDS} s"
fi
log "installed in ${INSTALL_SECONDS} s"

# 2. The installed system: it has to say that it booted
log "booting the installed system (up to ${BOOT_TIMEOUT} s)"
START=$(date +%s)
run_qemu -serial "file:${WORK}/boot.log" &
QEMU=$!

FOUND=0
for _ in $(seq 1 "${BOOT_TIMEOUT}"); do
    if grep -q -E "${MARKER}" "${WORK}/boot.log" 2>/dev/null; then FOUND=1; break; fi
    kill -0 "${QEMU}" 2>/dev/null || break
    sleep 1
done
BOOT_SECONDS=$(( $(date +%s) - START ))
kill "${QEMU}" 2>/dev/null || true
wait "${QEMU}" 2>/dev/null || true

if [ "${FOUND}" -ne 1 ]; then
    echo "--- the end of the boot log ---"; tail -40 "${WORK}/boot.log" || true
    die "the installed system did not say ${MARKER} in ${BOOT_SECONDS} s"
fi
log "the installed system booted in ${BOOT_SECONDS} s"

printf 'accel=%s install_seconds=%s boot_seconds=%s\n' "${ACCEL}" "${INSTALL_SECONDS}" "${BOOT_SECONDS}" > "${WORK}/timings.txt"
