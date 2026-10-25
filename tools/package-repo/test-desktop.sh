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
        grep -n -i -A6 -E "dpkg: error processing|trying to overwrite" /tmp/apt.log | head -60 >&2 || true
        echo "---- the end of the log of apt ----" >&2
        tail -60 /tmp/apt.log >&2
        exit 1
    fi
}
install_logged totaljs-developer-release totaljs-docker-source totaljs-mozilla-source
rm /etc/apt/sources.list.d/totaljs-test.list   # the release package wrote the same source with its own key
apt-get update -qq
# the real installer creates the person BEFORE this layer is installed: their home exists, and the packages have to leave ~/.config theirs
useradd -m -s /bin/bash earlyuser
install_logged totaljs-developer-desktop
for item in /home/earlyuser/.config /home/earlyuser/.config/openbox /home/earlyuser/.config/conky; do
    OWNER="$(stat -c %U "${item}")"
    [ "${OWNER}" = earlyuser ] || { echo "${item} belongs to ${OWNER}, not to the person" >&2; exit 1; }
done

echo "==> what the desktop promises"
for f in /usr/share/themes/TotalJS/openbox-3/themerc /etc/skel/.config/openbox/rc.xml /etc/skel/.config/tint2/tint2rc /etc/skel/.config/gtk-3.0/settings.ini \
         /usr/bin/totaljs-open /usr/bin/totaljs-wallpaper /etc/lightdm/lightdm.conf.d/50-totaljs.conf /etc/lightdm/lightdm-gtk-greeter.conf.d/50-totaljs.conf /usr/share/applications/totaljs-center.desktop; do
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
# each process gets up to 30 seconds: the session starts them all at once, and a panel that is started again counts too
for p in openbox tint2 picom dunst conky; do
    for _ in $(seq 1 30); do pgrep -x "${p}" >/dev/null && break; sleep 1; done
    pgrep -x "${p}" >/dev/null || { echo "${p} is not running" >&2; cat /tmp/openbox.log >&2; tail -n +1 "${HOME}"/.cache/*.log >&2 2>/dev/null || true; exit 1; }
done
import -window root /out/desktop.png
# the other profiles of the widget, one screenshot each, and back to the default one
for profile in services compact clock system; do
    totaljs-conky "${profile}"
    sleep 4
    pgrep -x conky >/dev/null || { echo "conky is not running with the profile ${profile}" >&2; exit 1; }
    import -window root "/out/desktop-widget-${profile}.png"
done
# the launcher and the right-click menu
alacritty -vv >/tmp/alacritty.log 2>&1 &
sleep 12
import -window root /out/desktop-terminal.png
# the same screen without the compositor: a window that is blank only with it is a problem of the compositor in a virtual screen
pgrep -x picom >/dev/null && echo "picom is running" || echo "picom is NOT running"
pkill -x picom || true
sleep 3
import -window root /out/desktop-terminal-without-picom.png
G_MESSAGES_DEBUG=all rofi -show drun -show-icons >/tmp/rofi.log 2>&1 &
sleep 3
import -window root /out/desktop-launcher.png
SESSION
chmod +x /tmp/session.sh
# what the programs of the session said goes with the screenshots, because a blank window says nothing by itself
collect_logs() { cp /tmp/openbox.log /tmp/alacritty.log /tmp/rofi.log /out/ 2>/dev/null || true; cp /home/deskuser/.cache/*.log /out/ 2>/dev/null || true; chmod -R a+r /out || true; }
trap collect_logs EXIT
su deskuser -c 'dbus-run-session -- xvfb-run -a -s "-screen 0 1920x1080x24" /tmp/session.sh'
test -s /out/desktop.png

echo "OK ${CODENAME}"
