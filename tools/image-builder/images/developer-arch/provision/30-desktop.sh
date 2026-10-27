#!/usr/bin/env bash
# Step 30 (Arch) — ArchLabs-inspired Openbox desktop.
# Pacman counterpart of the Ubuntu 30-desktop.sh: installs the Arch packages,
# then writes the SAME shared configuration (assets/desktop/desktop-config.sh).
set -euo pipefail

# Core desktop stack (Arch official repos). Names differ from Debian:
#   xorg-*            ← xorg / x11-xserver-utils / x11-utils
#   arc-gtk-theme     ← arc-theme   (+ gtk-engine-murrine to render it)
#   ttf-fira-code     ← fonts-firacode ; noto-fonts ← fonts-noto
#   ttf-dejavu        ← the wallpaper signature uses DejaVu-Sans (default on Ubuntu)
#   conky             ← conky-all   ; libnotify ← libnotify-bin ; mesa ← mesa GL
#   network-manager-applet ← network-manager-gnome
# Refresh the package databases first so every repo (incl. extra) is current —
# otherwise some targets resolve as "not found".
pac -Sy --noconfirm

# CRITICAL desktop stack — the session genuinely needs these, so a failure here
# must fail the build (it now surfaces correctly; the provision runner used to
# swallow it). Names differ from Debian; modesetting is built into xorg-server.
pac -S --noconfirm --needed \
    xorg-server xorg-xinit xorg-xrandr xorg-xsetroot xorg-xset xorg-xrdb \
    xorg-xprop xorg-xwininfo \
    openbox obconf-qt tint2 \
    lightdm lightdm-gtk-greeter \
    rofi pcmanfm gvfs xarchiver zip unzip conky alacritty feh picom lxappearance \
    network-manager-applet polkit avahi nss-mdns \
    pipewire pipewire-pulse wireplumber alsa-utils pavucontrol pasystray \
    gsimplecal \
    xdg-utils xdotool dunst libnotify scrot python-pyxdg spice-vdagent \
    xf86-input-libinput \
    mesa imagemagick python \
    gnome-themes-extra papirus-icon-theme

# OPTIONAL look-and-feel — themes, icons and fonts. Some of these aren't built
# for Arch Linux ARM (e.g. arc-gtk-theme / gtk-engine-murrine were "target not
# found"), and a missing theme must NOT block a working desktop. Install each
# best-effort; the session falls back to the stock Adwaita theme if absent.
for pkg in arc-gtk-theme gtk-engine-murrine polkit-gnome \
           adwaita-icon-theme ttf-fira-code noto-fonts ttf-dejavu; do
    pacman -S --noconfirm --needed "${pkg}" 2>/dev/null \
        || echo "[30-desktop] optional package unavailable, skipping: ${pkg}"
done

bash "${TOTALVM_ASSETS:-/mnt/assets}/desktop/desktop-config.sh"

# Alacritty is the only terminal in the Arch desktop. LibFM does not infer it
# from the installed packages, so PCManFM's "Open folder in terminal" action
# reports "terminal emulator not set" unless its preference is explicit.
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

# Some cross-distribution desktop utilities use Debian's generic executable
# name even on Arch. Keep that compatibility name without installing xterm.
ln -sfn /usr/bin/alacritty /usr/local/bin/x-terminal-emulator

# The build runner exposes the same VirtIO sound device as TotalVM. Refuse to
# publish an image whose kernel driver did not create a real ALSA card.
modprobe virtio_snd
aplay -l | grep -qi 'virtio' || {
    echo "[30-desktop] VirtIO sound device was not detected by ALSA" >&2
    aplay -l >&2 || true
    exit 1
}

# The visual configuration is shared verbatim; substitute only service names
# that differ on this base.
find /home/totaljs/.config/conky -type f -name '*.conf' -exec \
    sed -i -e 's/systemctl is-active ssh /systemctl is-active sshd /g' {} +
rm -rf /etc/skel/.config/conky
cp -a /home/totaljs/.config/conky /etc/skel/.config/

# --- Desktop reliability on Apple Virtualization ---------------------------
# The Apple Virtualization virtio-gpu exposes NO hardware GL. Xorg's modesetting
# driver defaults to glamor (GL) acceleration, which fails without it and makes
# Xorg exit with "no screens found" — so lightdm fails and the VM drops to a
# console login (the symptom on Arch). Disable accel so X starts on llvmpipe.
install -d /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/10-totalvm-modesetting.conf <<'EOF'
Section "Device"
    Identifier "virtio-gpu"
    Driver "modesetting"
    Option "AccelMethod" "none"
EndSection
EOF

# Make sure the virtio-gpu DRM node is present at boot so modesetting finds a
# screen even if udev is slow to autoload it.
echo virtio_gpu > /etc/modules-load.d/virtio-gpu.conf

# Belt and suspenders: guarantee the graphical login is the boot default on Arch
# (desktop-config.sh sets these too, but make the Arch path self-contained).
systemctl enable lightdm.service >/dev/null 2>&1 || true
systemctl set-default graphical.target >/dev/null 2>&1 || true
systemctl enable avahi-daemon.service >/dev/null 2>&1 || true
