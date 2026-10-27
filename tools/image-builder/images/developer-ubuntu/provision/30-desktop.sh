#!/usr/bin/env bash
# Step 30 (Ubuntu) — ArchLabs-inspired Openbox desktop.
# Installs the Debian/Ubuntu packages, then writes the shared configuration
# (assets/desktop/desktop-config.sh, used by the Arch image too).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get install -y --no-install-recommends \
    "linux-modules-extra-$(uname -r)" \
    xorg xserver-xorg \
    openbox obconf \
    tint2 \
    lightdm lightdm-gtk-greeter \
    rofi \
    pcmanfm gvfs xarchiver \
    conky-all \
    alacritty \
    feh picom \
    lxappearance lxappearance-obconf \
    arc-theme papirus-icon-theme \
    adwaita-icon-theme-full librsvg2-common shared-mime-info \
    fonts-firacode fonts-noto locales \
    network-manager network-manager-gnome policykit-1-gnome \
    avahi-daemon libnss-mdns \
    pipewire pipewire-pulse wireplumber alsa-utils pavucontrol pasystray \
    gsimplecal \
    dbus-x11 xdg-utils python3-xdg spice-vdagent \
    x11-xserver-utils x11-utils xdotool dunst libnotify-bin scrot \
    mesa-utils libgl1-mesa-dri libglx-mesa0 \
    imagemagick

bash "${TOTALVM_ASSETS:-/mnt/assets}/desktop/desktop-config.sh"

# Alacritty is the only terminal in the Ubuntu desktop. The xorg metapackage
# accepts any provider of x-terminal-emulator, so xterm is unnecessary. Set the
# Debian alternative for generic desktop utilities and LibFM's own preference
# for PCManFM, whose internal fallback is otherwise hard-coded to xterm.
update-alternatives --install \
    /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/alacritty 60
update-alternatives --set x-terminal-emulator /usr/bin/alacritty

install -d -o totaljs -g totaljs /home/totaljs/.config/libfm
cat > /home/totaljs/.config/libfm/libfm.conf <<'EOF'
[config]
terminal=alacritty
archiver=xarchiver
EOF
chown totaljs:totaljs /home/totaljs/.config/libfm/libfm.conf
install -d /etc/skel/.config/libfm
install -m 0644 /home/totaljs/.config/libfm/libfm.conf \
    /etc/skel/.config/libfm/libfm.conf

cat > /etc/profile.d/totaljs-terminal.sh <<'EOF'
export TERMINAL=alacritty
EOF
chmod 0644 /etc/profile.d/totaljs-terminal.sh
grep -q '^TERMINAL=' /etc/environment \
    && sed -i 's|^TERMINAL=.*|TERMINAL=alacritty|' /etc/environment \
    || printf '%s\n' 'TERMINAL=alacritty' >> /etc/environment

# Also removes uxterm, which is shipped by the same package. This is normally
# already absent on a fresh build now that it is no longer requested above.
apt-get purge -y xterm

# Openbox can execute its autostart file before the root window is fully ready.
# Conky then exits immediately, even though selecting a profile later works.
# Start it once the session is usable and retry once if X rejected the first
# window. Keep this Ubuntu-specific so the finished Arch image is untouched.
cat > /usr/local/bin/totaljs-conky-autostart <<'EOF'
#!/usr/bin/env bash
set -u

LOG="${HOME}/.cache/conky-autostart.log"
mkdir -p "${HOME}/.cache"

for _ in $(seq 1 20); do
    if pgrep -u "$(id -u)" -x openbox >/dev/null 2>&1 \
        && xset q >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

totaljs-conky restore >>"${LOG}" 2>&1 || true
sleep 3
if ! pgrep -u "$(id -u)" -x conky >/dev/null 2>&1; then
    echo "Conky did not stay running; retrying after session startup" >>"${LOG}"
    totaljs-conky restore >>"${LOG}" 2>&1 || true
fi
EOF
chmod 0755 /usr/local/bin/totaljs-conky-autostart
# Finish painting the root window before Conky creates its desktop window.
# Running both concurrently let a late `feh` invocation cover Conky until the
# user selected a profile manually.
sed -i 's|^totaljs-wallpaper &$|totaljs-wallpaper|' \
    /home/totaljs/.config/openbox/autostart
sed -i \
    's|^totaljs-conky restore &$|/usr/local/bin/totaljs-conky-autostart \&|' \
    /home/totaljs/.config/openbox/autostart

# Ubuntu's ImageMagick launcher uses a dotted icon name. Rofi can resolve it,
# but the Openbox pipe-menu resolver mistakes `.q16` for a file extension. Use
# Papirus' wizard-hat artwork through an absolute path in both the package entry
# (read first by the pipe menu) and the local override (read first by Rofi).
IMAGEMAGICK_DESKTOP=/usr/share/applications/display-im6.q16.desktop
IMAGEMAGICK_ICON=/usr/share/icons/Papirus/48x48/apps/display.im6.svg
if [ -f "${IMAGEMAGICK_DESKTOP}" ] && [ -f "${IMAGEMAGICK_ICON}" ]; then
    install -d /usr/local/share/applications
    sed -i "s|^Icon=.*|Icon=${IMAGEMAGICK_ICON}|" \
        "${IMAGEMAGICK_DESKTOP}"
    cp "${IMAGEMAGICK_DESKTOP}" \
        /usr/local/share/applications/display-im6.q16.desktop
fi

# Papirus is mostly SVG. With --no-install-recommends Ubuntu otherwise omits
# the GdkPixbuf SVG loader, leaving Rofi, Tint2 and tray applications with the
# same generic placeholder for almost every icon.
gdk-pixbuf-query-loaders --update-cache 2>/dev/null || true
for theme in Papirus Papirus-Dark Adwaita hicolor; do
    [ -f "/usr/share/icons/${theme}/index.theme" ] \
        && gtk-update-icon-cache -f -t "/usr/share/icons/${theme}" >/dev/null 2>&1 \
        || true
done
systemctl enable avahi-daemon.service >/dev/null 2>&1 || true
