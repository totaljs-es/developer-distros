#!/usr/bin/env bash
# arch/iso/build.sh - builds the installation ISO of Total.js Developer for Arch (x86_64) with archiso.
#
# It runs on Arch Linux as root and with permission to mount (a container with --privileged). Needs the package archiso.
#
#   KEY_FILE=public-key.gpg arch/iso/build.sh        # the ISO in build/arch-iso/out
#
# It starts from the profile `releng` that archiso brings (the official installation medium of Arch), so what Arch improves comes with it, and changes only
# what is ours: the name, the menu of the boot, the key of our repository, the configuration of archinstall and the program totaljs-install.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
KEY_FILE="${KEY_FILE:?KEY_FILE is the public key of the repository}"
BUILD="${ROOT}/build/arch-iso"
PROFILE="${BUILD}/profile"
EDITION="${EDITION:-server}"

[ "$(id -u)" = 0 ] || { echo "run this as root: mkarchiso needs to mount" >&2; exit 1; }
[ -d /usr/share/archiso/configs/releng ] || { echo "the package archiso is not installed" >&2; exit 1; }

rm -rf "${BUILD}"
mkdir -p "${BUILD}/out" "${BUILD}/work"
cp -r /usr/share/archiso/configs/releng "${PROFILE}"

# --- what is ours inside the medium
cp -r "${ROOT}/arch/iso/overlay/airootfs/." "${PROFILE}/airootfs/"
install -Dm644 "${KEY_FILE}" "${PROFILE}/airootfs/usr/share/totaljs-developer/repository-key.gpg"
install -Dm644 "${ROOT}/arch/archinstall/server.json" "${PROFILE}/airootfs/usr/share/totaljs-developer/archinstall/server.json"
[ ! -f "${ROOT}/arch/archinstall/desktop.json" ] || install -Dm644 "${ROOT}/arch/archinstall/desktop.json" "${PROFILE}/airootfs/usr/share/totaljs-developer/archinstall/desktop.json"
# the installer starts on the first console (the serial one and the others stay as a plain shell)
cat >> "${PROFILE}/airootfs/root/.zlogin" <<'ZLOGIN'

# Total.js Developer: the installer, on the first console
if [ "$(tty)" = /dev/tty1 ]; then /usr/local/bin/totaljs-install --ask || true; fi
ZLOGIN

# --- the name, and the permissions of what we add
python3 - "${PROFILE}/profiledef.sh" <<'PY'
import re, sys
path = sys.argv[1]
s = open(path).read()
s = re.sub(r'^iso_name=.*$', 'iso_name="totaljs-developer-arch"', s, flags=re.M)
s = re.sub(r'^iso_label=.*$', 'iso_label="TOTALJS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"', s, flags=re.M)
s = re.sub(r'^iso_publisher=.*$', 'iso_publisher="Total.js <https://www.totaljs.com>"', s, flags=re.M)
s = re.sub(r'^iso_application=.*$', 'iso_application="Total.js Developer installation medium"', s, flags=re.M)
s = s.replace('file_permissions=(', 'file_permissions=(\n  ["/usr/local/bin/totaljs-install"]="0:0:755"', 1)
open(path, 'w').write(s)
PY

# --- the menu of the boot (BIOS: syslinux, UEFI: systemd-boot and GRUB): our names, and the edition on the command line
grep -rl 'Arch Linux' "${PROFILE}/syslinux" "${PROFILE}/grub" "${PROFILE}/efiboot" 2>/dev/null | while read -r f; do
    sed -i "s/Arch Linux install medium/Total.js Developer installer/g; s/Arch Linux/Total.js Developer/g" "${f}"
done
grep -rl 'archisobasedir=' "${PROFILE}/syslinux" "${PROFILE}/grub" "${PROFILE}/efiboot" 2>/dev/null | while read -r f; do
    sed -i "/archisobasedir=/ s/\$/ totaljs.edition=${EDITION}/" "${f}"
done

mkarchiso -v -w "${BUILD}/work" -o "${BUILD}/out" "${PROFILE}"
ls -la "${BUILD}/out"
