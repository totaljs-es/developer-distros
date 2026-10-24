#!/usr/bin/env bash
# Total.js Developer — shared desktop configuration (Ubuntu + Arch images).
# Writes the ArchLabs-inspired Openbox/Tint2/LightDM/Rofi/PCManFM/Alacritty/Conky
# setup: theme, wallpapers, menus, autostart, greeter. DISTRO-SPECIFIC package
# installation lives in each image's 30-desktop.sh, which installs everything
# (including imagemagick for the wallpaper signature) and then runs this script.
set -euo pipefail
USER_HOME=/home/totaljs
# --- Software OpenGL --------------------------------------------------------
# The virtio-gpu in Apple Virtualization exposes NO hardware GL to the guest.
# Alacritty (and any other GL app) needs an OpenGL context to render — without
# one it opens a blank, unusable window. Force Mesa's llvmpipe software
# renderer for the whole session so GL apps draw correctly (a bit slower, but
# perfectly fine for a terminal).
cat >> /etc/environment <<'EOF'
LIBGL_ALWAYS_SOFTWARE=1
GALLIUM_DRIVER=llvmpipe
EOF

systemctl enable lightdm
systemctl set-default graphical.target
groupadd -f autologin
usermod -aG autologin totaljs
for media_group in audio video; do
    getent group "${media_group}" >/dev/null && usermod -aG "${media_group}" totaljs || true
done

# Apple Virtualization exposes a standard virtio-snd device. Load its kernel
# driver early when available; PipeWire/WirePlumber provide the desktop audio
# session and pasystray exposes volume controls in the top panel.
if modinfo virtio_snd >/dev/null 2>&1; then
    echo virtio_snd > /etc/modules-load.d/totaljs-audio.conf
    modprobe virtio_snd 2>/dev/null || true
fi
for audio_unit in pipewire.socket pipewire-pulse.socket wireplumber.service; do
    systemctl --global enable "$audio_unit" >/dev/null 2>&1 || true
done

install -d /usr/share/sounds/totaljs/events
install -m 0644 "${TOTALVM_ASSETS:-/mnt/assets}/audio/startup.wav" \
    /usr/share/sounds/totaljs/startup.wav
if [ -d "${TOTALVM_ASSETS:-/mnt/assets}/audio/events" ]; then
    find "${TOTALVM_ASSETS:-/mnt/assets}/audio/events" -maxdepth 1 -type f -name '*.wav' \
        -exec install -m 0644 {} /usr/share/sounds/totaljs/events/ \;
fi

cat > /usr/local/bin/totaljs-sound <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="$HOME/.config/totaljs"
MUTED="$STATE_DIR/sound-muted"
LOG_DIR="$HOME/.cache/totaljs"
LOG="$LOG_DIR/sound.log"
mkdir -p "$STATE_DIR" "$LOG_DIR"
printf '%s sound=%s\n' "$(date -Is)" "${1:-startup}" >> "$LOG"

case "${1:-startup}" in
    toggle)
        if [ -f "$MUTED" ]; then
            rm -f "$MUTED"
            notify-send "Total.js Developer" "System sounds enabled." 2>/dev/null || true
        else
            touch "$MUTED"
            notify-send "Total.js Developer" "System sounds muted." 2>/dev/null || true
        fi
        exit 0
        ;;
    preview)
        PREVIEW=1
        NAME="${2:-startup}"
        ;;
    *)
        NAME="${1:-startup}"
        ;;
esac

[ ! -f "$MUTED" ] || [ -n "${PREVIEW:-}" ] || exit 0
case "$NAME" in
    startup) SOUND=/usr/share/sounds/totaljs/startup.wav ;;
    alert|badges|beep|confirm|done|fail|message|notifications|success)
        SOUND="/usr/share/sounds/totaljs/events/${NAME}.wav"
        ;;
    *) echo "Unknown Total.js sound: $NAME" >&2; exit 2 ;;
esac

if [ "$NAME" = startup ] && [ -z "${PREVIEW:-}" ]; then
    MARKER="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/totaljs-startup-sound"
    [ ! -e "$MARKER" ] || exit 0
fi

# Start the user audio graph explicitly. Package presets normally do this, but
# minimal Openbox sessions don't always activate every socket on first login.
systemctl --user start pipewire.socket pipewire-pulse.socket wireplumber.service \
    >>"$LOG" 2>&1 || true

# PipeWire may need a moment after Openbox starts. Unmute the default sink,
# then play. ALSA is a final fallback if the user service is unavailable.
for _ in $(seq 1 30); do
    if command -v wpctl >/dev/null 2>&1 && wpctl status >>"$LOG" 2>&1; then
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 >>"$LOG" 2>&1 || true
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.75 >>"$LOG" 2>&1 || true
    fi
    if command -v pw-play >/dev/null 2>&1 && pw-play "$SOUND" >>"$LOG" 2>&1; then
        [ "$NAME" != startup ] || [ -n "${PREVIEW:-}" ] || touch "$MARKER"
        exit 0
    fi
    sleep 1
done

if command -v aplay >/dev/null 2>&1 && aplay -q "$SOUND" >>"$LOG" 2>&1; then
    [ "$NAME" != startup ] || [ -n "${PREVIEW:-}" ] || touch "$MARKER"
    exit 0
fi
{
    echo "No working audio sink found."
    modinfo virtio_snd 2>&1 | head -n 5
    aplay -l 2>&1
    wpctl status 2>&1
} >> "$LOG"
exit 1
EOF
chmod +x /usr/local/bin/totaljs-sound

# --- LightDM: auto-login the developer into Openbox ------------------------
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-totalvm.conf <<'EOF'
[Seat:*]
autologin-user=totaljs
autologin-user-timeout=0
autologin-session=openbox
user-session=openbox
greeter-session=lightdm-gtk-greeter
EOF

# Arc is available in Ubuntu but not currently packaged for Arch Linux ARM.
# Never request a missing theme: GTK silently falls back to light Adwaita while
# retaining dark symbolic icons, making active controls look disabled.
GTK_THEME_NAME=Adwaita-dark
if [ -f /usr/share/themes/Arc-Dark/gtk-3.0/gtk.css ]; then
    GTK_THEME_NAME=Arc-Dark
fi
GTK_ICON_THEME_NAME=Adwaita
if [ -d /usr/share/icons/Papirus-Dark ]; then
    GTK_ICON_THEME_NAME=Papirus-Dark
fi

# Branded greeter (shown when auto-login is disabled). Centred login box, soft
# antialiased text, a clock — and NO ~host indicator, so the machine name
# ("totalvm") never shows on the login screen.
cat > /etc/lightdm/lightdm-gtk-greeter.conf <<EOF
[greeter]
background = /usr/share/backgrounds/totaljs/login.jpg
user-background = false
theme-name = ${GTK_THEME_NAME}
icon-theme-name = ${GTK_ICON_THEME_NAME}
font-name = Noto Sans 11
hide-user-image = true
position = 50%,center 56%,center
clock-format = %H:%M  ·  %A %e %B
indicators = ~spacer;~clock;~spacer;~session;~power
xft-antialias = true
xft-hintstyle = hintslight
xft-rgba = rgb
EOF
install -d /etc/lightdm/lightdm-gtk-greeter.conf.d
cp /etc/lightdm/lightdm-gtk-greeter.conf \
    /etc/lightdm/lightdm-gtk-greeter.conf.d/50-totaljs.conf

# Hide the temporary "totaljs" bootstrap account from the login screen. It still
# auto-logs in on first boot to run the setup wizard (autologin ignores this),
# but once the wizard has created the real developer account, only that account
# should appear on the greeter — not the throwaway one.
install -d /var/lib/AccountsService/users
cat > /var/lib/AccountsService/users/totaljs <<'EOF'
[User]
SystemAccount=true
EOF

# --- Look & feel: GTK theme, icons, fonts (ArchLabs-style dark) -------------
# Set SYSTEM-WIDE so every GTK app (PCManFM, the setup wizard, lxappearance,
# nm-applet, Chromium chrome) and any account — including the one the wizard
# creates — gets the same dark GTK + icon + Noto Sans look with no per-user
# copies. Openbox runs no XSettings daemon, so GTK reads these files directly.
install -d /etc/gtk-4.0 /etc/gtk-3.0 /etc/gtk-2.0
cat > /etc/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-theme-name=${GTK_THEME_NAME}
gtk-icon-theme-name=${GTK_ICON_THEME_NAME}
gtk-font-name=Noto Sans 10
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=0
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
EOF
cat > /etc/gtk-4.0/settings.ini <<EOF
[Settings]
gtk-theme-name=Adwaita
gtk-icon-theme-name=${GTK_ICON_THEME_NAME}
gtk-font-name=Noto Sans 10
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
EOF
cat > /etc/gtk-2.0/gtkrc <<EOF
gtk-theme-name="${GTK_THEME_NAME}"
gtk-icon-theme-name="${GTK_ICON_THEME_NAME}"
gtk-font-name="Noto Sans 10"
gtk-cursor-theme-name="Adwaita"
EOF
# Default X cursor theme (used before any app sets its own).
install -d /usr/share/icons/default
cat > /usr/share/icons/default/index.theme <<'EOF'
[Icon Theme]
Inherits=Adwaita
EOF

# --- Wallpaper -------------------------------------------------------------
# Shipped by the builder via the "assets" virtiofs share when present;
# otherwise a solid Total.js-coloured fallback is generated.
install -d /usr/share/backgrounds/totaljs
if command -v magick >/dev/null 2>&1; then
    IMAGEMAGICK=(magick)
else
    IMAGEMAGICK=(convert)
fi
WALLPAPER_SOURCE=""
for candidate in \
    "${TOTALVM_ASSETS:-/mnt/assets}/wallpaper-totaljs.jpg" \
    "${TOTALVM_ASSETS:-/mnt/assets}/wallpaper-totaljs.jpeg" \
    "${TOTALVM_ASSETS:-/mnt/assets}/wallpaper-totaljs.png" \
    "${TOTALVM_ASSETS:-/mnt/assets}/wallpaper-dark.jpg" \
    "${TOTALVM_ASSETS:-/mnt/assets}/wallpaper-dark.jpeg" \
    "${TOTALVM_ASSETS:-/mnt/assets}/wallpaper-dark.png"; do
    if [ -f "${candidate}" ]; then
        WALLPAPER_SOURCE="${candidate}"
        break
    fi
done

if [ -n "${WALLPAPER_SOURCE}" ]; then
    cp "${WALLPAPER_SOURCE}" /usr/share/backgrounds/totaljs/wallpaper-source
    "${IMAGEMAGICK[@]}" /usr/share/backgrounds/totaljs/wallpaper-source \
        -resize 1920x1080 -background '#11161b' -gravity center -extent 1920x1080 \
        /usr/share/backgrounds/totaljs/wallpaper.jpg
    rm -f /usr/share/backgrounds/totaljs/wallpaper-source
else
    # Signature wallpaper: a subtle dark gradient with the Total.js wordmark in
    # the BOTTOM-RIGHT — deliberately away from conky (top-left) so the two never
    # overlap, unlike the old top-left text.
    "${IMAGEMAGICK[@]}" -size 1920x1080 gradient:'#0e1216'-'#161f1b' \
        -gravity SouthEast \
        -fill '#6ac043' -font DejaVu-Sans-Bold -pointsize 116 -annotate +130+150 'Total.js' \
        -fill '#9aa3ad' -font DejaVu-Sans -pointsize 38 -annotate +136+104 'Developer Distro' \
        /usr/share/backgrounds/totaljs/wallpaper.jpg
fi

# --- Wallpaper pack: a random one each login unless the user pins one ------
WALLPAPER_PACK_SRC="${TOTALVM_ASSETS:-/mnt/assets}/wallpapers"
install -d /usr/share/backgrounds/totaljs/pack
if [ -d "${WALLPAPER_PACK_SRC}" ]; then
    # The short alias survives ISO/Joliet filename limits. Keep the long-name
    # fallback for direct virtiofs builds and older asset trees.
    LOGIN_WALLPAPER="${TOTALVM_ASSETS:-/mnt/assets}/login.jpg"
    [ -f "${LOGIN_WALLPAPER}" ] || \
        LOGIN_WALLPAPER="${WALLPAPER_PACK_SRC}/77b1183f29d99b114cfb6047ee514f471da43e938e8dd65568c1ff2bb8229165.jpg"
    if [ -f "${LOGIN_WALLPAPER}" ]; then
        cp "${LOGIN_WALLPAPER}" /usr/share/backgrounds/totaljs/login.jpg
    fi
    find "${WALLPAPER_PACK_SRC}" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) \
        ! -name '77b1183f29d99b114cfb6047ee514f471da43e938e8dd65568c1ff2bb8229165.jpg' \
        -exec cp {} /usr/share/backgrounds/totaljs/pack/ \;
fi
[ -f /usr/share/backgrounds/totaljs/login.jpg ] || \
    cp /usr/share/backgrounds/totaljs/wallpaper.jpg /usr/share/backgrounds/totaljs/login.jpg

cat > /usr/local/bin/totaljs-wallpaper <<'EOF'
#!/usr/bin/env bash
# Picks the developer's pinned wallpaper, or a random one from the pack.
#   totaljs-wallpaper            apply pinned wallpaper, or a random one
#   totaljs-wallpaper next       show a different wallpaper
#   totaljs-wallpaper shuffle    force a new random pick (ignores the pin)
#   totaljs-wallpaper pin        pin whatever is currently showing
#   totaljs-wallpaper shuffle    go back to a random wallpaper each login
#   totaljs-wallpaper signature  use the Total.js signature background
set -euo pipefail
PACK_DIR=/usr/share/backgrounds/totaljs/pack
STATE_DIR="$HOME/.config/totaljs"
PINNED="${STATE_DIR}/wallpaper"
CURRENT="${STATE_DIR}/wallpaper.current"
mkdir -p "${STATE_DIR}"

case "${1:-show}" in
    pin)
        [ -f "${CURRENT}" ] && cp "${CURRENT}" "${PINNED}"
        notify-send "Total.js Developer" "Wallpaper pinned." 2>/dev/null || true
        exit 0
        ;;
    unpin)
        rm -f "${PINNED}"
        exec "$0" shuffle
        ;;
    next)
        OPTIONS=()
        while IFS= read -r candidate; do
            OPTIONS+=("${candidate}")
        done < <(find "${PACK_DIR}" -maxdepth 1 -type f | shuf)
        [ "${#OPTIONS[@]}" -gt 0 ] || exit 0
        CHOICE=""
        for candidate in "${OPTIONS[@]}"; do
            if [ ! -f "${CURRENT}" ] || ! cmp -s "${candidate}" "${CURRENT}"; then
                CHOICE="${candidate}"
                break
            fi
        done
        [ -n "${CHOICE}" ] || CHOICE="${OPTIONS[0]}"
        rm -f "${PINNED}"
        ;;
    shuffle)
        rm -f "${PINNED}"
        FORCE_RANDOM=1
        ;;
    signature)
        cp /usr/share/backgrounds/totaljs/wallpaper.jpg "${PINNED}"
        CHOICE="${PINNED}"
        ;;
esac

if [ -z "${FORCE_RANDOM:-}" ] && [ -f "${PINNED}" ]; then
    CHOICE="${PINNED}"
elif [ -d "${PACK_DIR}" ] && [ -n "$(ls -A "${PACK_DIR}" 2>/dev/null)" ]; then
    CHOICE="$(find "${PACK_DIR}" -maxdepth 1 -type f | shuf -n 1)"
else
    CHOICE=/usr/share/backgrounds/totaljs/wallpaper.jpg
fi

cp "${CHOICE}" "${CURRENT}"
feh --bg-fill "${CHOICE}"
EOF
chmod +x /usr/local/bin/totaljs-wallpaper

install -m 0755 "${TOTALVM_ASSETS:-/mnt/assets}/desktop/totaljs-region.py" \
    /usr/local/bin/totaljs-region
install -d -m 0755 /usr/local/share/totaljs-settings
install -d -m 0755 /usr/local/libexec
install -m 0755 "${TOTALVM_ASSETS:-/mnt/assets}/desktop/totaljs-settings.py" \
    /usr/local/share/totaljs-settings/settings.py
install -m 0755 -o root -g root \
    "${TOTALVM_ASSETS:-/mnt/assets}/desktop/totaljs-system-settings.py" \
    /usr/local/libexec/totaljs-system-settings
cat > /usr/local/bin/totaljs-settings <<'EOF'
#!/bin/sh
cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}"
log_file="${cache_dir}/totaljs-settings.log"
mkdir -p "${cache_dir}"
python3 /usr/local/share/totaljs-settings/settings.py 2>>"${log_file}"
status=$?
if [ "${status}" -ne 0 ] && command -v notify-send >/dev/null 2>&1; then
    notify-send -i dialog-error "Total Settings" \
        "Could not open the settings panel. Details: ${log_file}"
fi
exit "${status}"
EOF
chmod 0755 /usr/local/bin/totaljs-settings

cat > /usr/share/applications/totaljs-settings.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Total Settings
Comment=Configure the Total.js Developer desktop
Exec=/usr/local/bin/totaljs-settings
Icon=preferences-system
Terminal=false
Categories=Settings;System;
Keywords=network;sound;appearance;panel;region;keyboard;login;wallpaper;conky;
EOF

# The regional panel writes format preferences as the logged-in user. Only a
# time-zone change needs elevated privileges; authorize that narrow timedated
# action for an active local administrator instead of running the whole helper
# through pkexec (which fails when no textual controlling terminal exists).
install -d /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/49-totaljs-timezone.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.timedate1.set-timezone" &&
        subject.active && subject.local && subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
    if (action.id == "org.freedesktop.timedate1.set-timezone" &&
        subject.active && subject.local && subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
EOF

# Total Settings keeps running as the desktop user. PolicyKit grants only this
# fixed helper to the active local administrator; the helper itself accepts
# only the auto-login toggle and validated installed XKB layouts.
cat > /usr/share/polkit-1/actions/org.totaljs.settings.policy <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>Total.js</vendor>
  <vendor_url>https://www.totaljs.com/</vendor_url>
  <action id="org.totaljs.settings">
    <description>Change Total.js Developer system settings</description>
    <message>Authentication is required to change login or keyboard settings</message>
    <defaults>
      <allow_any>no</allow_any>
      <allow_inactive>no</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/local/libexec/totaljs-system-settings</annotate>
  </action>
</policyconfig>
EOF

cat > /etc/polkit-1/rules.d/49-totaljs-settings.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.totaljs.settings" && subject.active && subject.local &&
        (subject.isInGroup("wheel") || subject.isInGroup("sudo"))) {
        return polkit.Result.YES;
    }
});
EOF

# PCManFM's "Desktop Preferences" tool only works when PCManFM owns the root
# window. Openbox owns it here (for its right-click menu), so hide that dead
# launcher instead of showing a misleading "desktop manager is not active".
for desktop_pref in /usr/share/applications/pcmanfm-desktop-pref.desktop; do
    [ -f "${desktop_pref}" ] && printf '\nNoDisplay=true\n' >> "${desktop_pref}"
done

# Common locales used by the format-only regional panel. The desktop language
# remains English; only LC_TIME/NUMERIC/MONETARY/MEASUREMENT/PAPER are changed.
for locale in en_US en_GB es_ES de_DE fr_FR it_IT pt_PT nl_NL; do
    sed -Ei "s/^#[[:space:]]*(${locale}\.UTF-8[[:space:]]+UTF-8)/\1/" /etc/locale.gen 2>/dev/null || true
done
locale-gen >/dev/null 2>&1 || true

# Give small Openbox utilities stable freedesktop icons in Rofi.
set_desktop_icon() {
    local file="$1" icon="$2"
    [ -f "$file" ] || return 0
    if grep -q '^Icon=' "$file"; then
        sed -i "s|^Icon=.*|Icon=${icon}|" "$file"
    else
        printf '\nIcon=%s\n' "$icon" >> "$file"
    fi
}
set_desktop_icon /usr/share/applications/obconf.desktop preferences-system-windows
set_desktop_icon /usr/share/applications/pasystray.desktop audio-volume-high
set_desktop_icon /usr/share/applications/pavucontrol.desktop multimedia-volume-control
set_desktop_icon /usr/share/applications/org.pulseaudio.pavucontrol.desktop multimedia-volume-control
set_desktop_icon /usr/share/applications/rofi.desktop system-search
set_desktop_icon /usr/share/applications/rofi-theme-selector.desktop preferences-desktop-theme
set_desktop_icon /usr/share/applications/texinfo.desktop help-about
set_desktop_icon /usr/share/applications/tint2.desktop preferences-desktop-panel
set_desktop_icon /usr/share/applications/tint2conf.desktop preferences-desktop-panel

# These launchers are implementation details of the Openbox session. Starting
# them manually duplicates Conky/the tray, while Tint2 and Picom either do
# nothing visible or replace the managed session process. Keep the useful
# Pavucontrol entry and hide the plumbing from both Rofi and Applications.
for internal_launcher in \
    /usr/share/applications/conky.desktop \
    /usr/share/applications/avahi-discover.desktop \
    /usr/share/applications/bssh.desktop \
    /usr/share/applications/bvnc.desktop \
    /usr/share/applications/pasystray.desktop \
    /usr/share/applications/picom.desktop \
    /usr/share/applications/rofi.desktop \
    /usr/share/applications/rofi-theme-selector.desktop \
    /usr/share/applications/texinfo.desktop \
    /usr/share/applications/tint2.desktop \
    /usr/share/applications/tint2conf.desktop \
    /usr/share/applications/qv4l2.desktop \
    /usr/share/applications/qvidcap.desktop \
    /usr/share/applications/info.desktop \
    /usr/share/applications/debian-uxterm.desktop \
    /usr/share/applications/debian-xterm.desktop \
    /usr/share/applications/uxterm.desktop \
    /usr/share/applications/xterm.desktop; do
    [ -f "${internal_launcher}" ] || continue
    if grep -q '^NoDisplay=' "${internal_launcher}"; then
        sed -i 's/^NoDisplay=.*/NoDisplay=true/' "${internal_launcher}"
    else
        sed -i '/^\[Desktop Entry\]/a NoDisplay=true' "${internal_launcher}"
    fi
done

# --- Dynamic Applications submenu ------------------------------------------
# Openbox pipe menu: auto-lists every installed .desktop app, grouped by
# category, so anything the user installs later (VS Code, LibreOffice, another
# browser...) appears in the menu without editing anything.
if [ -f "${TOTALVM_ASSETS:-/mnt/assets}/desktop/totaljs-appmenu" ]; then
    install -m 0755 "${TOTALVM_ASSETS:-/mnt/assets}/desktop/totaljs-appmenu" \
        /usr/local/bin/totaljs-appmenu
fi

# --- Openbox config for the developer user ---------------------------------
USER_HOME=/home/totaljs
install -d -o totaljs -g totaljs "${USER_HOME}/.config/openbox" "${USER_HOME}/.config/tint2" "${USER_HOME}/.config/conky" "${USER_HOME}/.config/picom" "${USER_HOME}/.config/rofi" "${USER_HOME}/.config/dunst" "${USER_HOME}/.config/gsimplecal"

# User-level tombstones take precedence over system launchers in Rofi. This is
# more durable than editing package-owned .desktop files alone: qv4l2 and the
# other session internals stay hidden even after their packages are upgraded.
install -d -o totaljs -g totaljs "${USER_HOME}/.local/share/applications"
install -d /etc/skel/.local/share/applications
for desktop_id in \
    avahi-discover.desktop bssh.desktop bvnc.desktop conky.desktop \
    debian-uxterm.desktop debian-xterm.desktop info.desktop \
    pasystray.desktop picom.desktop qv4l2.desktop qvidcap.desktop \
    rofi.desktop rofi-theme-selector.desktop texinfo.desktop \
    tint2.desktop tint2conf.desktop uxterm.desktop xterm.desktop; do
    cat > "${USER_HOME}/.local/share/applications/${desktop_id}" <<EOF
[Desktop Entry]
Type=Application
Name=Hidden system component
Exec=false
Hidden=true
NoDisplay=true
EOF
    cp "${USER_HOME}/.local/share/applications/${desktop_id}" \
        "/etc/skel/.local/share/applications/${desktop_id}"
done
chown -R totaljs:totaljs "${USER_HOME}/.local"

# Gsimplecal was designed as a toggleable Tint2/Openbox clock popup. Keep it
# undecorated and out of the task list so it feels like part of the panel.
cat > "${USER_HOME}/.config/gsimplecal/config" <<'EOF'
show_calendar = 1
show_timezones = 0
mark_today = 1
show_week_numbers = 1
close_on_unfocus = 0
close_on_mouseleave = 0
mainwindow_decorated = 0
mainwindow_keep_above = 1
mainwindow_sticky = 1
mainwindow_skip_taskbar = 1
mainwindow_resizable = 0
mainwindow_position = mouse
EOF

# --- TotalJS Openbox theme: flat, ArchLabs-inspired, Total.js green accent --
install -d /usr/share/themes/TotalJS/openbox-3
cat > /usr/share/themes/TotalJS/openbox-3/themerc <<'EOF'
window.active.border.color: #6ac043
window.inactive.border.color: #2a3036
window.active.title.bg: flat solid
window.active.title.bg.color: #20262c
window.inactive.title.bg: flat solid
window.inactive.title.bg.color: #181b1f
window.active.label.text.color: #d7d9dc
window.inactive.label.text.color: #6b7178
window.active.button.unpressed.image.color: #d7d9dc
window.inactive.button.unpressed.image.color: #6b7178
window.active.button.hover.image.color: #6ac043
window.active.button.pressed.image.color: #4a8a2c
window.active.button.disabled.image.color: #4a4f55
window.label.text.justify: left
# A 2px green frame reads clearly all the way around (corners included) now that
# picom no longer rounds — and the handle/grips share the title background so the
# bottom edge sits inside the same frame instead of showing a default-coloured block.
border.width: 2
window.handle.width: 4
window.active.handle.bg: flat solid
window.active.handle.bg.color: #20262c
window.inactive.handle.bg: flat solid
window.inactive.handle.bg.color: #181b1f
window.active.grip.bg: flat solid
window.active.grip.bg.color: #20262c
window.inactive.grip.bg: flat solid
window.inactive.grip.bg.color: #181b1f
window.client.padding.width: 0
padding.width: 5
padding.height: 4
menu.title.bg: flat solid
menu.title.bg.color: #20262c
menu.title.text.color: #d7d9dc
menu.items.bg: flat solid
menu.items.bg.color: #181b1f
menu.items.text.color: #d7d9dc
menu.items.disabled.text.color: #6b7178
menu.items.active.bg: flat solid
menu.items.active.bg.color: #2c3a22
menu.items.active.text.color: #ffffff
menu.separator.color: #4a565f
menu.separator.width: 1
menu.separator.padding.width: 4
menu.separator.padding.height: 4
osd.bg: flat solid
osd.bg.color: #20262c
osd.label.bg: flat solid
osd.label.bg.color: #20262c
osd.label.text.color: #d7d9dc
osd.hilight.bg: flat solid
osd.hilight.bg.color: #6ac043
osd.unhilight.bg: flat solid
osd.unhilight.bg.color: #2a3036
osd.border.color: #6ac043
osd.border.width: 1
window.active.shadow: true
window.inactive.shadow: true
font: shadow=n place=ActiveWindowTitle font="Noto Sans" size=11 weight=bold slant=normal
font: shadow=n place=InactiveWindowTitle font="Noto Sans" size=11 weight=bold slant=normal
font: shadow=n place=MenuHeader font="Noto Sans" size=10 weight=bold slant=normal
font: shadow=n place=MenuItem font="Noto Sans" size=11 weight=normal slant=normal
font: shadow=n place=OnScreenDisplay font="Noto Sans" size=10 weight=bold slant=normal
EOF

# --- picom: subtle shadows + fade to match the rest of the desktop ---------
cat > "${USER_HOME}/.config/picom/picom.conf" <<'EOF'
# xrender, not glx: the virtio-gpu in Apple Virtualization has no hardware GL
# in the guest, so the glx backend would fail to start (no compositing at all).
backend = "xrender";
# vsync OFF: the xrender backend can't truly sync to the virtio-gpu, and leaving
# it on caused stalls/artifacts in the guest.
vsync = false;

shadow = true;
shadow-radius = 14;
shadow-offset-x = -10;
shadow-offset-y = -10;
shadow-opacity = 0.45;
shadow-color = "#000000";
shadow-exclude = [
  "class_g = 'Conky'",
  "_NET_WM_STATE@:32a *= '_NET_WM_STATE_SKIP_TASKBAR'"
];

fading = true;
fade-in-step = 0.06;
fade-out-step = 0.06;
fade-delta = 6;

inactive-opacity = 0.96;
active-opacity = 1.0;
frame-opacity = 1.0;
inactive-opacity-override = false;

# No rounded corners: with the xrender backend (no hardware GL in the guest)
# picom rounds the window but clips Openbox's square border at the corners, so
# the green frame looks broken/un-cornered. Square corners keep the green border
# crisp all the way around — and it's a sharper ArchLabs look anyway.
corner-radius = 0;

blur-background = false;
mark-wmwin-focused = true;
mark-ovredir-focused = true;
detect-rounded-corners = true;
detect-client-opacity = true;
# use-damage OFF: with the xrender backend on the virtio-gpu, partial-damage
# repaint left stale regions — parts of conky and windows vanished or windows
# stayed see-through because their content was never redrawn. Repainting the
# whole frame each time (a bit more CPU) keeps the desktop coherent.
use-damage = false;
EOF

# --- Rofi launcher: centred, dark, Total.js-green accent (ArchLabs feel) ----
cat > "${USER_HOME}/.config/rofi/config.rasi" <<'EOF'
configuration {
    modi: "drun,run,window";
    show-icons: true;
    icon-theme: "Papirus-Dark";
    drun-display-format: "{name}";
    font: "Noto Sans 11";
    display-drun: "Apps";
    display-run: "Run";
    display-window: "Windows";
}

* {
    bg:      #1c2024;
    bg-alt:  #24282e;
    fg:      #d7d9dc;
    fg-alt:  #8b949e;
    accent:  #6ac043;
    on-accent: #11161a;
    background-color: transparent;
    text-color: @fg;
}

window {
    background-color: @bg;
    border: 2px;
    border-color: @accent;
    border-radius: 12px;
    width: 600px;
    padding: 0;
}
mainbox { padding: 14px; spacing: 12px; }
inputbar {
    background-color: @bg-alt;
    border-radius: 8px;
    padding: 11px 14px;
    spacing: 10px;
    children: [ prompt, entry ];
}
prompt { text-color: @accent; }
entry  { placeholder: "Search…"; placeholder-color: @fg-alt; }
listview { lines: 8; spacing: 4px; scrollbar: false; }
element { padding: 9px 12px; border-radius: 8px; spacing: 11px; }
element normal active   { text-color: @accent; }
element selected normal { background-color: @accent; text-color: @on-accent; }
element selected active  { background-color: @accent; text-color: @on-accent; }
element-icon { size: 22px; vertical-align: 0.5; }
element-text { vertical-align: 0.5; }
EOF

# --- Dunst notifications: dark card, green accent frame ---------------------
cat > "${USER_HOME}/.config/dunst/dunstrc" <<'EOF'
[global]
    follow = mouse
    width = 330
    height = 120
    origin = top-right
    offset = 18x52
    notification_limit = 4
    progress_bar = true
    progress_bar_height = 8
    progress_bar_frame_width = 0
    indicate_hidden = yes
    transparency = 5
    padding = 12
    horizontal_padding = 14
    frame_width = 2
    frame_color = "#6ac043"
    corner_radius = 10
    separator_color = frame
    sort = yes
    font = Noto Sans 10
    markup = full
    format = "<b>%s</b>\n%b"
    alignment = left
    vertical_alignment = center
    word_wrap = yes
    icon_position = left
    min_icon_size = 24
    max_icon_size = 48
    mouse_left_click = do_action, close_current
    mouse_right_click = close_all

[urgency_low]
    background = "#1c2024"
    foreground = "#8b949e"
    frame_color = "#2e353c"
    timeout = 5

[urgency_normal]
    background = "#1c2024"
    foreground = "#d7d9dc"
    frame_color = "#6ac043"
    timeout = 8

[urgency_critical]
    background = "#2a1416"
    foreground = "#ffffff"
    frame_color = "#e75a5a"
    timeout = 0
EOF

# Browser launcher shared by every menu entry. `gio open` follows the desktop's
# configured default browser, so changing it later works everywhere.
cat > /usr/local/bin/totaljs-open <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${1:?Usage: totaljs-open URL}"
mkdir -p "${HOME}/.cache"
nohup gio open "${url}" >"${HOME}/.cache/totaljs-browser.log" 2>&1 &
EOF
chmod +x /usr/local/bin/totaljs-open

cat > /usr/local/bin/totaljs-launch-once <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
process="${1:?process name required}"
shift
while IFS= read -r pid; do
    # pgrep sees this helper too because the target command is one of its own
    # arguments. Ignore this shell and its parent; only a real existing target
    # should suppress a second launch.
    [ "${pid}" = "$$" ] || [ "${pid}" = "${PPID}" ] || exit 0
done < <(pgrep -u "$(id -u)" -f "${process}" 2>/dev/null || true)
mkdir -p "${HOME}/.cache"
nohup "$@" >"${HOME}/.cache/${process}.log" 2>&1 &
EOF
chmod +x /usr/local/bin/totaljs-launch-once

cat > /usr/local/bin/totaljs-panel-settings <<'EOF'
#!/usr/bin/env bash
exec tint2conf "${HOME}/.config/tint2/top.tint2rc"
EOF
chmod +x /usr/local/bin/totaljs-panel-settings

# Ubuntu provides the original GTK ObConf application, while Arch ARM ships
# its maintained Qt port. Keep LXAppearance only as a last-resort fallback so
# Appearance and Window Borders normally remain two distinct destinations.
cat > /usr/local/bin/totaljs-window-borders <<'EOF'
#!/bin/sh
if command -v obconf >/dev/null 2>&1; then
    exec obconf
fi
if command -v obconf-qt >/dev/null 2>&1; then
    exec obconf-qt
fi
exec lxappearance
EOF
chmod 0755 /usr/local/bin/totaljs-window-borders

# Branded session confirmation. Openbox's built-in Exit action hard-codes both
# "Exit Openbox" and its confirmation copy, which exposes the implementation
# instead of the desktop the user is actually leaving.
cat > /usr/local/bin/totaljs-logout <<'EOF'
#!/usr/bin/env python3
import subprocess

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk


dialog = Gtk.MessageDialog(
    transient_for=None,
    flags=Gtk.DialogFlags.MODAL,
    message_type=Gtk.MessageType.QUESTION,
    buttons=Gtk.ButtonsType.NONE,
    text="Are you sure you want to log out of Total.js Developer?",
)
dialog.set_title("Total.js Developer")
dialog.set_position(Gtk.WindowPosition.CENTER)
dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
dialog.add_button("Log out", Gtk.ResponseType.OK)
dialog.set_default_response(Gtk.ResponseType.CANCEL)
response = dialog.run()
dialog.destroy()

if response == Gtk.ResponseType.OK:
    subprocess.Popen(["openbox", "--exit"], start_new_session=True)
EOF
chmod 0755 /usr/local/bin/totaljs-logout

# Dynamic Trash indicator for the dock. GIO reports the real aggregated trash
# contents, including any locations supported by GVFS.
install -d /usr/local/share/icons
install -m 0644 "${TOTALVM_ASSETS:-/mnt/assets}/desktop/trash-empty.svg" \
    /usr/local/share/icons/totaljs-trash-empty.svg
install -m 0644 "${TOTALVM_ASSETS:-/mnt/assets}/desktop/trash-full.svg" \
    /usr/local/share/icons/totaljs-trash-full.svg

cat > /usr/local/bin/totaljs-trash-status <<'EOF'
#!/usr/bin/env bash
if gio list trash:/// 2>/dev/null | head -n 1 | grep -q .; then
    printf '%s\n' /usr/local/share/icons/totaljs-trash-full.svg
else
    printf '%s\n' /usr/local/share/icons/totaljs-trash-empty.svg
fi
EOF
chmod 0755 /usr/local/bin/totaljs-trash-status

cat > /usr/local/bin/totaljs-trash-menu <<'EOF'
#!/usr/bin/env python3
import subprocess

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, Gtk


def trash_has_items():
    result = subprocess.run(
        ["gio", "list", "trash:///"], text=True, capture_output=True, check=False,
    )
    return bool(result.stdout.strip())


def finish():
    try:
        Gdk.Display.get_default().get_default_seat().ungrab()
    except (AttributeError, TypeError):
        pass
    if Gtk.main_level():
        Gtk.main_quit()


def open_trash(*_):
    subprocess.Popen(["pcmanfm", "trash:///"])
    finish()


def empty_trash(*_):
    dialog = Gtk.MessageDialog(
        message_type=Gtk.MessageType.WARNING,
        buttons=Gtk.ButtonsType.CANCEL,
        text="Empty Trash?",
    )
    dialog.set_title("Trash")
    dialog.format_secondary_text("These files will be permanently removed.")
    dialog.add_button("Empty Trash", Gtk.ResponseType.OK)
    response = dialog.run()
    dialog.destroy()
    if response == Gtk.ResponseType.OK:
        subprocess.run(["gio", "trash", "--empty"], check=False)
    finish()


# Tint2 starts this as a separate process, so there is no GTK mouse event to
# anchor a Gtk.Menu to. A tiny popup window positioned at the live pointer is
# reliable on both distro versions and behaves like the expected context menu.
popup = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
popup.set_name("trash-menu")
popup.set_position(Gtk.WindowPosition.NONE)
popup.set_keep_above(True)
popup.set_resizable(False)
popup.set_decorated(False)
popup.set_skip_taskbar_hint(True)
popup.set_skip_pager_hint(True)
popup.set_type_hint(Gdk.WindowTypeHint.POPUP_MENU)
popup.set_accept_focus(True)
popup.set_focus_on_map(True)
popup.set_border_width(1)
popup.connect("focus-out-event", lambda *_: finish())
popup.connect(
    "key-press-event",
    lambda _window, event: finish() if event.keyval == Gdk.KEY_Escape else False,
)

provider = Gtk.CssProvider()
provider.load_from_data(b"""
#trash-menu { background-color: #1c2126; border: 1px solid #45515b; }
#trash-menu button { min-width: 0; min-height: 0; color: #e4e8eb; background-image: none; background-color: transparent; border: 0; box-shadow: none; font-size: 10px; padding: 4px 10px; }
#trash-menu button:hover { color: #ffffff; background-color: #2c3a22; }
""")
Gtk.StyleContext.add_provider_for_screen(
    Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
)

box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
popup.add(box)
open_button = Gtk.Button(label="Open Trash")
open_button.set_relief(Gtk.ReliefStyle.NONE)
open_button.connect("clicked", open_trash)
box.pack_start(open_button, False, False, 0)
empty_button = Gtk.Button(label="Empty Trash")
empty_button.set_relief(Gtk.ReliefStyle.NONE)
empty_button.set_sensitive(trash_has_items())
empty_button.connect("clicked", empty_trash)
box.pack_start(empty_button, False, False, 0)


def dismiss_if_outside(window, event):
    window_x, window_y = window.get_position()
    width, height = window.get_size()
    if not (
        window_x <= event.x_root < window_x + width
        and window_y <= event.y_root < window_y + height
    ):
        finish()
        return True
    return False


popup.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.BUTTON_RELEASE_MASK)
popup.connect("button-press-event", dismiss_if_outside)
popup.show_all()
popup.realize()

# Place the menu above the bottom-dock icon, leaving enough space that neither
# the icon nor its hover area is covered by the popup.
display = Gdk.Display.get_default()
seat = display.get_default_seat()
_screen, pointer_x, pointer_y = seat.get_pointer().get_position()
preferred = popup.get_preferred_size()[1]
monitor = display.get_monitor_at_point(pointer_x, pointer_y)
workarea = monitor.get_workarea()
popup_x = min(
    max(workarea.x, pointer_x - preferred.width + 18),
    workarea.x + workarea.width - preferred.width,
)
popup_y = max(workarea.y, pointer_y - preferred.height - 18)
popup.move(popup_x, popup_y)
popup.present()
popup.grab_focus()
seat.grab(
    popup.get_window(), Gdk.SeatCapabilities.ALL_POINTING,
    True, None, None, None,
)
Gtk.main()
EOF
chmod 0755 /usr/local/bin/totaljs-trash-menu

install -m 0755 "${TOTALVM_ASSETS:-/mnt/assets}/desktop/totaljs-pasystray" \
    /usr/local/bin/totaljs-pasystray

# Keep NetworkManager's real status applet attached to Tint2. Starting it
# directly races the two Tint2 instances during login and can leave the top
# panel without a network icon for the whole session.
cat > /usr/local/bin/totaljs-nm-applet <<'EOF'
#!/usr/bin/env bash
set -u

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "${RUNTIME_DIR}"
LOCK_FILE="${RUNTIME_DIR}/totaljs-nm-applet.lock"
PID_FILE="${RUNTIME_DIR}/totaljs-nm-applet.pid"
exec 9>"${LOCK_FILE}"

if ! flock -n 9; then
    old_pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
    case "${old_pid}" in
        ''|*[!0-9]*) ;;
        *) kill -TERM "${old_pid}" 2>/dev/null || true ;;
    esac
    for _ in $(seq 1 30); do
        flock -n 9 && break
        sleep 0.1
    done
fi
flock -n 9 || exit 0
printf '%s\n' "$$" > "${PID_FILE}"

child=
cleanup() {
    trap - EXIT
    [ -z "${child}" ] || kill -TERM "${child}" 2>/dev/null || true
    if [ "$(cat "${PID_FILE}" 2>/dev/null || true)" = "$$" ]; then
        rm -f "${PID_FILE}"
    fi
}
trap cleanup EXIT
trap 'exit 0' HUP INT TERM

while ! pgrep -u "$(id -u)" -x tint2 >/dev/null 2>&1; do
    sleep 1
done
sleep 3

while true; do
    nm-applet &
    child=$!
    wait "${child}" || true
    child=
    sleep 2
done
EOF
chmod 0755 /usr/local/bin/totaljs-nm-applet

# Autostart: compositor, panel, wallpaper and first-run setup.
cat > "${USER_HOME}/.config/openbox/autostart" <<'EOF'
# A normal arrow cursor on the root window (otherwise it's the default X "X").
xsetroot -cursor_name left_ptr &
# A developer VM must stay available while its Mac window is in the background.
# Disable X screen blanking and DPMS; the host owns display power management.
xset s off -dpms
# Openbox started by LightDM on first boot sometimes loads the config "cold"
# (menus/titlebar-button actions inert until a reconfigure). Re-apply it once
# the session has settled so everything works on the very first login.
( sleep 3; openbox --reconfigure ) &
pgrep -u "$(id -u)" -x picom >/dev/null || picom --config "$HOME/.config/picom/picom.conf" --daemon &
totaljs-wallpaper &
pgrep -u "$(id -u)" -x tint2 >/dev/null || {
  tint2 -c "$HOME/.config/tint2/top.tint2rc" &
  tint2 -c "$HOME/.config/tint2/dock.tint2rc" &
}
totaljs-conky restore &
/usr/local/bin/totaljs-nm-applet &
/usr/local/bin/totaljs-pasystray &
# Openbox does not provide its own Polkit agent. Start whichever distro path
# exists so Regional Settings and graphical updates can authenticate.
for agent in \
  /usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 \
  /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1; do
  if [ -x "$agent" ]; then
    totaljs-launch-once '[p]olkit-gnome-authentication-agent-1' "$agent"
    break
  fi
done
( sleep 2; totaljs-sound startup ) &
totaljs-launch-once '[d]unst' dunst
if [ ! -f "$HOME/.config/totaljs/first-run.done" ]; then
  mkdir -p "$HOME/.config/totaljs"
  /usr/local/bin/totaljs-first-run &
fi
EOF

# Install the canonical Total.js artwork used by the Openbox menu. Both Ubuntu
# and Arch builds receive this directory from tools/package-repo/icons.
MENU_ICON_SOURCE="${TOTALVM_ASSETS:-/mnt/assets}/menu-icons"
MENU_ICON_DEST=/usr/share/totaljs-developer/icons
MENU_ICONS="applications browser developer launcher logout preferences projects restart services shutdown terminal total-center totaljs"
install -d "${MENU_ICON_DEST}"
for icon in ${MENU_ICONS}; do
    [ -f "${MENU_ICON_SOURCE}/${icon}.svg" ] || {
        echo "Missing Openbox menu icon: ${MENU_ICON_SOURCE}/${icon}.svg" >&2
        exit 1
    }
    install -m 0644 "${MENU_ICON_SOURCE}/${icon}.svg" \
        "${MENU_ICON_DEST}/${icon}.svg"
done

# Right-click menu for the Total.js Developer desktop.
cat > "${USER_HOME}/.config/openbox/menu.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_menu xmlns="http://openbox.org/3.4/menu">
  <menu id="root-menu" label="Total.js Developer">
    <menu id="developer-menu" label="Developer" icon="/usr/share/totaljs-developer/icons/developer.svg">
      <item label="Code"><action name="Execute"><command>totaljs-code-open</command></action></item>
      <item label="Flow"><action name="Execute"><command>totaljs-flow-open</command></action></item>
    </menu>
    <item label="Projects" icon="/usr/share/totaljs-developer/icons/projects.svg"><action name="Execute"><command>pcmanfm /www/www</command></action></item>
    <item label="Terminal" icon="/usr/share/totaljs-developer/icons/terminal.svg"><action name="Execute"><command>alacritty</command></action></item>
    <item label="Total.js Center" icon="/usr/share/totaljs-developer/icons/total-center.svg"><action name="Execute"><command>totaljs-open http://totaljs.developer</command></action></item>
    <item label="Web Browser" icon="/usr/share/totaljs-developer/icons/browser.svg"><action name="Execute"><command>totaljs-open http://totaljs.developer</command></action></item>
    <separator />
    <menu id="apps-menu" label="Applications" execute="python3 /usr/local/bin/totaljs-appmenu" icon="/usr/share/totaljs-developer/icons/applications.svg" />
    <menu id="preferences-menu" label="Preferences" icon="/usr/share/totaljs-developer/icons/preferences.svg">
      <item label="All Settings"><action name="Execute"><command>/usr/local/bin/totaljs-settings</command></action></item>
      <separator />
      <item label="Appearance"><action name="Execute"><command>lxappearance</command></action></item>
      <item label="Panel settings"><action name="Execute"><command>totaljs-panel-settings</command></action></item>
      <item label="Regional settings"><action name="Execute"><command>/usr/local/bin/totaljs-region</command></action></item>
      <menu id="conky-menu" label="Desktop Stats">
        <item label="Compact"><action name="Execute"><command>totaljs-conky compact</command></action></item>
        <item label="Services"><action name="Execute"><command>totaljs-conky services</command></action></item>
        <item label="System"><action name="Execute"><command>totaljs-conky system</command></action></item>
        <separator />
        <item label="Hide"><action name="Execute"><command>totaljs-conky hidden</command></action></item>
      </menu>
      <menu id="sound-menu" label="Sound">
        <item label="Play startup sound"><action name="Execute"><command>totaljs-sound preview startup</command></action></item>
        <item label="Toggle system sounds"><action name="Execute"><command>totaljs-sound toggle</command></action></item>
        <item label="Volume control"><action name="Execute"><command>pavucontrol</command></action></item>
      </menu>
      <menu id="wallpaper-menu" label="Wallpaper">
        <item label="Change wallpaper (Super+W)"><action name="Execute"><command>totaljs-wallpaper next</command></action></item>
        <item label="Pin current wallpaper"><action name="Execute"><command>totaljs-wallpaper pin</command></action></item>
        <item label="Shuffle on login"><action name="Execute"><command>totaljs-wallpaper shuffle</command></action></item>
        <item label="Total.js signature"><action name="Execute"><command>totaljs-wallpaper signature</command></action></item>
      </menu>
    </menu>
    <menu id="services-menu" label="Services" icon="/usr/share/totaljs-developer/icons/services.svg">
      <item label="Code status"><action name="Execute"><command>alacritty -e bash -lc 'docker compose -f /www/code/docker-compose.yml ps; read -rp "Press Enter..."'</command></action></item>
      <item label="Docker status"><action name="Execute"><command>alacritty -e bash -lc 'docker ps; read -rp "Press Enter..."'</command></action></item>
      <item label="pgAdmin (database client)"><action name="Execute"><command>totaljs-pgadmin-open</command></action></item>
      <item label="PostgreSQL files"><action name="Execute"><command>pcmanfm /www/services/postgres</command></action></item>
    </menu>
    <menu id="totaljs-menu" label="Total.js" icon="/usr/share/totaljs-developer/icons/totaljs.svg">
      <item label="Blog"><action name="Execute"><command>totaljs-open https://blog.totaljs.com</command></action></item>
      <item label="Documentation"><action name="Execute"><command>totaljs-open https://docs.totaljs.com</command></action></item>
      <item label="Website"><action name="Execute"><command>totaljs-open https://www.totaljs.com</command></action></item>
      <separator label="Online services" />
      <item label="API services"><action name="Execute"><command>totaljs-open https://docs.totaljs.com/totalapi/</command></action></item>
      <item label="Componentator"><action name="Execute"><command>totaljs-open https://componentator.com</command></action></item>
      <item label="Flow reader"><action name="Execute"><command>totaljs-open https://floweditor.totaljs.com</command></action></item>
      <item label="NoSQL reader"><action name="Execute"><command>totaljs-open https://nosql.totaljs.com</command></action></item>
      <item label="Read me"><action name="Execute"><command>totaljs-open https://readme.totaljs.com</command></action></item>
      <item label="Templates"><action name="Execute"><command>totaljs-open https://templates.totaljs.com</command></action></item>
      <item label="Text Utilities"><action name="Execute"><command>totaljs-open https://utils.totaljs.com</command></action></item>
      <item label="Translator"><action name="Execute"><command>totaljs-open https://translate.totaljs.com</command></action></item>
      <item label="UI Builder"><action name="Execute"><command>totaljs-open https://uibuilder.totaljs.com</command></action></item>
      <separator label="Account" />
      <item label="App Monitoring"><action name="Execute"><command>totaljs-open https://account.totaljs.com/monitor/</command></action></item>
      <item label="Total.js Account"><action name="Execute"><command>totaljs-open https://account.totaljs.com</command></action></item>
    </menu>
    <separator />
    <item label="Open launcher" icon="/usr/share/totaljs-developer/icons/launcher.svg"><action name="Execute"><command>rofi -show drun</command></action></item>
    <separator />
    <item label="Log out" icon="/usr/share/totaljs-developer/icons/logout.svg"><action name="Execute"><command>totaljs-logout</command></action></item>
    <item label="Restart" icon="/usr/share/totaljs-developer/icons/restart.svg"><action name="Execute"><command>systemctl reboot</command></action></item>
    <item label="Shutdown" icon="/usr/share/totaljs-developer/icons/shutdown.svg"><action name="Execute"><command>systemctl poweroff</command></action></item>
  </menu>
  <menu id="client-menu">
    <item label="Always on all desktops"><action name="ToggleOmnipresent"/></item>
    <item label="Always on top"><action name="ToggleAlwaysOnTop"/></item>
    <item label="Maximize"><action name="ToggleMaximizeFull"/></item>
    <item label="Minimize"><action name="Iconify"/></item>
    <separator />
    <item label="Move"><action name="Move"/></item>
    <item label="Resize"><action name="Resize"/></item>
    <separator />
    <item label="Close"><action name="Close"/></item>
  </menu>
</openbox_menu>
EOF

# Keybindings: Super+Return → terminal, Super+D → Rofi, Super+W → wallpaper.
cat > "${USER_HOME}/.config/openbox/rc.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme>
    <name>TotalJS</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>yes</keepBorder>
    <animateIconify>yes</animateIconify>
  </theme>
  <desktops>
    <number>4</number>
    <firstdesk>1</firstdesk>
    <names>
      <name>1</name>
      <name>2</name>
      <name>3</name>
      <name>4</name>
    </names>
  </desktops>
  <!-- Reserve the top system bar and lower task strip as real work-area
       margins. The task strip intentionally is not a DOCK window because
       Openbox otherwise stacks both Tint2 panels at the top. -->
  <margins>
    <top>34</top>
    <bottom>44</bottom>
    <left>0</left>
    <right>0</right>
  </margins>
  <applications>
    <application name="TotalJSSetup" class="TotalJSSetup" role="totaljs-setup" title="Total.js Developer Setup">
      <decor>no</decor>
      <position force="yes"><x>center</x><y>center</y></position>
      <size><width>620</width><height>480</height></size>
      <focus>yes</focus>
    </application>
    <application class="Alacritty">
      <position><x>center</x><y>center</y></position>
    </application>
  </applications>
  <keyboard>
    <keybind key="W-Return"><action name="Execute"><command>alacritty</command></action></keybind>
    <keybind key="W-d"><action name="Execute"><command>rofi -show drun</command></action></keybind>
    <keybind key="W-e"><action name="Execute"><command>pcmanfm</command></action></keybind>
    <keybind key="W-w"><action name="Execute"><command>totaljs-wallpaper next</command></action></keybind>
    <keybind key="W-space"><action name="ShowMenu"><menu>root-menu</menu></action></keybind>
    <keybind key="A-Tab"><action name="NextWindow"/></keybind>
    <keybind key="A-S-Tab"><action name="PreviousWindow"/></keybind>
    <keybind key="A-F4"><action name="Close"/></keybind>
    <keybind key="W-f"><action name="ToggleMaximizeFull"/></keybind>
    <keybind key="W-q"><action name="Close"/></keybind>
    <keybind key="W-Left"><action name="UnmaximizeFull"/><action name="MoveResizeTo"><x>0</x><y>0</y><width>50%</width><height>100%</height></action></keybind>
    <keybind key="W-Right"><action name="UnmaximizeFull"/><action name="MoveResizeTo"><x>50%</x><y>0</y><width>50%</width><height>100%</height></action></keybind>
    <!-- Virtual desktops: Super+1..4 switch, Super+Shift+1..4 send window -->
    <keybind key="W-1"><action name="GoToDesktop"><to>1</to></action></keybind>
    <keybind key="W-2"><action name="GoToDesktop"><to>2</to></action></keybind>
    <keybind key="W-3"><action name="GoToDesktop"><to>3</to></action></keybind>
    <keybind key="W-4"><action name="GoToDesktop"><to>4</to></action></keybind>
    <keybind key="W-S-1"><action name="SendToDesktop"><to>1</to></action></keybind>
    <keybind key="W-S-2"><action name="SendToDesktop"><to>2</to></action></keybind>
    <keybind key="W-S-3"><action name="SendToDesktop"><to>3</to></action></keybind>
    <keybind key="W-S-4"><action name="SendToDesktop"><to>4</to></action></keybind>
    <keybind key="C-A-Left"><action name="GoToDesktop"><to>previous</to></action></keybind>
    <keybind key="C-A-Right"><action name="GoToDesktop"><to>next</to></action></keybind>
    <!-- Window management -->
    <keybind key="A-F5"><action name="Iconify"/></keybind>
    <keybind key="A-F6"><action name="ToggleMaximizeFull"/></keybind>
    <keybind key="A-F8"><action name="ToggleDecorations"/></keybind>
    <!-- Screenshots (saved to ~/Pictures) -->
    <keybind key="Print"><action name="Execute"><command>bash -c 'mkdir -p ~/Pictures; scrot ~/Pictures/totaljs-%Y%m%d-%H%M%S.png'</command></action></keybind>
    <keybind key="A-Print"><action name="Execute"><command>bash -c 'mkdir -p ~/Pictures; scrot -s ~/Pictures/totaljs-%Y%m%d-%H%M%S.png'</command></action></keybind>
    <!-- Force-kill a frozen window -->
    <keybind key="W-Escape"><action name="Execute"><command>xkill</command></action></keybind>
    <!-- Reload Openbox config -->
    <keybind key="C-A-r"><action name="Reconfigure"/></keybind>
  </keyboard>
  <mouse>
    <dragThreshold>8</dragThreshold>
    <doubleClickTime>400</doubleClickTime>
    <screenEdgeWarpTime>400</screenEdgeWarpTime>
    <context name="Root">
      <mousebind button="Right" action="Press">
        <action name="ShowMenu"><menu>root-menu</menu></action>
      </mousebind>
      <mousebind button="Middle" action="Press">
        <action name="ShowMenu"><menu>root-menu</menu></action>
      </mousebind>
    </context>
    <context name="Desktop">
      <mousebind button="Right" action="Press">
        <action name="ShowMenu"><menu>root-menu</menu></action>
      </mousebind>
      <mousebind button="Middle" action="Press">
        <action name="ShowMenu"><menu>root-menu</menu></action>
      </mousebind>
    </context>
    <context name="Titlebar">
      <mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="Left" action="Drag"><action name="Move"/></mousebind>
      <mousebind button="Left" action="DoubleClick"><action name="ToggleMaximizeFull"/></mousebind>
      <mousebind button="Middle" action="Press"><action name="Lower"/><action name="FocusToBottom"/><action name="Unfocus"/></mousebind>
      <mousebind button="Right" action="Press"><action name="ShowMenu"><menu>client-menu</menu></action></mousebind>
    </context>
    <context name="Top"><mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/><action name="Resize"><edge>top</edge></action></mousebind></context>
    <context name="Left"><mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/><action name="Resize"><edge>left</edge></action></mousebind></context>
    <context name="Right"><mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/><action name="Resize"><edge>right</edge></action></mousebind></context>
    <context name="Bottom"><mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/><action name="Resize"><edge>bottom</edge></action></mousebind></context>
    <context name="TLCorner"><mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/><action name="Resize"><edge>tl</edge></action></mousebind></context>
    <context name="TRCorner"><mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/><action name="Resize"><edge>tr</edge></action></mousebind></context>
    <context name="BLCorner"><mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/><action name="Resize"><edge>bl</edge></action></mousebind></context>
    <context name="BRCorner"><mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/><action name="Resize"><edge>br</edge></action></mousebind></context>
    <context name="Client">
      <mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="Middle" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="Right" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
    </context>
    <context name="Frame">
      <mousebind button="W-Left" action="Drag"><action name="Move"/></mousebind>
      <mousebind button="W-Right" action="Drag"><action name="Resize"/></mousebind>
      <mousebind button="A-Left" action="Drag"><action name="Move"/></mousebind>
      <mousebind button="A-Right" action="Drag"><action name="Resize"/></mousebind>
    </context>
    <context name="MoveResize">
      <mousebind button="Up" action="Click"><action name="GoToDesktop"><to>previous</to></action></mousebind>
      <mousebind button="Down" action="Click"><action name="GoToDesktop"><to>next</to></action></mousebind>
    </context>
    <!-- Titlebar button contexts. The names MUST be exactly Iconify/Maximize/
         Close/Icon/AllDesktops/Shade — Openbox silently ignores any other name
         (the old *Button names were why the buttons drew but did nothing). -->
    <context name="Iconify">
      <mousebind button="Left" action="Click"><action name="Iconify"/></mousebind>
    </context>
    <context name="Maximize">
      <mousebind button="Left" action="Click"><action name="ToggleMaximizeFull"/></mousebind>
      <mousebind button="Middle" action="Click"><action name="ToggleMaximizeVert"/></mousebind>
      <mousebind button="Right" action="Click"><action name="ToggleMaximizeHorz"/></mousebind>
    </context>
    <context name="Close">
      <mousebind button="Left" action="Click"><action name="Close"/></mousebind>
    </context>
    <context name="Icon">
      <mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/><action name="ShowMenu"><menu>client-menu</menu></action></mousebind>
      <mousebind button="Right" action="Press"><action name="Focus"/><action name="Raise"/><action name="ShowMenu"><menu>client-menu</menu></action></mousebind>
    </context>
    <context name="AllDesktops">
      <mousebind button="Left" action="Click"><action name="ToggleOmnipresent"/></mousebind>
    </context>
    <context name="Shade">
      <mousebind button="Left" action="Click"><action name="ToggleShade"/></mousebind>
    </context>
  </mouse>
</openbox_config>
EOF

# --- Tint2: top system bar + current-desktop dock --------------------------
install -d /usr/local/share/icons
install -m 0644 "${TOTALVM_ASSETS:-/mnt/assets}/desktop/totaljs-panel.svg" \
    /usr/local/share/icons/totaljs-panel.svg

cat > /usr/share/applications/totaljs-menu.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Total.js
Comment=Open the Total.js Developer menu
Exec=xdotool key Super_L+space
Icon=/usr/local/share/icons/totaljs-panel.svg
Terminal=false
Categories=System;
NoDisplay=true
EOF

cat > /usr/local/bin/totaljs-desktop-status <<'EOF'
#!/usr/bin/env bash
desktop="${1:-1}"
current="$(xdotool get_desktop 2>/dev/null || printf '0')"
target=$((desktop - 1))

if [ "${current}" = "${target}" ]; then
    printf '<span foreground="#11161a" background="#6ac043"><b>  %s  </b></span>\n' "${desktop}"
else
    printf '<span foreground="#8b949e"><b>  %s  </b></span>\n' "${desktop}"
fi
EOF
chmod +x /usr/local/bin/totaljs-desktop-status

cat > /usr/local/bin/totaljs-panel-status <<'EOF'
#!/usr/bin/env bash
set -u

# Tint2 calls this every five seconds. Derive CPU activity from two cumulative
# /proc/stat samples and retain a tiny history instead of showing a percentage
# that inevitably disagrees with Conky's different sampling window.
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/totaljs-$(id -u)}"
STATE_FILE="${RUNTIME_DIR}/panel-activity"
mkdir -p "${RUNTIME_DIR}"
chmod 0700 "${RUNTIME_DIR}" 2>/dev/null || true

read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
total=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle_total=$((idle + iowait))
previous_total=${total}
previous_idle=${idle_total}
cpu_history=
memory_history=
if [ -r "${STATE_FILE}" ]; then
    read -r previous_total previous_idle cpu_history memory_history < "${STATE_FILE}" || true
fi

delta_total=$((total - previous_total))
delta_idle=$((idle_total - previous_idle))
if [ "${delta_total}" -gt 0 ]; then
    cpu=$((100 * (delta_total - delta_idle) / delta_total))
else
    cpu=0
fi

memory_total="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)"
memory_available="$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo)"
if [ -n "${memory_total}" ] && [ "${memory_total}" -gt 0 ]; then
    memory=$((100 * (memory_total - memory_available) / memory_total))
else
    memory=0
fi

level() {
    case "$1" in
        [0-9]|1[0-2]) printf '1' ;;
        1[3-9]|2[0-4]) printf '2' ;;
        2[5-9]|3[0-6]) printf '3' ;;
        3[7-9]|4[0-9]) printf '4' ;;
        5[0-9]|6[0-1]) printf '5' ;;
        6[2-9]|7[0-4]) printf '6' ;;
        7[5-9]|8[0-7]) printf '7' ;;
        *) printf '8' ;;
    esac
}

# Store ASCII levels so history trimming is independent of locale and Bash's
# handling of multibyte characters. Convert to Unicode blocks only for output.
cpu_history="${cpu_history}$(level "${cpu}")"
memory_history="${memory_history}$(level "${memory}")"
[ "${#cpu_history}" -le 8 ] || cpu_history="${cpu_history: -8}"
[ "${#memory_history}" -le 8 ] || memory_history="${memory_history: -8}"
printf '%s %s %s %s\n' "${total}" "${idle_total}" "${cpu_history}" "${memory_history}" \
    > "${STATE_FILE}"

graph() {
    local levels="$1" result=
    while [ -n "${levels}" ]; do
        case "${levels:0:1}" in
            1) result="${result}▁" ;;
            2) result="${result}▂" ;;
            3) result="${result}▃" ;;
            4) result="${result}▄" ;;
            5) result="${result}▅" ;;
            6) result="${result}▆" ;;
            7) result="${result}▇" ;;
            8) result="${result}█" ;;
        esac
        levels="${levels:1}"
    done
    printf '%s' "${result}"
}
cpu_graph="$(graph "${cpu_history}")"
memory_graph="$(graph "${memory_history}")"

if ip route get 1.1.1.1 >/dev/null 2>&1; then
    net='<span foreground="#6ac043">NET</span>'
else
    net='<span foreground="#e75a5a">NET</span>'
fi
if systemctl is-active --quiet docker; then
    docker='<span foreground="#6ac043">DOCKER</span>'
else
    docker='<span foreground="#8b949e">DOCKER</span>'
fi
printf 'CPU <span foreground="#6ac043">%s</span>   MEM <span foreground="#7aa2d6">%s</span>   %s   %s\n' \
    "${cpu_graph}" "${memory_graph}" "${net}" "${docker}"
EOF
chmod +x /usr/local/bin/totaljs-panel-status

cat > "${USER_HOME}/.config/tint2/top.tint2rc" <<'EOF'
# Background 1: system bar
rounded = 0
border_width = 0
border_sides = B
background_color = #11161a 96
border_color = #303840 100

# Background 2: interactive hover surface
rounded = 5
border_width = 0
background_color = #20272d 0
background_color_hover = #2a3239 100
background_color_pressed = #334028 100

panel_items = LFESCE
panel_size = 100% 34
panel_margin = 0 0
panel_padding = 18 2 8
panel_position = top center horizontal
panel_background_id = 1
panel_dock = 0
panel_layer = top
strut_policy = none
wm_menu = 1
font_shadow = 0

launcher_padding = 5 2 4
launcher_background_id = 2
launcher_icon_background_id = 0
launcher_icon_size = 24
launcher_tooltip = 1
launcher_icon_theme = Papirus-Dark
launcher_icon_theme_override = 1
launcher_item_app = /usr/share/applications/totaljs-menu.desktop

execp = new
execp_name = system-status
execp_command = /usr/local/bin/totaljs-panel-status
execp_interval = 5
execp_has_icon = 0
execp_markup = 1
execp_font = Noto Sans 9
execp_font_color = #aeb6be 100
execp_background_id = 2
execp_centered = 1
execp_padding = 10 2 0
execp_tooltip = Activity history — click to open htop
execp_lclick_command = alacritty -e htop

systray_padding = 7 3 5
systray_background_id = 0
systray_sort = right2left
systray_icon_size = 18
# Render status icons as white silhouettes on the dark panel while preserving
# each icon's alpha mask (network state and volume remain recognisable).
systray_icon_asb = 100 -100 100

time1_format = %a %d %b   %H:%M
time1_font = Noto Sans Bold 9
clock_font_color = #e4e8eb 100
clock_padding = 10 2
clock_background_id = 2
clock_tooltip = %A, %d %B %Y
clock_lclick_command = gsimplecal

# A real final panel item guarantees breathing room after the clock. Tint2 can
# collapse outer padding depending on the combination of freespace and tray.
execp = new
execp_name = right-edge-spacer
execp_command = printf '<span foreground="#11161a">.</span>'
execp_interval = 0
execp_has_icon = 0
execp_markup = 1
execp_font = Noto Sans 1
execp_padding = 9 0 0

tooltip_padding = 8 5
tooltip_show_timeout = 0.4
tooltip_hide_timeout = 0.1
tooltip_background_id = 1
tooltip_font_color = #e4e8eb 100
tooltip_font = Noto Sans 9
EOF

cat > "${USER_HOME}/.config/tint2/dock.tint2rc" <<'EOF'
# Background 1: dock
rounded = 8
border_width = 1
border_sides = TBLR
background_color = #181d22 92
border_color = #343d45 90

# Background 2: normal window
rounded = 5
border_width = 0
background_color = #242b31 55
background_color_hover = #303941 100
background_color_pressed = #20262b 100

# Background 3: active window
rounded = 5
border_width = 1
border_sides = B
background_color = #2b3529 100
border_color = #6ac043 100

# Background 4: urgent window
rounded = 5
border_width = 1
background_color = #3a2325 100
border_color = #e75a5a 100

panel_items = EEEETFE
panel_size = 88% 44
panel_margin = 0 0
panel_padding = 7 5 7
panel_position = bottom center horizontal
panel_background_id = 1
# Openbox puts every DOCK window into one shared top container. Keep the task
# strip independent so Tint2 can honor its explicit bottom position.
panel_dock = 0
panel_layer = top
strut_policy = none
wm_menu = 1

# Workspace navigation belongs with windows: desktops stay fixed at the left,
# followed by the current desktop's tasks and Trash at the far right.
execp = new
execp_name = desktop-1
execp_command = /usr/local/bin/totaljs-desktop-status 1
execp_interval = 1
execp_has_icon = 0
execp_markup = 1
execp_font = Noto Sans Bold 9
execp_background_id = 2
execp_centered = 1
execp_padding = 1 2 0
execp_tooltip = Desktop 1 (Super+1)
execp_lclick_command = xdotool set_desktop 0

execp = new
execp_name = desktop-2
execp_command = /usr/local/bin/totaljs-desktop-status 2
execp_interval = 1
execp_has_icon = 0
execp_markup = 1
execp_font = Noto Sans Bold 9
execp_background_id = 2
execp_centered = 1
execp_padding = 1 2 0
execp_tooltip = Desktop 2 (Super+2)
execp_lclick_command = xdotool set_desktop 1

execp = new
execp_name = desktop-3
execp_command = /usr/local/bin/totaljs-desktop-status 3
execp_interval = 1
execp_has_icon = 0
execp_markup = 1
execp_font = Noto Sans Bold 9
execp_background_id = 2
execp_centered = 1
execp_padding = 1 2 0
execp_tooltip = Desktop 3 (Super+3)
execp_lclick_command = xdotool set_desktop 2

execp = new
execp_name = desktop-4
execp_command = /usr/local/bin/totaljs-desktop-status 4
execp_interval = 1
execp_has_icon = 0
execp_markup = 1
execp_font = Noto Sans Bold 9
execp_background_id = 2
execp_centered = 1
execp_padding = 1 2 0
execp_tooltip = Desktop 4 (Super+4)
execp_lclick_command = xdotool set_desktop 3

taskbar_mode = single_desktop
taskbar_name = 0
taskbar_padding = 3 0 5
taskbar_background_id = 0
taskbar_active_background_id = 0
taskbar_hide_if_empty = 0

task_icon = 1
task_text = 1
task_centered = 1
task_tooltip = 1
task_maximum_size = 190 34
task_padding = 9 4 7
task_font = Noto Sans 9
task_font_color = #b7bec5 100
task_active_font_color = #ffffff 100
task_iconified_font_color = #7f8992 100
task_urgent_font_color = #ffffff 100
task_background_id = 2
task_active_background_id = 3
task_iconified_background_id = 0
task_urgent_background_id = 4
task_icon_asb = 90 0 0
task_active_icon_asb = 100 0 5
task_iconified_icon_asb = 55 -40 -10

# Dynamic Trash at the right edge: the executor reloads its icon every two
# seconds, opens on left click and shows its GTK context menu on right click.
execp = new
execp_name = trash
execp_command = /usr/local/bin/totaljs-trash-status
execp_interval = 2
execp_has_icon = 1
execp_cache_icon = 0
execp_icon_w = 25
execp_icon_h = 25
execp_background_id = 2
execp_centered = 1
execp_padding = 10 4 0
execp_tooltip = Trash
execp_lclick_command = pcmanfm trash:///
execp_rclick_command = /usr/local/bin/totaljs-trash-menu

mouse_left = toggle_iconify
mouse_middle = close
mouse_right = none
mouse_scroll_up = prev_task
mouse_scroll_down = next_task

tooltip_padding = 8 5
tooltip_show_timeout = 0.4
tooltip_hide_timeout = 0.1
tooltip_background_id = 1
tooltip_font_color = #e4e8eb 100
tooltip_font = Noto Sans 9
EOF

cat > "${USER_HOME}/.config/conky/totalvm.conf" <<'EOF'
conky.config = {
  alignment = 'top_left',
  background = true,
  update_interval = 2,
  double_buffer = true,
  own_window = true,
  own_window_type = 'desktop',
  own_window_transparent = false,
  own_window_argb_visual = true,
  own_window_argb_value = 145,
  own_window_colour = '11161a',
  own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
  use_xft = true,
  font = 'Fira Code:size=10',
  xftalpha = 0.95,
  gap_x = 42,
  gap_y = 48,
  minimum_width = 315,
  maximum_width = 315,
  border_inner_margin = 14,
  default_color = 'd7d9dc',
  color1 = '6ac043',
  color2 = '8b949e',
  color3 = '20262c',
  draw_shades = false,
  default_shade_color = '000000',
  draw_outline = false,
  draw_borders = false,
};

conky.text = [[
${font Noto Sans:bold:size=17}${color1}Total.js Developer Distro${font}
${color2}Desktop Edition  ${alignr}${machine}
${color2}${kernel}  ${alignr}up ${uptime_short}
${color1}${hr 1}

${color2}CPU${color} ${cpu cpu0}% ${alignr}${freq_g} GHz
${cpugraph cpu0 34,315 20262c 6ac043 -t}
${top name 1}${alignr}${top cpu 1}%
${top name 2}${alignr}${top cpu 2}%
${top name 3}${alignr}${top cpu 3}%

${color2}RAM${color} ${mem} / ${memmax} ${alignr}${memperc}%
${membar 7,315}
${memgraph 28,315 20262c 6ac043 -t}

${color2}Disk${color} ${fs_used /} / ${fs_size /} ${alignr}${fs_used_perc /}%
${fs_bar 7,315 /}
${color2}I/O${color} ${diskio_read} read ${alignr}${diskio_write} write
${diskiograph 24,315 20262c 6ac043 -t}

${color2}Network${color} ${addr eth0}
${color2}Down${color} ${downspeed eth0}/s ${alignr}${color2}Up${color} ${upspeed eth0}/s
${downspeedgraph eth0 24,153 20262c 6ac043 -t}${alignr}${upspeedgraph eth0 24,153 20262c 6ac043 -t}

${color2}Docker${color} ${execi 10 systemctl is-active docker 2>/dev/null}
${color2}Containers${color} ${execi 10 sh -c "docker ps -q 2>/dev/null | wc -l"} running
${color2}PostgreSQL${color} ${execi 10 docker inspect -f '{{.State.Status}}' postgres 2>/dev/null}
${color2}Code${color} ${execi 10 docker inspect -f '{{.State.Status}}' code 2>/dev/null}

${color2}Projects${color} /www/www
${color1}${hr 1}
${color2}Super+Enter${color} Terminal
${color2}Super+D${color} Launcher
${color2}Super+Space${color} Menu
${color2}Super+W${color} Wallpaper
${color2}Super+1-4${color} Desktops
]];
EOF

cat > "${USER_HOME}/.config/conky/minimal.conf" <<'EOF'
conky.config = {
  alignment = 'top_left', background = true, update_interval = 2,
  double_buffer = true, own_window = true, own_window_type = 'desktop',
  own_window_transparent = true, own_window_argb_visual = true,
  own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
  use_xft = true, font = 'Noto Sans:size=10', xftalpha = 0.96,
  gap_x = 48, gap_y = 52, minimum_width = 330, maximum_width = 330,
  default_color = 'e7eaed', color1 = '6ac043', color2 = 'a1a8ae',
  color3 = '303840', draw_shades = true, default_shade_color = '000000',
};

conky.text = [[
${font Noto Sans:light:size=28}${color}Total.js${font}
${font Noto Sans:bold:size=11}${color1}DEVELOPER  /  UBUNTU LTS${font}${alignr}${color2}${machine}
${voffset 10}${color3}${hr 1}
${voffset 14}${font Noto Sans:light:size=34}${color}${cpu}%${font}${alignr}${font Noto Sans:size=9}${color2}CPU${font}
${alignr}${color2}${freq_g} GHz
${cpugraph cpu0 42,330 303840 6ac043 -t}
${color2}${top name 1}${alignr}${top cpu 1}%
${top name 2}${alignr}${top cpu 2}%
${voffset 12}${font Noto Sans:light:size=28}${color}${memperc}%${font}${alignr}${font Noto Sans:size=9}${color2}MEMORY${font}
${alignr}${color2}${mem} / ${memmax}
${membar 5,330}
${voffset 12}${font Noto Sans:light:size=28}${color}${fs_used_perc /}%${font}${alignr}${font Noto Sans:size=9}${color2}STORAGE${font}
${alignr}${color2}${fs_used /} / ${fs_size /}
${fs_bar 5,330 /}
${color2}${diskio_read} read${alignr}${diskio_write} write
${voffset 12}${font Noto Sans:bold:size=11}${color1}NETWORK${font}${alignr}${color}${addr eth0}
${color2}${downspeed eth0}/s down${alignr}${upspeed eth0}/s up
${downspeedgraph eth0 28,160 303840 6ac043 -t}${alignr}${upspeedgraph eth0 28,160 303840 6ac043 -t}
${voffset 12}${font Noto Sans:bold:size=11}${color1}WORKSPACE${font}
${color2}Docker${alignr}${color}${execi 10 systemctl is-active docker 2>/dev/null}
${color2}Containers${alignr}${color}${execi 10 sh -c "docker ps -q 2>/dev/null | wc -l"} running
${color2}PostgreSQL${alignr}${color}${execi 10 docker inspect -f '{{.State.Status}}' postgres 2>/dev/null}
${color2}Code${alignr}${color}${execi 10 docker inspect -f '{{.State.Status}}' code 2>/dev/null}
${color2}Projects${alignr}${color}/www/www
${voffset 12}${color3}${hr 1}
${color2}${kernel}${alignr}up ${uptime_short}
${color2}Super+Enter  Terminal   Super+W  Wallpaper
]];
EOF

cat > "${USER_HOME}/.config/conky/terminal.conf" <<'EOF'
conky.config = {
  alignment = 'top_left', background = true, update_interval = 2,
  double_buffer = true, own_window = true, own_window_type = 'desktop',
  own_window_transparent = false, own_window_argb_visual = true,
  own_window_argb_value = 205,
  own_window_colour = '0b0f0c',
  own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
  use_xft = true, font = 'Fira Code:size=10', xftalpha = 1,
  gap_x = 28, gap_y = 50, minimum_width = 350, maximum_width = 350,
  border_inner_margin = 18, default_color = 'c7d0c9',
  color1 = '78d64b', color2 = '738078', color3 = '27332b',
  draw_shades = false, draw_borders = false,
};

conky.text = [[
${color1}${exec whoami}@totaljs${color}:${color2}~${color}$ totalfetch
${color1}       _______     ${color}Total.js Developer
${color1}    __/ _____  \__  ${color2}Total.js Developer Distro / ${machine}
${color1}   /__ /     \ __\ ${color2}${kernel}
${color1}      \_____ /     ${color2}up ${uptime_short}
${color3}${hr 1}
${color1}> cpu${color}  ${cpu}% @ ${freq_g} GHz
${cpugraph cpu0 36,350 27332b 78d64b -t}
${color2}  ${top name 1}${alignr}${top cpu 1}%
  ${top name 2}${alignr}${top cpu 2}%
  ${top name 3}${alignr}${top cpu 3}%
${color1}> mem${color}  ${mem} / ${memmax} (${memperc}%)
${membar 6,350}
${color1}> disk${color} ${fs_used /} / ${fs_size /} (${fs_used_perc /}%)
${fs_bar 6,350 /}
${color2}  io: ${diskio_read} read${alignr}${diskio_write} write
${diskiograph 24,350 27332b 78d64b -t}
${color1}> net${color}  ${addr eth0}
${color2}  rx ${downspeed eth0}/s${alignr}tx ${upspeed eth0}/s
${downspeedgraph eth0 25,171 27332b 78d64b -t}${alignr}${upspeedgraph eth0 25,171 27332b 78d64b -t}
${color1}> services
${color2}  docker${alignr}${color}${execi 10 systemctl is-active docker 2>/dev/null}
${color2}  containers${alignr}${color}${execi 10 sh -c "docker ps -q 2>/dev/null | wc -l"} running
${color2}  postgres${alignr}${color}${execi 10 docker inspect -f '{{.State.Status}}' postgres 2>/dev/null}
${color2}  code${alignr}${color}${execi 10 docker inspect -f '{{.State.Status}}' code 2>/dev/null}
${color1}> projects${color} /www/www
${color3}${hr 1}
${color2}[super+enter] terminal  [super+d] apps
[super+space] menu     [super+w] wallpaper
]];
EOF

cat > "${USER_HOME}/.config/conky/dashboard.conf" <<'EOF'
conky.config = {
  alignment = 'top_left', background = true, update_interval = 2,
  double_buffer = true, own_window = true, own_window_type = 'desktop',
  own_window_transparent = false, own_window_argb_visual = true,
  own_window_argb_value = 178, own_window_colour = '13191d',
  own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
  use_xft = true, font = 'Noto Sans:size=10', xftalpha = 0.98,
  gap_x = 28, gap_y = 50, minimum_width = 370, maximum_width = 370,
  border_inner_margin = 20, default_color = 'e5e9ec',
  color1 = '6ac043', color2 = '929ca4', color3 = '35414a',
  draw_shades = false,
};

conky.text = [[
${font Noto Sans:bold:size=20}${color}Developer ${color1}Dashboard${font}
${color2}Total.js Developer Distro  /  ${machine}${alignr}up ${uptime_short}
${voffset 8}${color3}${hr 1}
${voffset 10}${font Noto Sans:bold:size=10}${color1}PERFORMANCE${font}
${color2}CPU${color} ${cpu}%${alignr}${color2}${freq_g} GHz
${cpubar 8,370}
${cpugraph cpu0 40,370 35414a 6ac043 -t}
${color2}${top name 1}${alignr}${top cpu 1}%
${top name 2}${alignr}${top cpu 2}%
${voffset 8}${color2}MEMORY${color} ${memperc}%${alignr}${color2}${mem} / ${memmax}
${membar 8,370}
${memgraph 30,370 35414a 6ac043 -t}
${voffset 10}${font Noto Sans:bold:size=10}${color1}STORAGE + NETWORK${font}
${color2}ROOT${color} ${fs_used_perc /}%${alignr}${color2}${fs_free /} free
${fs_bar 8,370 /}
${color2}I/O${color} ${diskio_read}${alignr}${diskio_write}
${color2}IP${color} ${addr eth0}
${color2}DOWN${color} ${downspeed eth0}/s${alignr}${color2}UP ${color}${upspeed eth0}/s
${downspeedgraph eth0 28,181 35414a 6ac043 -t}${alignr}${upspeedgraph eth0 28,181 35414a 6ac043 -t}
${voffset 10}${font Noto Sans:bold:size=10}${color1}DEVELOPER SERVICES${font}
${color2}Docker${alignr}${color}${execi 10 systemctl is-active docker 2>/dev/null}
${color2}Running containers${alignr}${color}${execi 10 sh -c "docker ps -q 2>/dev/null | wc -l"}
${color2}PostgreSQL${alignr}${color}${execi 10 docker inspect -f '{{.State.Status}}' postgres 2>/dev/null}
${color2}Code${alignr}${color}${execi 10 docker inspect -f '{{.State.Status}}' code 2>/dev/null}
${color2}Projects${alignr}${color}/www/www
${voffset 10}${color3}${hr 1}
${color2}${kernel}${alignr}Super+W changes wallpaper
]];
EOF

cat > "${USER_HOME}/.config/conky/compact.conf" <<'EOF'
conky.config = {
  alignment = 'top_left',
  background = true,
  update_interval = 2,
  double_buffer = true,
  own_window = true,
  own_window_type = 'desktop',
  own_window_transparent = false,
  own_window_argb_visual = true,
  own_window_argb_value = 145,
  own_window_colour = '11161a',
  own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
  use_xft = true,
  font = 'Fira Code:size=10',
  gap_x = 42,
  gap_y = 48,
  minimum_width = 245,
  maximum_width = 245,
  border_inner_margin = 14,
  default_color = 'd7d9dc',
  color1 = '6ac043',
  color2 = '8b949e',
  draw_shades = false,
  default_shade_color = '000000',
};

conky.text = [[
${font Noto Sans:bold:size=18}${color1}Total.js${font}
${color2}Developer Distro
${color1}${hr 1}
${color2}CPU${color} ${cpu}% ${alignr}${freq_g} GHz
${cpubar 6,245}
${color2}RAM${color} ${memperc}% ${alignr}${mem}
${membar 6,245}
${color2}Disk${color} ${fs_used_perc /}% ${alignr}${fs_free /} free
${fs_bar 6,245 /}
${color2}IP${color} ${addr eth0}
${color1}${hr 1}
${color2}Super+Enter${color} Terminal
${color2}Super+D${color} Launcher
${color2}Super+Space${color} Menu
${color2}Super+W${color} Wallpaper
${color2}Super+1-4${color} Desktops
]];
EOF

cat > "${USER_HOME}/.config/conky/services.conf" <<'EOF'
conky.config = {
  alignment = 'top_left',
  background = true,
  update_interval = 3,
  double_buffer = true,
  own_window = true,
  own_window_type = 'desktop',
  own_window_transparent = false,
  own_window_argb_visual = true,
  own_window_argb_value = 145,
  own_window_colour = '11161a',
  own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
  use_xft = true,
  font = 'Fira Code:size=10',
  gap_x = 42,
  gap_y = 48,
  minimum_width = 285,
  maximum_width = 285,
  border_inner_margin = 14,
  default_color = 'd7d9dc',
  color1 = '6ac043',
  color2 = '8b949e',
  draw_shades = false,
  default_shade_color = '000000',
};

conky.text = [[
${font Noto Sans:bold:size=18}${color1}Services${font}
${color2}Total.js Developer
${color1}${hr 1}
${color2}Docker${color} ${alignr}${execi 10 systemctl is-active docker 2>/dev/null}
${color2}PostgreSQL${color} ${alignr}${execi 10 docker inspect -f '{{.State.Status}}' postgres 2>/dev/null}
${color2}Code${color} ${alignr}${execi 10 docker inspect -f '{{.State.Status}}' code 2>/dev/null}
${color2}SSH${color} ${alignr}${execi 10 systemctl is-active ssh 2>/dev/null}
${color2}Projects${color} ${alignr}/www/www
${color2}IP${color} ${alignr}${addr eth0}
${color1}${hr 1}
${color2}Super+Enter${color} Terminal
${color2}Super+D${color} Launcher
${color2}Super+Space${color} Menu
${color2}Super+W${color} Wallpaper
${color2}Super+1-4${color} Desktops
]];
EOF

cat > /usr/local/bin/totaljs-conky <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
PROFILE="${1:-system}"
STATE_DIR="$HOME/.config/totaljs"
PROFILE_FILE="$STATE_DIR/conky-profile"
mkdir -p "$STATE_DIR"

if [ "$PROFILE" = restore ]; then
  PROFILE="$(cat "$PROFILE_FILE" 2>/dev/null || echo system)"
fi

if [ "$PROFILE" = hidden ]; then
  echo hidden > "$PROFILE_FILE"
  pkill conky 2>/dev/null || true
  exit 0
fi

CONFIG="$HOME/.config/conky/totalvm.conf"
case "$PROFILE" in
  system) CONFIG="$HOME/.config/conky/totalvm.conf" ;;
  compact) CONFIG="$HOME/.config/conky/compact.conf" ;;
  services) CONFIG="$HOME/.config/conky/services.conf" ;;
  *) PROFILE=system; CONFIG="$HOME/.config/conky/totalvm.conf" ;;
esac
echo "$PROFILE" > "$PROFILE_FILE"
pkill conky 2>/dev/null || true
nohup conky -c "$CONFIG" >/dev/null 2>&1 &
EOF
chmod +x /usr/local/bin/totaljs-conky

install -d -o totaljs -g totaljs "${USER_HOME}/.config/alacritty"
cat > "${USER_HOME}/.config/alacritty/alacritty.toml" <<'EOF'
[window]
padding = { x = 12, y = 12 }
opacity = 0.96

[font]
normal = { family = "Fira Code", style = "Regular" }
size = 12

[colors.primary]
background = "#15181c"
foreground = "#d7d9dc"

[colors.normal]
black = "#15181c"
red = "#e75a5a"
green = "#6ac043"
yellow = "#d8b45d"
blue = "#4da3ff"
magenta = "#b47cff"
cyan = "#55c7c2"
white = "#d7d9dc"

[colors.bright]
black = "#2a3036"
red = "#ff7b7b"
green = "#9ad959"
yellow = "#e8c87a"
blue = "#74b9ff"
magenta = "#cda0ff"
cyan = "#74d6d1"
white = "#ffffff"

[colors.cursor]
cursor = "#6ac043"
text = "#15181c"

[colors.selection]
background = "#2c3a22"
text = "CellForeground"
EOF

# The /usr/local/bin/totaljs-first-run launcher and its autostart entry are
# installed by 45-firstrun-wizard.sh (GTK setup wizard).

chown -R totaljs:totaljs "${USER_HOME}/.config"

# Session skeleton shared by every account created later. Keeping the complete
# profile here mirrors ArchLabs' base + session model and gives Ubuntu and Arch
# one source of truth instead of teaching the first-run wizard every dotfile.
install -d /etc/skel/.config
for profile in openbox tint2 alacritty conky picom rofi dunst gsimplecal; do
    rm -rf "/etc/skel/.config/${profile}"
    cp -a "${USER_HOME}/.config/${profile}" "/etc/skel/.config/${profile}"
done

echo "[30-desktop] done"
