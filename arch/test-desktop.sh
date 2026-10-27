#!/usr/bin/env bash
# arch/test-desktop.sh - installs the desktop edition from the repository that arch/build.sh made, in a container of Arch, and looks at what it promises.
#   arch/test-desktop.sh /path/to/the/folder/with/the/repository
# (No `| grep -q` at the end of a pipe: with pipefail it dies with 141.)
set -Eeuo pipefail
trap 'status=$?; printf "FAILED %s:%s (exit %s): %s\n" "$0" "$LINENO" "$status" "$BASH_COMMAND" >&2; exit "$status"' ERR

REPO="${1:?the folder of the repository (the one with totaljs-developer.db.tar.zst)}"
test -f "${REPO}/totaljs-developer.db.tar.zst"

echo "==> the repository"
if ! grep -q '^\[totaljs-developer\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<CONF

[totaljs-developer]
SigLevel = Optional TrustAll
Server = file://${REPO}
CONF
fi
pacman -Syu --noconfirm

echo "==> install the desktop edition"
# the person that the installer made before the layer (the test of the server may have made it already)
id earlyuser >/dev/null 2>&1 || useradd -m -s /bin/bash earlyuser
pacman -S --noconfirm totaljs-developer-desktop

echo "==> what the desktop promises"
for f in /usr/share/themes/TotalJS/openbox-3/themerc /etc/skel/.config/openbox/rc.xml /etc/skel/.config/openbox/menu.xml /etc/skel/.config/tint2/tint2rc \
         /etc/skel/.config/gtk-3.0/settings.ini /usr/bin/totaljs-open /usr/bin/totaljs-wallpaper /etc/lightdm/lightdm.conf.d/50-totaljs.conf \
         /etc/lightdm/lightdm-gtk-greeter.conf.d/50-totaljs.conf /usr/share/applications/totaljs-center.desktop /usr/share/xsessions/openbox.desktop; do
    test -e "${f}" || { echo "missing ${f}" >&2; exit 1; }
done
for xml in /etc/skel/.config/openbox/rc.xml /etc/skel/.config/openbox/menu.xml; do python -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "${xml}"; done
test "$(ls /usr/share/backgrounds/totaljs/*.jpg | wc -l)" -eq 12
test "$(ls /usr/share/totaljs-developer/icons/*.svg | wc -l)" -ge 10   # the icons of the menu: `include` too
grep -q 'totaljs-wallpaper choose' /etc/skel/.config/openbox/menu.xml
bash -n /usr/bin/totaljs-wallpaper
for c in openbox tint2 picom rofi dunst feh alacritty pcmanfm conky firefox chromium nm-applet pasystray lightdm; do command -v "${c}" >/dev/null || { echo "missing command: ${c}" >&2; exit 1; }; done
test -e /usr/bin/obconf   # the window borders: obconf-qt, with the name of the menu

echo "==> the browsers"
test -f /etc/firefox/policies/policies.json
python -c 'import json; json.load(open("/etc/firefox/policies/policies.json"))'
grep -q 'totaljs-developer.crt' /etc/firefox/policies/policies.json
test -x /usr/bin/totaljs-trust-ca
test -f /etc/xdg/autostart/totaljs-trust-ca.desktop

echo "==> the system starts in the desktop"
test "$(systemctl is-enabled lightdm.service)" = enabled
test "$(systemctl is-enabled NetworkManager.service)" = enabled
test "$(systemctl get-default)" = graphical.target
if systemctl is-enabled systemd-networkd.service >/dev/null 2>&1; then echo 'systemd-networkd is still enabled next to NetworkManager' >&2; exit 1; fi

echo "==> the files of the person that existed before the desktop"
for item in /home/earlyuser/.config /home/earlyuser/.config/openbox /home/earlyuser/.config/tint2; do
    OWNER="$(stat -c %U "${item}")"
    [ "${OWNER}" = earlyuser ] || { echo "${item} belongs to ${OWNER}, not to the person" >&2; exit 1; }
done

echo "OK arch desktop"
