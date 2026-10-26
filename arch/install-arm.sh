#!/usr/bin/env bash
# install-arm.sh - installs Total.js Developer (server edition) on Arch Linux ARM, on an empty disk. For ARM virtual machines (UTM, Parallels, VMware on a Mac with
# Apple Silicon) and ARM computers that start with UEFI.
#
# Arch Linux has no official ISO for ARM, so this runs from the Archboot AArch64 ISO (https://release.archboot.com/aarch64/latest/iso/): start the machine with it, and at its
# shell run:
#
#   curl -fsSL https://totaljs-es.github.io/developer-distros/repo/arch/install-arm.sh | bash
#
# It asks for the disk, the name of the machine, your user and your password, puts the official root filesystem of Arch Linux ARM on the disk, trusts the key of the
# repository of Total.js, and installs the server edition from it. WHAT IS ON THE DISK IS ERASED.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REPO_URL="${REPO_URL:-https://totaljs-es.github.io/developer-distros/repo}"
KEY_FPR=95454694523B8D18A376F7D5D722BA35C8427B40
ROOTFS_URL="${ROOTFS_URL:-http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz}"
MNT=/mnt/totaljs-arch
GPGDIR=/tmp/totaljs-pacman-gnupg

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1; }
# the questions are answered on the terminal, also when the script comes from a pipe (curl | bash)
ask() { local reply; read -r -p "$1" reply < /dev/tty; printf '%s' "${reply}"; }
ask_secret() { local reply; read -r -s -p "$1" reply < /dev/tty; echo > /dev/tty; printf '%s' "${reply}"; }
cleanup() { umount -R "${MNT}" 2>/dev/null || true; }
trap 'cleanup' EXIT
trap 'echo "The installation stopped. Nothing else has been changed; you can run the script again." >&2' ERR

[ "$(id -u)" = 0 ] || die "run it as root (it is, in Archboot)"
[ "$(uname -m)" = aarch64 ] || die "this is for ARM (aarch64); for Intel and AMD use archinstall (docs/install-arch.md)"
[ -d /sys/firmware/efi ] || die "this needs UEFI: start the machine in UEFI mode"

say "Total.js Developer for Arch Linux ARM"

# --- the questions ----------------------------------------------------------
say "The disk"
lsblk -dpno NAME,SIZE,MODEL,TYPE | awk '$NF == "disk"'
DISK="$(ask 'Disk to erase and install on (for example /dev/vda): ')"
[ -b "${DISK}" ] || die "${DISK} is not a disk"
[ "$(ask "Everything on ${DISK} will be ERASED. Type the name of the disk again to continue: ")" = "${DISK}" ] || die "not confirmed"

list_keymaps() { find /usr/share/kbd/keymaps -name '*.map.gz' -printf '%f\n' 2>/dev/null | sed 's/\.map\.gz$//' | sort -u | "${PAGER:-less}"; }
list_zones() { find /usr/share/zoneinfo -type f -not -path '*/posix/*' -not -path '*/right/*' 2>/dev/null | sed 's#/usr/share/zoneinfo/##' | sort | "${PAGER:-less}"; }
# the layout is applied to the medium at once (the user and the password are typed with it); a name that does not exist is asked again
while :; do
    KEYMAP_NEW="$(ask 'Keyboard layout [us] (for example es, de, fr, uk, latam, it; "list" shows them): ')"; KEYMAP_NEW="${KEYMAP_NEW:-us}"
    if [ "${KEYMAP_NEW}" = list ]; then list_keymaps; continue; fi
    if ! need loadkeys; then break; fi
    if loadkeys "${KEYMAP_NEW}" 2>/dev/null; then break; fi
    echo "the layout '${KEYMAP_NEW}' does not exist: try again (type list to see them)"
done
while :; do
    TZ_NEW="$(ask 'Time zone [UTC] (for example Europe/Madrid, America/Mexico_City; "list" shows them): ')"; TZ_NEW="${TZ_NEW:-UTC}"
    if [ "${TZ_NEW}" = list ]; then list_zones; continue; fi
    if [ ! -d /usr/share/zoneinfo ] || [ -f "/usr/share/zoneinfo/${TZ_NEW}" ]; then break; fi
    echo "the time zone '${TZ_NEW}' does not exist: try again (type list to see them)"
done
# the edition: the entry of the boot menu says it (totaljs.edition=desktop|server); without it, it is asked
EDITION=""
for word in $(cat /proc/cmdline 2>/dev/null); do case "${word}" in totaljs.edition=*) EDITION="${word#totaljs.edition=}" ;; esac; done
while [ "${EDITION}" != desktop ] && [ "${EDITION}" != server ]; do
    EDITION="$(ask 'Edition: desktop (Openbox, Firefox, Chromium) or server (command line) [desktop]: ')"; EDITION="${EDITION:-desktop}"
done
HOSTNAME_NEW="$(ask 'Name of the machine [totaljs]: ')"; HOSTNAME_NEW="${HOSTNAME_NEW:-totaljs}"
USER_NEW="$(ask 'Your user name: ')"
[[ "${USER_NEW}" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || die "the user name has to be lower case letters, numbers, - or _"
PASS1="$(ask_secret 'Your password: ')"; PASS2="$(ask_secret 'Your password again: ')"
[ -n "${PASS1}" ] && [ "${PASS1}" = "${PASS2}" ] || die "the passwords are empty or not the same"
unset PASS2

# --- tools of the installer (Archboot is minimal: some of them have to be restored) ---------------------------------------------
say "Tools"
ALL_TOOLS=1
for t in sgdisk mkfs.fat mkfs.ext4 bsdtar blkid chroot partprobe md5sum; do need "${t}" || ALL_TOOLS=0; done
# the medium of Total.js Developer has them all; Archboot is minimal and some of them have to be restored
if [ "${ALL_TOOLS}" = 0 ]; then
    mkdir -p "${GPGDIR}"; chmod 0700 "${GPGDIR}"
    if need systemctl; then systemctl start systemd-networkd systemd-resolved >/dev/null 2>&1 || true; fi
    for ((i = 0; i < 30; i++)); do curl -fsS -o /dev/null --max-time 5 "${ROOTFS_URL}.md5" && break; sleep 2; done
    curl -fsS -o /dev/null --max-time 5 "${ROOTFS_URL}.md5" || die "no internet: the installer downloads the system"
    if grep -Eq '^[#[:space:]]*GPGDir[[:space:]]*=' /etc/pacman.conf; then sed -Ei "s|^[#[:space:]]*GPGDir[[:space:]]*=.*|GPGDir = ${GPGDIR}|" /etc/pacman.conf
    else sed -i "/^\[options\]$/a GPGDir = ${GPGDIR}" /etc/pacman.conf; fi
    pacman-key --gpgdir "${GPGDIR}" --init
    pacman-key --gpgdir "${GPGDIR}" --populate archlinuxarm
    for attempt in 1 2 3 4 5; do
        pacman -Syy --noconfirm && pacman -S --noconfirm --overwrite '*' coreutils gptfdisk dosfstools e2fsprogs util-linux shadow && break
        [ "${attempt}" -lt 5 ] || die "could not install the tools of the installer"
        sleep $((attempt * 3))
    done
fi
for t in sgdisk mkfs.fat mkfs.ext4 bsdtar blkid chroot; do need "${t}" || die "missing tool: ${t}"; done
for ((i = 0; i < 30; i++)); do curl -fsS -o /dev/null --max-time 5 "${ROOTFS_URL}.md5" && break; sleep 2; done
curl -fsS -o /dev/null --max-time 5 "${ROOTFS_URL}.md5" || die "no internet: the installer downloads the system"

# --- the disk: ESP + root --------------------------------------------------------------------------------------------------------
say "The disk"
swapoff -a 2>/dev/null || true
umount -R "${MNT}" 2>/dev/null || true
wipefs -af "${DISK}" >/dev/null 2>&1 || true
sgdisk --zap-all "${DISK}" >/dev/null
sgdisk --clear --new=1:2048:+512M --typecode=1:ef00 --change-name=1:TOTALJS_EFI --new=2:0:0 --typecode=2:8300 --change-name=2:TOTALJS_ARCH "${DISK}" >/dev/null
partprobe "${DISK}" 2>/dev/null || blockdev --rereadpt "${DISK}" 2>/dev/null || true
udevadm settle 2>/dev/null || true; sleep 2
case "${DISK}" in *[0-9]) PART="${DISK}p" ;; *) PART="${DISK}" ;; esac
mkfs.fat -F 32 -n TOTALJS_EFI "${PART}1" >/dev/null
mkfs.ext4 -F -L TOTALJS_ARCH "${PART}2" >/dev/null
mkdir -p "${MNT}"
mount "${PART}2" "${MNT}"

# --- the root filesystem of Arch Linux ARM, checked --------------------------------------------------------------------------------
say "Arch Linux ARM"
TARBALL=/tmp/archlinuxarm-rootfs.tar.gz
curl -fL --retry 8 --retry-delay 3 "${ROOTFS_URL}" -o "${TARBALL}"
EXPECTED="$(curl -fsSL "${ROOTFS_URL}.md5" | awk '{print $1}')"
[ "$(md5sum "${TARBALL}" | awk '{print $1}')" = "${EXPECTED}" ] || die "the download of Arch Linux ARM is damaged (md5)"
bsdtar -xpf "${TARBALL}" -C "${MNT}"
rm -f "${TARBALL}"

# --- the boot: the kernel on the ESP and systemd-boot (the fallback path of UEFI: it needs no entry in the NVRAM) -----------------
mkdir -p /tmp/totaljs-boot "${MNT}/boot"
cp -a "${MNT}/boot/." /tmp/totaljs-boot/
rm -rf "${MNT}/boot"/*
mount "${PART}1" "${MNT}/boot"
cp -a /tmp/totaljs-boot/. "${MNT}/boot/"
SDBOOT="${MNT}/usr/lib/systemd/boot/efi/systemd-bootaa64.efi"
[ -f "${SDBOOT}" ] || die "systemd-boot is not in the root filesystem"
install -Dm644 "${SDBOOT}" "${MNT}/boot/EFI/BOOT/BOOTAA64.EFI"
install -Dm644 "${SDBOOT}" "${MNT}/boot/EFI/systemd/systemd-bootaa64.efi"
ROOT_PARTUUID="$(blkid -s PARTUUID -o value "${PART}2")"
EFI_PARTUUID="$(blkid -s PARTUUID -o value "${PART}1")"
mkdir -p "${MNT}/boot/loader/entries"
printf 'default totaljs-arch.conf\ntimeout 3\nconsole-mode max\neditor no\n' > "${MNT}/boot/loader/loader.conf"
# preempt=none: with full preemption Arch Linux ARM can corrupt the execution under Apple Virtualization during heavy virtio I/O
cat > "${MNT}/boot/loader/entries/totaljs-arch.conf" <<ENTRY
title Total.js Developer (Arch Linux ARM)
linux /Image
initrd /initramfs-linux.img
options root=PARTUUID=${ROOT_PARTUUID} rw rootwait preempt=none
ENTRY
printf 'PARTUUID=%s / ext4 defaults,noatime 0 1\nPARTUUID=%s /boot vfat defaults 0 2\n' "${ROOT_PARTUUID}" "${EFI_PARTUUID}" > "${MNT}/etc/fstab"

# colour and the candy in pacman, from the start (the first update of the installer already shows the Pac-Man)
for option in Color ILoveCandy; do
    grep -q "^${option}" "${MNT}/etc/pacman.conf" || sed -i "/^\[options\]/a ${option}" "${MNT}/etc/pacman.conf"
done

# --- the system of the person ---------------------------------------------------------------------------------------------------------
say "The system"
echo "${HOSTNAME_NEW}" > "${MNT}/etc/hostname"
echo 'LANG=en_US.UTF-8' > "${MNT}/etc/locale.conf"
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "${MNT}/etc/locale.gen"
cat > "${MNT}/etc/pacman.d/mirrorlist" <<'MIRRORS'
Server = http://mirror.archlinuxarm.org/$arch/$repo
Server = http://de.mirror.archlinuxarm.org/$arch/$repo
Server = http://fr.mirror.archlinuxarm.org/$arch/$repo
Server = http://ca.us.mirror.archlinuxarm.org/$arch/$repo
MIRRORS

# the root filesystem of Arch Linux ARM comes with a user "alarm" and passwords that everybody knows: they go away, and the person you asked for takes the place of the first one
mount -t proc proc "${MNT}/proc"; mount --rbind /sys "${MNT}/sys"; mount --rbind /dev "${MNT}/dev"
rm -f "${MNT}/etc/resolv.conf"; cp -L /etc/resolv.conf "${MNT}/etc/resolv.conf"   # the DNS of this installer, for the chroot (the system gets its own link at the end)
in_target() { chroot "${MNT}" /usr/bin/env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin "$@"; }

in_target pacman-key --init
in_target pacman-key --populate archlinuxarm
in_target userdel -r alarm 2>/dev/null || true
in_target passwd -l root >/dev/null
in_target useradd -m -G wheel -s /bin/bash "${USER_NEW}"
printf '%s:%s\n' "${USER_NEW}" "${PASS1}" | in_target chpasswd
unset PASS1
install -Dm440 /dev/stdin "${MNT}/etc/sudoers.d/10-wheel" <<'SUDO'
%wheel ALL=(ALL:ALL) ALL
SUDO
in_target locale-gen >/dev/null
# the keyboard of the console and the time zone
in_target pacman -S --needed --noconfirm kbd >/dev/null 2>&1 || true
printf 'KEYMAP=%s\n' "${KEYMAP_NEW}" > "${MNT}/etc/vconsole.conf"
if [ -e "${MNT}/usr/share/zoneinfo/${TZ_NEW}" ]; then ln -sf "../usr/share/zoneinfo/${TZ_NEW}" "${MNT}/etc/localtime"
else echo "(the time zone '${TZ_NEW}' does not exist: UTC stays; it is changed later with timedatectl set-timezone)"; fi
in_target systemctl enable systemd-networkd.service systemd-resolved.service systemd-timesyncd.service

# --- the repository of Total.js: its key, and trusted ---------------------------------------------------------------------------------
say "The repository of Total.js"
curl -fsSL "${REPO_URL}/totaljs-developer.gpg" -o "${MNT}/tmp/totaljs-developer.gpg"
[ "$(gpg --show-keys --with-colons "${MNT}/tmp/totaljs-developer.gpg" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')" = "${KEY_FPR}" ] \
    || die "the key of the repository is not the one of Total.js (${KEY_FPR})"
in_target pacman-key --add /tmp/totaljs-developer.gpg
in_target pacman-key --lsign-key "${KEY_FPR}"
printf 'Server = %s/arch/$arch\n' "${REPO_URL}" > "${MNT}/etc/pacman.d/totaljs-developer-mirrorlist"
printf '\n[totaljs-developer]\nSigLevel = Required DatabaseOptional\nInclude = /etc/pacman.d/totaljs-developer-mirrorlist\n' >> "${MNT}/etc/pacman.conf"

# --- the system up to date, and the server edition ------------------------------------------------------------------------------------
say "Updating the system and installing Total.js Developer, ${EDITION} edition (this takes a while)"
in_target pacman -Syu --noconfirm
in_target pacman -S --noconfirm --overwrite /etc/pacman.d/totaljs-developer-mirrorlist totaljs-developer-release "totaljs-developer-${EDITION}"

# the system uses its own DNS (systemd-resolved) from now on
rm -f "${MNT}/etc/resolv.conf"
ln -s ../run/systemd/resolve/stub-resolv.conf "${MNT}/etc/resolv.conf"
sync
umount -R "${MNT}"
trap - EXIT ERR
say "Done. Take out the ISO and restart: the machine starts Total.js Developer. Log in as ${USER_NEW}, and open https://totaljs.developer"
[ "${EDITION}" != desktop ] || echo "The login screen of the desktop appears when it starts."
