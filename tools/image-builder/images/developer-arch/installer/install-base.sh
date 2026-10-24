#!/usr/bin/env bash
# Runs inside Archboot (booted by the totalvm-builder runner on Apple's
# Virtualization framework — no QEMU). Creates a portable UEFI Arch Linux ARM
# base on /dev/vda.
#
# The published "latest" Archboot AArch64 ISO is a minimal environment: it ships
# pacman, curl, bsdtar and blkid but NOT the partitioning / mkfs / systemd-boot
# tools. It does have working NAT networking, so we pull the few tools we need
# with pacman, and we install systemd-boot by copying the EFI binary straight
# out of the extracted root filesystem (no bootctl required).
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
trap 'echo TOTALJS_ARCH_BASE_FAILED' ERR

DISK=/dev/vda
MNT=/mnt/totaljs-arch
# Prefer a host-provided tarball (virtiofs share) to avoid re-downloading the
# image the host already verified; fall back to the official mirror.
ROOTFS_LOCAL="${ROOTFS_LOCAL:-}"
ROOTFS_URL="${ROOTFS_URL:-http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}"

need() { command -v "$1" >/dev/null 2>&1; }

# Archboot's stock list contains only the GeoIP redirector. If the selected
# backend stalls, pacman exhausts that one server and the whole image build
# dies before our resilient provisioning wrapper exists. Use official,
# push-synchronised European mirrors first and keep GeoIP/US as fallbacks.
cat > /etc/pacman.d/mirrorlist <<'EOF'
Server = http://de3.mirror.archlinuxarm.org/$arch/$repo
Server = http://fr.mirror.archlinuxarm.org/$arch/$repo
Server = http://gr.mirror.archlinuxarm.org/$arch/$repo
Server = http://mirror.archlinuxarm.org/$arch/$repo
Server = http://ca.us.mirror.archlinuxarm.org/$arch/$repo
EOF

# Five simultaneous downloads can push every connection below libalpm's
# low-speed threshold on a busy mirror. Two still overlap latency without
# starving individual package transfers.
if grep -Eq '^[#[:space:]]*ParallelDownloads[[:space:]]*=' /etc/pacman.conf; then
    sed -Ei 's/^[#[:space:]]*ParallelDownloads[[:space:]]*=.*/ParallelDownloads = 2/' \
        /etc/pacman.conf
else
    sed -i '/^\[options\]$/a ParallelDownloads = 2' /etc/pacman.conf
fi

# The Archboot runtime intentionally starts without a persistent pacman
# keyring. New packages then trigger an attempted key download, but its default
# GPG directory lives on the immutable installer filesystem. Build a complete
# temporary keyring in RAM and point both pacman and pacman-key at it.
BOOTSTRAP_GPGDIR=/tmp/totaljs-pacman-gnupg
rm -rf "${BOOTSTRAP_GPGDIR}"
mkdir -p "${BOOTSTRAP_GPGDIR}"
chmod 0700 "${BOOTSTRAP_GPGDIR}"
if grep -Eq '^[#[:space:]]*GPGDir[[:space:]]*=' /etc/pacman.conf; then
    sed -Ei "s|^[#[:space:]]*GPGDir[[:space:]]*=.*|GPGDir = ${BOOTSTRAP_GPGDIR}|" \
        /etc/pacman.conf
else
    sed -i "/^\[options\]$/a GPGDir = ${BOOTSTRAP_GPGDIR}" /etc/pacman.conf
fi
pacman-key --gpgdir "${BOOTSTRAP_GPGDIR}" --init
pacman-key --gpgdir "${BOOTSTRAP_GPGDIR}" --populate archlinuxarm

install_bootstrap_packages() {
    local attempt
    local -a timeout_option
    for ((attempt=1; attempt<=5; attempt++)); do
        timeout_option=()
        # Normal attempts fail over quickly. Only the final two tolerate an
        # extremely slow but still progressing official mirror indefinitely.
        if (( attempt >= 4 )); then
            timeout_option=(--disable-download-timeout)
        fi
        echo "[arch-base] package bootstrap attempt ${attempt}/5"
        if pacman -Syy --noconfirm "${timeout_option[@]}" \
            && pacman -S --noconfirm --overwrite '*' "${timeout_option[@]}" \
                coreutils gptfdisk dosfstools e2fsprogs util-linux shadow; then
            return 0
        fi
        rm -f /var/cache/pacman/pkg/*.part 2>/dev/null || true
        sleep $((attempt * 3))
    done
    return 1
}

# --- Bring up networking, then fetch the missing installer tools ------------
systemctl start systemd-networkd systemd-resolved >/dev/null 2>&1 || true
if ! need sgdisk || ! need mkfs.ext4 || ! need mkfs.fat || ! need partprobe; then
    online=0
    for ((i=0; i<30; i++)); do
        if curl -fsS -o /dev/null --max-time 5 "${ROOTFS_URL}.md5"; then online=1; break; fi
        sleep 2
    done
    [ "${online}" -eq 1 ] || echo "warning: network not confirmed; pacman may fail" >&2
    # The minimal Archboot lists these packages as installed in pacman's DB but
    # strips many of their binaries to shrink the image (sgdisk, mkfs.*, and even
    # coreutils applets like chroot/sync/seq are absent), so `--needed` would skip
    # them. Reinstall unconditionally (no --needed) to restore the actual files.
    install_bootstrap_packages
fi
for t in sgdisk mkfs.fat mkfs.ext4 bsdtar blkid; do
    need "$t" || { echo "required tool missing after setup: $t" >&2; false; }
done

# --- Partition: 512 MiB ESP + ext4 root ------------------------------------
swapoff -a 2>/dev/null || true
umount -R "${MNT}" 2>/dev/null || true
wipefs -af "${DISK}" 2>/dev/null || true
sgdisk --zap-all "${DISK}"
sgdisk --clear \
    --new=1:2048:+512M --typecode=1:ef00 --change-name=1:TOTALJS_EFI \
    --new=2:0:0 --typecode=2:8300 --change-name=2:TOTALJS_ARCH \
    "${DISK}"
partprobe "${DISK}" 2>/dev/null || blockdev --rereadpt "${DISK}" 2>/dev/null || true
udevadm settle 2>/dev/null || true
sleep 2

mkfs.fat -F 32 -n TOTALJS_EFI "${DISK}1"
mkfs.ext4 -F -L TOTALJS_ARCH "${DISK}2"
mkdir -p "${MNT}"
mount "${DISK}2" "${MNT}"

# --- Root filesystem -------------------------------------------------------
TARBALL=/tmp/archlinuxarm-rootfs.tar.gz
CLEANUP_TARBALL=1
if [ -n "${ROOTFS_LOCAL}" ] && [ -f "${ROOTFS_LOCAL}" ]; then
    echo "using host-provided rootfs: ${ROOTFS_LOCAL}"
    TARBALL="${ROOTFS_LOCAL}"
    CLEANUP_TARBALL=0
else
    echo "downloading rootfs: ${ROOTFS_URL}"
    curl -fL --retry 8 --retry-delay 3 "${ROOTFS_URL}" -o "${TARBALL}"
fi
bsdtar -xpf "${TARBALL}" -C "${MNT}"
[ "${CLEANUP_TARBALL}" -eq 1 ] && rm -f "${TARBALL}"

# Keep GeoIP as the best default for the distributed image, but do not leave
# installed systems with a single point of failure during updates.
cat > "${MNT}/etc/pacman.d/mirrorlist" <<'EOF'
Server = http://mirror.archlinuxarm.org/$arch/$repo
Server = http://de.mirror.archlinuxarm.org/$arch/$repo
Server = http://de3.mirror.archlinuxarm.org/$arch/$repo
Server = http://fr.mirror.archlinuxarm.org/$arch/$repo
Server = http://ca.us.mirror.archlinuxarm.org/$arch/$repo
Server = http://nj.us.mirror.archlinuxarm.org/$arch/$repo
EOF
if grep -Eq '^[#[:space:]]*ParallelDownloads[[:space:]]*=' "${MNT}/etc/pacman.conf"; then
    sed -Ei 's/^[#[:space:]]*ParallelDownloads[[:space:]]*=.*/ParallelDownloads = 3/' \
        "${MNT}/etc/pacman.conf"
else
    sed -i '/^\[options\]$/a ParallelDownloads = 3' "${MNT}/etc/pacman.conf"
fi

# --- Boot: kernel/initramfs on the ESP, systemd-boot via the fallback path --
mkdir -p /tmp/totaljs-boot "${MNT}/boot"
cp -a "${MNT}/boot/." /tmp/totaljs-boot/
rm -rf "${MNT}/boot"/*
mount "${DISK}1" "${MNT}/boot"
cp -a /tmp/totaljs-boot/. "${MNT}/boot/"

# Install systemd-boot by copying the EFI binary out of the rootfs (the minimal
# Archboot has no bootctl). EFI/BOOT/BOOTAA64.EFI is the architecture-defined
# removable-media fallback, so the firmware boots it with no NVRAM entry.
SDBOOT="${MNT}/usr/lib/systemd/boot/efi/systemd-bootaa64.efi"
[ -f "${SDBOOT}" ] || { echo "systemd-boot EFI binary not found in rootfs" >&2; false; }
install -Dm644 "${SDBOOT}" "${MNT}/boot/EFI/BOOT/BOOTAA64.EFI"
install -Dm644 "${SDBOOT}" "${MNT}/boot/EFI/systemd/systemd-bootaa64.efi"

ROOT_PARTUUID="$(blkid -s PARTUUID -o value "${DISK}2")"
EFI_PARTUUID="$(blkid -s PARTUUID -o value "${DISK}1")"
mkdir -p "${MNT}/boot/loader/entries"
cat > "${MNT}/boot/loader/loader.conf" <<'EOF'
default totaljs-arch.conf
timeout 0
console-mode max
editor no
EOF
cat > "${MNT}/boot/loader/entries/totaljs-arch.conf" <<EOF
title Total.js Developer (Arch Linux)
linux /Image
initrd /initramfs-linux.img
# Arch Linux ARM currently enables full dynamic preemption. Under Apple
# Virtualization that mode can corrupt execution during sustained virtio I/O
# (the failure surfaces in unrelated paths such as virtio_net and seccomp).
# A development VM values deterministic stability over sub-millisecond kernel
# latency, so keep preemption disabled for this image.
options root=PARTUUID=${ROOT_PARTUUID} rw rootwait console=hvc0 preempt=none
EOF
cat > "${MNT}/etc/fstab" <<EOF
PARTUUID=${ROOT_PARTUUID} / ext4 defaults,noatime,nodiscard 0 1
PARTUUID=${EFI_PARTUUID} /boot vfat defaults 0 2
EOF

echo totalvm > "${MNT}/etc/hostname"
echo 'LANG=en_US.UTF-8' > "${MNT}/etc/locale.conf"
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "${MNT}/etc/locale.gen"
# Set the root password without chroot — this minimal Archboot has no chroot
# binary. chpasswd --root edits the target's /etc/shadow directly so the
# provisioning step can log in as root/root. The unprivileged "totaljs"
# bootstrap account is created later by 00-base.sh inside the installed system.
echo 'root:root' | chpasswd --root "${MNT}"

systemctl --root="${MNT}" enable systemd-networkd.service systemd-resolved.service \
    systemd-timesyncd.service sshd.service serial-getty@hvc0.service
ln -sf /run/systemd/resolve/stub-resolv.conf "${MNT}/etc/resolv.conf"

sync 2>/dev/null || true
umount -R "${MNT}"
echo TOTALJS_ARCH_BASE_READY
poweroff
