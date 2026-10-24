#!/usr/bin/env bash
# test-desktop.sh - installs the desktop edition in a clean Ubuntu container and starts its session in a virtual screen.
#
#   docker run --rm -v "$PWD/build/site/repo:/repo:ro" -v "$PWD/tools/package-repo/test-desktop.sh:/test.sh:ro" -v "$PWD/build/desktop:/out" ubuntu:26.04 bash /test.sh
#
# The repository has to be built with BASE_URL=file:///repo and signed with a throwaway key. A container has no screen: the session
# runs in Xvfb, and what the screen looks like is saved in /out as screenshots.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
echo "==> ${CODENAME}: $(. /etc/os-release && echo "${PRETTY_NAME}")"

apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl gnupg >/dev/null

install -m 0644 /repo/totaljs-developer.gpg /usr/share/keyrings/totaljs-test.gpg
echo "deb [signed-by=/usr/share/keyrings/totaljs-test.gpg] file:///repo/ubuntu ${CODENAME} main" > /etc/apt/sources.list.d/totaljs-test.list
apt-get update -qq

echo "==> the sources and the desktop edition"
# the output is kept, and the end of it is shown when apt fails: a failed postinst says which package is the one
install_logged() {
    if ! apt-get install -y "$@" >/tmp/apt.log 2>&1; then
        grep -n -i -E "^E:|dpkg: error|error processing|subprocess|returned error|failed" /tmp/apt.log | tail -30 >&2 || true
        echo "---- the end of the log of apt ----" >&2
        tail -60 /tmp/apt.log >&2
        exit 1
    fi
}
install_logged totaljs-developer-release totaljs-docker-source totaljs-mozilla-source
rm /etc/apt/sources.list.d/totaljs-test.list   # the release package wrote the same source with its own key
apt-get update -qq
install_logged totaljs-developer-desktop

echo "==> what the desktop promises"
for f in /usr/share/themes/TotalJS/openbox-3/themerc /etc/skel/.config/openbox/rc.xml /etc/skel/.config/tint2/tint2rc \
         /usr/bin/totaljs-open /usr/bin/totaljs-wallpaper /etc/lightdm/lightdm.conf.d/50-totaljs.conf /usr/share/applications/totaljs-center.desktop; do
    test -e "${f}" || { echo "missing ${f}" >&2; exit 1; }
done
for xml in /etc/skel/.config/openbox/rc.xml /etc/skel/.config/openbox/menu.xml; do python3 -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "${xml}"; done
test "$(ls /usr/share/backgrounds/totaljs/*.jpg | wc -l)" = 12
command -v firefox >/dev/null
POLICY="$(apt-cache policy firefox)"
case "${POLICY}" in *packages.mozilla.org*) ;; *) echo "${POLICY}" >&2; echo 'firefox does not come from Mozilla' >&2; exit 1 ;; esac

echo "==> the session in a virtual screen"
apt-get install -y -qq --no-install-recommends xvfb imagemagick >/dev/null
useradd -m -s /bin/bash deskuser
chmod 777 /out
test -f /home/deskuser/.config/openbox/rc.xml   # the person got the configuration from /etc/skel
cat > /tmp/session.sh <<'SESSION'
#!/bin/bash
set -e
export HOME=/home/deskuser XDG_RUNTIME_DIR=/tmp/run-deskuser
mkdir -p "${XDG_RUNTIME_DIR}"; chmod 700 "${XDG_RUNTIME_DIR}"
export LIBGL_ALWAYS_SOFTWARE=1
openbox-session >/tmp/openbox.log 2>&1 &
sleep 14
for p in openbox tint2 picom dunst; do pgrep -x "${p}" >/dev/null || { echo "${p} is not running" >&2; cat /tmp/openbox.log >&2; exit 1; }; done
import -window root /out/desktop.png
# the launcher and the right-click menu
alacritty >/tmp/alacritty.log 2>&1 &
sleep 4
import -window root /out/desktop-terminal.png
rofi -show drun >/tmp/rofi.log 2>&1 &
sleep 3
import -window root /out/desktop-launcher.png
SESSION
chmod +x /tmp/session.sh
su deskuser -c 'dbus-run-session -- xvfb-run -a -s "-screen 0 1920x1080x24" /tmp/session.sh'
test -s /out/desktop.png

echo "OK ${CODENAME}"
