#!/usr/bin/env bash
# build.sh - builds the live image of Total.js Developer from the packages of Ubuntu, with no installer of Canonical and no marks of Ubuntu.
#
#   docker run --rm --privileged -v "$PWD:/src" -v "$PWD/build/own:/out" ubuntu:26.04 bash /src/iso/own/build.sh /out/totaljs-ubuntu-amd64.iso
#
# It runs in a clean Ubuntu 26.04 (a privileged container: it needs to mount and to chroot). It makes a minimal system with debootstrap, adds a kernel and
# live-boot (which starts a system from a CD), packs it in a squashfs and writes a hybrid ISO (BIOS and UEFI) with grub-mkrescue.
set -euo pipefail

OUT="${1:?usage: build.sh <output.iso>}"
SUITE="${SUITE:-resolute}"
ARCH="${ARCH:-$(dpkg --print-architecture)}"
CALAMARES="${CALAMARES:-0}"
case "${ARCH}" in
    amd64) DEFAULT_MIRROR=https://archive.ubuntu.com/ubuntu; GRUB_PACKAGES='grub-pc-bin grub-efi-amd64-bin' ;;
    arm64) DEFAULT_MIRROR=https://ports.ubuntu.com/ubuntu-ports; GRUB_PACKAGES=grub-efi-arm64-bin ;;
    *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac
[ "${ARCH}" = "$(dpkg --print-architecture)" ] || { echo 'Use a native build container for this architecture' >&2; exit 1; }
case "${CALAMARES}" in 0|1) ;; *) echo 'CALAMARES must be 0 or 1' >&2; exit 1 ;; esac
[ "${CALAMARES}" = 0 ] || [ "${SUITE}" = resolute ] || { echo 'The installer profile targets resolute (26.04)' >&2; exit 1; }
MIRROR="${UBUNTU_MIRROR:-${DEFAULT_MIRROR}}"
WORK="${WORK_DIR:-/tmp/totaljs-own}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
WORK="$(realpath -m "${WORK}")"
case "${WORK}" in /|/tmp|/var|/var/tmp|/out|"${ROOT}") echo 'Unsafe build work directory' >&2; exit 1 ;; esac
for path in "${WORK}/rootfs" "${WORK}/rootfs/dev" "${WORK}/rootfs/dev/pts" "${WORK}/rootfs/proc" "${WORK}/rootfs/sys"; do
    if mountpoint -q "${path}"; then
        echo "A previous build still has mounts at ${path}; unmount it before rebuilding" >&2
        exit 1
    fi
done
export DEBIAN_FRONTEND=noninteractive

log() { printf '==> %s\n' "$*"; }

log "tools"
apt-get update -qq
apt-get install -y -qq --no-install-recommends debootstrap squashfs-tools xorriso ${GRUB_PACKAGES} grub-common mtools dosfstools \
    ca-certificates ubuntu-keyring gnupg >/dev/null

rm -rf "${WORK}"
mkdir -p "${WORK}/rootfs" "${WORK}/tree/live" "${WORK}/tree/boot/grub" "$(dirname "${OUT}")"

cleanup() {
    for mount in dev/pts dev proc sys; do umount -lf "${WORK}/rootfs/${mount}" 2>/dev/null || true; done
}
trap cleanup EXIT

log "debootstrap ${SUITE}"
debootstrap --variant=minbase --arch="${ARCH}" --include=ca-certificates "${SUITE}" "${WORK}/rootfs" "${MIRROR}" >"${WORK}/debootstrap.log" 2>&1 \
    || { tail -40 "${WORK}/debootstrap.log"; exit 1; }

mount -t proc proc "${WORK}/rootfs/proc"
mount -t sysfs sys "${WORK}/rootfs/sys"
mount --bind /dev "${WORK}/rootfs/dev"
mount --make-rslave "${WORK}/rootfs/dev"
mount --bind /dev/pts "${WORK}/rootfs/dev/pts"

# what the image has: the script that runs inside, and the files that it puts in the system
install -m 0755 "${HERE}/chroot-setup.sh" "${WORK}/rootfs/tmp/chroot-setup.sh"
cp -R "${HERE}/rootfs/." "${WORK}/rootfs/"
if [ "${CALAMARES}" = 1 ]; then
    mkdir -p "${WORK}/rootfs/tmp/totaljs-installer-source/shared"
    cp -R "${ROOT}/shared/calamares" "${ROOT}/shared/branding" "${WORK}/rootfs/tmp/totaljs-installer-source/shared/"
    mkdir -p "${WORK}/rootfs/tmp/totaljs-installer-source/docs/images"
    cp "${ROOT}/docs/images/desktop.jpg" "${ROOT}/docs/images/terminal.jpg" "${WORK}/rootfs/tmp/totaljs-installer-source/docs/images/"
fi
printf 'nameserver 9.9.9.9\n' > "${WORK}/rootfs/etc/resolv.conf"

log "the system inside the image"
SUITE="${SUITE}" MIRROR="${MIRROR}" ARCH="${ARCH}" CALAMARES="${CALAMARES}" \
    chroot "${WORK}/rootfs" /bin/bash /tmp/chroot-setup.sh

cleanup
rm -f "${WORK}/rootfs/tmp/chroot-setup.sh"

log "kernel and initrd"
KERNEL="$(ls "${WORK}"/rootfs/boot/vmlinuz-* | sort -V | tail -1)"
INITRD="$(ls "${WORK}"/rootfs/boot/initrd.img-* | sort -V | tail -1)"
cp "${KERNEL}" "${WORK}/tree/live/vmlinuz"
cp "${INITRD}" "${WORK}/tree/live/initrd"

log "squashfs"
mksquashfs "${WORK}/rootfs" "${WORK}/tree/live/filesystem.squashfs" -comp xz -noappend -no-progress -e boot >/dev/null
ls -l "${WORK}/tree/live"

log "the boot menu"
cp "${HERE}/grub.cfg" "${WORK}/tree/boot/grub/grub.cfg"
if [ "${ARCH}" = arm64 ]; then
    sed -i 's/ttyS0/ttyAMA0/g' "${WORK}/tree/boot/grub/grub.cfg"
fi

log "the ISO"
rm -f "${OUT}"
grub-mkrescue -o "${OUT}" "${WORK}/tree" -- -volid TOTALJS_LIVE >"${WORK}/grub-mkrescue.log" 2>&1 || { cat "${WORK}/grub-mkrescue.log"; exit 1; }
ls -l "${OUT}"
