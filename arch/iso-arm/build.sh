#!/usr/bin/env bash
# arch/iso-arm/build.sh - builds the installation ISO of Total.js Developer for Arch Linux ARM (aarch64).
#
# archiso does not support ARM, so the ISO is made with the same pieces by hand: the root filesystem of Arch Linux ARM, a live system in a SquashFS and the initramfs
# of archiso (mkinitcpio-archiso), a kernel that boots straight from UEFI (linux-aarch64 is an EFI stub) and GRUB for UEFI. It starts in virtual machines
# (UTM, Parallels, VMware, QEMU) and in ARM computers with UEFI, from a DVD image or a USB stick.
#
# It runs as root on an ARM machine (the runner arm64 of GitHub, or a virtual machine of ARM): the chroot of the aarch64 system is native, with no emulation.
#   Needs: libarchive-tools squashfs-tools xorriso mtools dosfstools grub-efi-arm64-bin curl
#   KEY_FILE=public-key.gpg arch/iso-arm/build.sh        # the ISO in build/arch-iso-arm/out
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KEY_FILE="${KEY_FILE:?KEY_FILE is the public key of the repository}"
BUILD="${ROOT}/build/arch-iso-arm"
RFS="${BUILD}/rootfs"
ISO="${BUILD}/iso"
OUT="${BUILD}/out"
ROOTFS_URL="${ROOTFS_URL:-http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}"
LABEL="TOTALJS_ARM_$(date +%Y%m)"
VERSION="$(date +%Y.%m.%d)"
EDITION="${EDITION:-server}"

[ "$(id -u)" = 0 ] || { echo "run this as root" >&2; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "this builds on an ARM machine (aarch64)" >&2; exit 1; }

# what pacman-key leaves running in the chroot (gpg-agent, dirmngr) keeps the mounts busy and they stay mounted: those processes are stopped first
cleanup() {
    local pid
    for pid in /proc/[0-9]*; do
        case "$(readlink "${pid}/root" 2>/dev/null)" in "${RFS}"|"${RFS}"/*) kill "${pid#/proc/}" 2>/dev/null || true ;; esac
    done
    sleep 1
    umount -R -l "${RFS}" 2>/dev/null || true
}
trap cleanup EXIT
in_rfs() { chroot "${RFS}" /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin "$@"; }

mkdir -p "${BUILD}"
rm -rf "${RFS}" "${ISO}" "${OUT}"
mkdir -p "${RFS}" "${ISO}/arch/boot/aarch64" "${ISO}/arch/aarch64" "${ISO}/EFI/BOOT" "${OUT}"

echo "==> the root filesystem of Arch Linux ARM"
if [ ! -f "${BUILD}/rootfs.tar.gz" ]; then
    curl -fL --retry 8 --retry-delay 3 "${ROOTFS_URL}" -o "${BUILD}/rootfs.tar.gz"
    [ "$(md5sum "${BUILD}/rootfs.tar.gz" | awk '{print $1}')" = "$(curl -fsSL "${ROOTFS_URL}.md5" | awk '{print $1}')" ] || { echo "the root filesystem is damaged (md5)" >&2; exit 1; }
fi
bsdtar -xpf "${BUILD}/rootfs.tar.gz" -C "${RFS}"
# pacman checks the free space of the mount point of its cache: the folder of the system has to be one (arch-chroot does the same)
mount --bind "${RFS}" "${RFS}"
mount -t proc proc "${RFS}/proc"; mount --rbind /sys "${RFS}/sys"; mount --rbind /dev "${RFS}/dev"
rm -f "${RFS}/etc/resolv.conf"; cp -L /etc/resolv.conf "${RFS}/etc/resolv.conf"

echo "==> the live system"
in_rfs pacman-key --init
in_rfs pacman-key --populate archlinuxarm
in_rfs pacman -Syu --noconfirm
# what the installer needs inside the medium: disks, the root filesystem (bsdtar), network (iwd for Wi-Fi), an editor
in_rfs pacman -S --noconfirm --needed mkinitcpio-archiso pv gptfdisk dosfstools e2fsprogs util-linux parted libarchive curl iwd nano

# our files: the installer, the key and the banner (the same ones of the ISO of x86_64)
cp -r "${ROOT}/arch/iso/overlay/airootfs/." "${RFS}/"
install -Dm644 "${KEY_FILE}" "${RFS}/usr/share/totaljs-developer/repository-key.gpg"
install -Dm755 "${ROOT}/arch/install-arm.sh" "${RFS}/usr/local/bin/totaljs-install-arm"
chmod 755 "${RFS}/usr/local/bin/totaljs-install"
sed -i 's/Based on Arch Linux\./Based on Arch Linux ARM./' "${RFS}/etc/motd"

# root logs in by itself on the first console and on the serial one; on the first one the installer starts
mkdir -p "${RFS}/etc/systemd/system/getty@tty1.service.d" "${RFS}/etc/systemd/system/serial-getty@ttyAMA0.service.d"
cat > "${RFS}/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'AUTOLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin root %I $TERM
AUTOLOGIN
cat > "${RFS}/etc/systemd/system/serial-getty@ttyAMA0.service.d/autologin.conf" <<'AUTOLOGIN'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --keep-baud 115200,57600,38400,9600 --autologin root %I $TERM
AUTOLOGIN
in_rfs systemctl enable getty@tty1.service serial-getty@ttyAMA0.service systemd-networkd.service systemd-resolved.service iwd.service
in_rfs passwd -d root >/dev/null
cat > "${RFS}/root/.bash_profile" <<'PROFILE'
[ -f ~/.bashrc ] && . ~/.bashrc
# Total.js Developer: the installer, on the first console
if [ "$(tty)" = /dev/tty1 ]; then /usr/local/bin/totaljs-install --ask || true; fi
PROFILE
echo totaljs-installer > "${RFS}/etc/hostname"
# nothing of the keys of the machine that builds the medium
rm -f "${RFS}/etc/machine-id" "${RFS}"/etc/ssh/ssh_host_*

echo "==> the initramfs of archiso"
KERNEL="$(ls "${RFS}/usr/lib/modules" | head -n 1)"
MODDIR="${RFS}/usr/lib/modules/${KERNEL}"
# the modules that the medium needs: only the ones that this kernel has as modules go into the list (mkinitcpio fails with the ones that it has built in or does not have)
MODS=()
for m in loop squashfs overlay isofs sr_mod virtio_blk virtio_scsi virtio_pci virtio_net usb_storage uas; do
    if grep -qE "/${m}\.ko(\.[a-z]+)?:" "${MODDIR}/modules.dep"; then MODS+=("${m}"); echo "module: ${m}"
    elif grep -qE "/${m}\.ko" "${MODDIR}/modules.builtin"; then echo "built in: ${m}"
    else
        echo "missing: ${m}"
        case "${m}" in loop|squashfs|overlay) echo "the kernel ${KERNEL} has not ${m}, which the live system needs" >&2; exit 1 ;; esac
    fi
done
cat > "${RFS}/etc/mkinitcpio-live.conf" <<CONF
MODULES=(${MODS[*]})
BINARIES=()
FILES=()
HOOKS=(base udev modconf archiso archiso_loop_mnt block filesystems keyboard)
COMPRESSION="gzip"
CONF
echo "hooks of mkinitcpio: $(ls "${RFS}/usr/lib/initcpio/install" | tr '\n' ' ')"
in_rfs mkinitcpio -c /etc/mkinitcpio-live.conf -k "${KERNEL}" -g /boot/initramfs-live.img 2>&1 | tee "${BUILD}/mkinitcpio.log" || { echo "--- mkinitcpio failed (the errors are above)"; grep -n -i -E "error|not found|cannot" "${BUILD}/mkinitcpio.log" >&2 || true; exit 1; }
# mkinitcpio says that the image may not be complete when it finds an error, and still exits with 0 in some versions
if grep -q -E "^==> ERROR|ERROR:" "${BUILD}/mkinitcpio.log"; then grep -n -E "ERROR" "${BUILD}/mkinitcpio.log" >&2; exit 1; fi
cp "${RFS}/boot/Image" "${ISO}/arch/boot/aarch64/Image"
cp "${RFS}/boot/initramfs-live.img" "${ISO}/arch/boot/aarch64/initramfs-linux.img"
rm -f "${RFS}/etc/resolv.conf"; ln -s ../run/systemd/resolve/stub-resolv.conf "${RFS}/etc/resolv.conf"
rm -rf "${RFS}/var/cache/pacman/pkg"/*

echo "==> the live system in a SquashFS (gzip: the kernel of Arch Linux ARM reads it without more modules)"
cleanup
# the mounts are gone: if /proc or /dev were still mounted, mksquashfs would walk through them for ever
for d in proc sys dev; do [ -z "$(ls -A "${RFS}/${d}" 2>/dev/null)" ] || { echo "${RFS}/${d} is still mounted: the build stops" >&2; exit 1; }; done
rm -rf "${RFS}"/boot/*   # the kernel and the initramfs go next to the SquashFS, not inside it
mksquashfs "${RFS}" "${ISO}/arch/aarch64/airootfs.sfs" -comp gzip -noappend -no-progress

echo "==> the boot: GRUB for UEFI"
cat > "${BUILD}/grub-embedded.cfg" <<GRUBCFG
search --no-floppy --set=root --label ${LABEL}
set default=0
set timeout=5
menuentry "Total.js Developer installer (aarch64, ${EDITION} edition)" {
    linux /arch/boot/aarch64/Image archisobasedir=arch archisolabel=${LABEL} console=tty0 console=ttyAMA0,115200 totaljs.edition=${EDITION}
    initrd /arch/boot/aarch64/initramfs-linux.img
}
GRUBCFG
grub-mkstandalone -O arm64-efi -o "${ISO}/EFI/BOOT/BOOTAA64.EFI" --modules="part_gpt part_msdos iso9660 search search_label normal linux configfile" "boot/grub/grub.cfg=${BUILD}/grub-embedded.cfg"
# the image of the ESP that goes into the ISO (the firmware of a computer reads it from the GPT of the USB stick or from the El Torito entry of the DVD)
EFIIMG="${BUILD}/efiboot.img"
truncate -s 32M "${EFIIMG}"
mkfs.vfat -n TOTALJS_EFI "${EFIIMG}" >/dev/null
mmd -i "${EFIIMG}" ::/EFI ::/EFI/BOOT
mcopy -i "${EFIIMG}" "${ISO}/EFI/BOOT/BOOTAA64.EFI" ::/EFI/BOOT/

echo "==> the ISO"
xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -joliet -joliet-long -rational-rock \
    -volid "${LABEL}" -appid "Total.js Developer installation medium" -publisher "Total.js <https://www.totaljs.com>" \
    -append_partition 2 0xef "${EFIIMG}" -appended_part_as_gpt \
    -eltorito-alt-boot -e --interval:appended_partition_2:all:: -no-emul-boot -isohybrid-gpt-basdat \
    -output "${OUT}/totaljs-developer-arch-${VERSION}-aarch64.iso" "${ISO}"
ls -la "${OUT}"
