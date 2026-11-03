#!/usr/bin/env bash
# Runs only inside a disposable live-image rootfs during its build.
set -euo pipefail

[ "${TOTALJS_LIVE_BUILD:-0}" = 1 ] || { echo 'This script is for a live-image build only' >&2; exit 1; }
[ "$(id -u)" = 0 ] || { echo 'The live-image build must run as root' >&2; exit 1; }
BASE="${1:?usage: setup-live.sh <ubuntu|arch> <amd64|arm64>}"
ARCH="${2:?usage: setup-live.sh <ubuntu|arch> <amd64|arm64>}"
case "${BASE}" in ubuntu|arch) ;; *) echo 'Unsupported base' >&2; exit 1 ;; esac
case "${ARCH}" in amd64|arm64) ;; *) echo 'Unsupported architecture' >&2; exit 1 ;; esac
HERE="$(cd "$(dirname "$0")" && pwd)"
PROFILE=/usr/share/totaljs-installer

if [ ! -f "${PROFILE}/installer.json" ]; then
    python3 "${HERE}/render.py" --mode installer --base "${BASE}" --arch "${ARCH}" --output "${PROFILE}"
fi
python3 - "${PROFILE}/installer.json" "${BASE}" "${ARCH}" <<'PROFILE_CHECK'
import json, sys
with open(sys.argv[1]) as file:
    profile = json.load(file)
if profile.get('mode') != 'experimental-online-installer' or profile.get('base') != sys.argv[2] or profile.get('architecture') != sys.argv[3]:
    raise SystemExit('Existing live installer profile does not match this build')
PROFILE_CHECK
getent passwd live >/dev/null || useradd --create-home --shell /bin/bash live
passwd -l live >/dev/null

# Only this fixed, root-owned profile can be launched without a password.
install -d -m 0755 /etc/sudoers.d
cat > /etc/sudoers.d/90-totaljs-live-installer <<'SUDO'
Defaults:live env_keep += "DISPLAY XAUTHORITY"
live ALL=(root) NOPASSWD: /usr/bin/calamares -c /usr/share/totaljs-installer
SUDO
chmod 0440 /etc/sudoers.d/90-totaljs-live-installer
visudo -cf /etc/sudoers.d/90-totaljs-live-installer

install -d /etc/lightdm/lightdm.conf.d /usr/share/applications /home/live/.config/openbox /home/live/Desktop
cat > /etc/lightdm/lightdm.conf.d/90-totaljs-live.conf <<'LIGHTDM'
[Seat:*]
user-session=openbox
autologin-user=live
autologin-user-timeout=0
greeter-session=lightdm-gtk-greeter
LIGHTDM
cat > /home/live/.config/openbox/autostart <<'AUTOSTART'
xsetroot -solid '#20252b'
nm-applet &
tint2 &
for agent in /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1; do
    if [ -x "${agent}" ]; then "${agent}" & break; fi
done
sudo -n /usr/bin/calamares -c /usr/share/totaljs-installer &
AUTOSTART
cat > /usr/share/applications/totaljs-installer.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Install Total.js Developer
Comment=Install the Desktop or Server edition
Exec=sudo -n /usr/bin/calamares -c /usr/share/totaljs-installer
Icon=/usr/share/totaljs-installer/branding/totaljs/logo-totaljs-qt.svg
Terminal=false
Categories=System;
DESKTOP
cp /usr/share/applications/totaljs-installer.desktop /home/live/Desktop/
chown -R live:live /home/live

install -d /etc/NetworkManager/conf.d /etc/polkit-1/rules.d
cat > /etc/NetworkManager/conf.d/90-totaljs-live.conf <<'NETWORK'
[main]
dns=systemd-resolved
NETWORK
# Ubuntu's vendor default excludes wired devices unless a renderer claims them.
# The live session uses NetworkManager directly, without a netplan generator.
cat > /etc/NetworkManager/conf.d/10-globally-managed-devices.conf <<'MANAGED'
[keyfile]
unmanaged-devices=
MANAGED
cat > /etc/polkit-1/rules.d/49-totaljs-live-network.rules <<'POLKIT'
polkit.addRule(function(action, subject) {
    if (subject.user === "live" && subject.local && subject.active &&
        action.id.indexOf("org.freedesktop.NetworkManager.") === 0)
        return polkit.Result.YES;
});
POLKIT
ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

systemctl disable systemd-networkd.service >/dev/null 2>&1 || true
systemctl enable NetworkManager.service lightdm.service
systemctl set-default graphical.target

# A separate marker proves native modules loaded, not just that Linux booted.
install -d /usr/lib/totaljs-live
cat > /usr/lib/totaljs-live/check-installer <<'CHECK'
#!/usr/bin/env bash
set -euo pipefail
for _ in $(seq 1 180); do
    if systemctl is-active --quiet lightdm && pgrep -x calamares >/dev/null; then
        for logfile in /root/.cache/calamares/session.log /home/live/.cache/calamares/session.log; do
            if [ -f "${logfile}" ] && grep -q 'STARTUP: loadModules for all modules done' "${logfile}"; then
                SERIAL=/dev/ttyS0
                [ ! -c /dev/ttyAMA0 ] || SERIAL=/dev/ttyAMA0
                printf 'TOTALJS-CALAMARES-READY\n' > "${SERIAL}"
                exit 0
            fi
        done
    fi
    sleep 2
done
echo 'Calamares did not finish loading its modules' >&2
exit 1
CHECK
chmod 0755 /usr/lib/totaljs-live/check-installer
cat > /etc/systemd/system/totaljs-installer-test.service <<'SERVICE'
[Unit]
Description=Check the graphical Total.js installer loaded its modules
After=lightdm.service
Wants=lightdm.service
[Service]
Type=oneshot
ExecStart=/usr/lib/totaljs-live/check-installer
TimeoutStartSec=400
[Install]
WantedBy=graphical.target
SERVICE
systemctl enable totaljs-installer-test.service
