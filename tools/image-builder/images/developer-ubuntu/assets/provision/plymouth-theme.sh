#!/usr/bin/env bash
# Total.js Developer — Plymouth splash theme (shared). The distro 35-branding
# installs plymouth + imagemagick, runs this, then wires initramfs + bootloader.
set -euo pipefail
install -d /usr/share/totalvm /usr/share/plymouth/themes/totalvm
SPLASH_TITLE="${TOTALVM_SPLASH_TITLE:-Total.js Developer Distro}"
SPLASH_SUBTITLE="${TOTALVM_SPLASH_SUBTITLE:-Developer Distro}"

if command -v magick >/dev/null 2>&1; then
    IMAGEMAGICK=(magick)
else
    IMAGEMAGICK=(convert)
fi

# Tiny generated progress textures keep the theme self-contained.
"${IMAGEMAGICK[@]}" -size 16x5 xc:'#2a3036' /usr/share/plymouth/themes/totalvm/progress-bg.png
"${IMAGEMAGICK[@]}" -size 16x5 xc:'#6ac043' /usr/share/plymouth/themes/totalvm/progress-fg.png

cat > /usr/share/plymouth/themes/totalvm/totalvm.plymouth <<'EOF'
[Plymouth Theme]
Name=Total.js Developer
Description=Total.js developer environment boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/totalvm
ScriptFile=/usr/share/plymouth/themes/totalvm/totalvm.script
EOF

ASSETS_BOOT="${TOTALVM_ASSETS:-/mnt/assets}/boot"
if [ -f "${ASSETS_BOOT}/hexagon.png" ] && [ -f "${ASSETS_BOOT}/letter.png" ]; then
    # Same mark used in the Total.js UI loading animation: the hexagon spins
    # 0deg -> 180deg every second while the "T" stays still. The hexagon has
    # 180deg point symmetry, so the loop has no visible snap.
    # Plymouth's Image.Rotate() returns an image the SAME size as the source
    # and clips whatever falls outside that box — so a tightly-cropped hexagon
    # gets its corners sheared off as it spins. Pad both marks onto a generous
    # transparent square (source is ~320x370; its rotation diagonal is ~490) so
    # the hexagon always has room to turn without touching the edges. Both are
    # padded to the SAME canvas so the still "T" stays perfectly centred over
    # the spinning hexagon.
    cp "${ASSETS_BOOT}/hexagon.png" /usr/share/plymouth/themes/totalvm/hexagon-src.png
    cp "${ASSETS_BOOT}/letter.png" /usr/share/plymouth/themes/totalvm/letter-src.png
    "${IMAGEMAGICK[@]}" /usr/share/plymouth/themes/totalvm/hexagon-src.png \
        -background none -gravity center -extent 540x540 \
        /usr/share/plymouth/themes/totalvm/hexagon.png
    "${IMAGEMAGICK[@]}" /usr/share/plymouth/themes/totalvm/letter-src.png \
        -background none -gravity center -extent 540x540 \
        /usr/share/plymouth/themes/totalvm/letter.png
    rm -f /usr/share/plymouth/themes/totalvm/hexagon-src.png \
          /usr/share/plymouth/themes/totalvm/letter-src.png

    cat > /usr/share/plymouth/themes/totalvm/totalvm.script <<EOF
Window.SetBackgroundTopColor(0.07, 0.08, 0.09);
Window.SetBackgroundBottomColor(0.10, 0.12, 0.14);

screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

# The PNGs are a 540x540 transparent square with the ~370px mark centred, so
# the box is sized up to keep the visible hexagon at roughly its old 190px.
logo_height = 270;
hex_base = Image("hexagon.png");
letter_base = Image("letter.png");
logo_width = logo_height * hex_base.GetWidth() / hex_base.GetHeight();

hex_scaled = hex_base.Scale(logo_width, logo_height);
letter_scaled = letter_base.Scale(logo_width, logo_height);

logo_center_x = screen_width / 2;
logo_center_y = (screen_height / 2) - 90;

hex_sprite = Sprite(hex_scaled);
hex_sprite.SetX(logo_center_x - logo_width / 2);
hex_sprite.SetY(logo_center_y - logo_height / 2);

letter_sprite = Sprite(letter_scaled);
letter_sprite.SetX(logo_center_x - logo_width / 2);
letter_sprite.SetY(logo_center_y - logo_height / 2);

title_image = Image.Text("${SPLASH_TITLE}", 1.0, 1.0, 1.0);
title_sprite = Sprite(title_image);
title_sprite.SetX((screen_width - title_image.GetWidth()) / 2);
title_sprite.SetY(logo_center_y + logo_height / 2 + 36);

subtitle_image = Image.Text("${SPLASH_SUBTITLE}", 0.42, 0.75, 0.28);
subtitle_sprite = Sprite(subtitle_image);
subtitle_sprite.SetX((screen_width - subtitle_image.GetWidth()) / 2);
subtitle_sprite.SetY(logo_center_y + logo_height / 2 + 70);

bar_width = 260;
bar_height = 5;
bar_x = (screen_width - bar_width) / 2;
bar_y = logo_center_y + logo_height / 2 + 112;

bar_bg_sprite = Sprite(Image("progress-bg.png").Scale(bar_width, bar_height));
bar_bg_sprite.SetX(bar_x);
bar_bg_sprite.SetY(bar_y);

bar_fg_sprite = Sprite();
bar_fg_sprite.SetX(bar_x);
bar_fg_sprite.SetY(bar_y);

PI = 3.14159265;
spin_time = 1.1;    # seconds for one full 360 turn
pause_time = 1.6;   # seconds resting upright between turns
cycle_time = spin_time + pause_time;

fun progress_callback(duration, progress) {
    if (progress < 0.0) progress = 0.0;
    if (progress > 1.0) progress = 1.0;

    # Find the phase within the current cycle (t) and the cycle index (n).
    t = duration;
    n = 0;
    while (t >= cycle_time) { t -= cycle_time; n += 1; }

    # Alternate spin direction every cycle: even = clockwise, odd = counter.
    m = n;
    while (m >= 2) m -= 2;
    dir = 1;
    if (m == 1) dir = -1;

    # Spin a full turn, then hold upright. A full 360 lands exactly where it
    # started, so the spin->pause->next-spin loop has no visible snap.
    if (t < spin_time) {
        angle = dir * 2 * PI * (t / spin_time);
    } else {
        angle = 0;
    }

    rotated_hex = hex_scaled.Rotate(angle);
    hex_sprite.SetImage(rotated_hex);
    hex_sprite.SetX(logo_center_x - rotated_hex.GetWidth() / 2);
    hex_sprite.SetY(logo_center_y - rotated_hex.GetHeight() / 2);

    fg_width = bar_width * progress;
    if (fg_width < 1) fg_width = 1;
    bar_fg_sprite.SetImage(Image("progress-fg.png").Scale(fg_width, bar_height));
}

Plymouth.SetBootProgressFunction(progress_callback);
EOF
else
    if [ -f "${TOTALVM_ASSETS:-/mnt/assets}/totalvm.png" ]; then
        cp "${TOTALVM_ASSETS}/totalvm.png" /usr/share/totalvm/totalvm.png
        cp "${TOTALVM_ASSETS}/totalvm.png" /usr/share/plymouth/themes/totalvm/logo.png
    fi

    cat > /usr/share/plymouth/themes/totalvm/totalvm.script <<EOF
Window.SetBackgroundTopColor(0.07, 0.08, 0.09);
Window.SetBackgroundBottomColor(0.10, 0.12, 0.14);

screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

logo = Image("logo.png").Scale(132, 132);
logo_sprite = Sprite(logo);
logo_sprite.SetX((screen_width - 132) / 2);
logo_sprite.SetY((screen_height / 2) - 118);

title_image = Image.Text("${SPLASH_TITLE}", 1.0, 1.0, 1.0);
title_sprite = Sprite(title_image);
title_sprite.SetX((screen_width - title_image.GetWidth()) / 2);
title_sprite.SetY((screen_height / 2) + 32);

subtitle_image = Image.Text("${SPLASH_SUBTITLE}", 0.42, 0.75, 0.28);
subtitle_sprite = Sprite(subtitle_image);
subtitle_sprite.SetX((screen_width - subtitle_image.GetWidth()) / 2);
subtitle_sprite.SetY((screen_height / 2) + 66);

fun progress_callback(duration, progress) {
    if (progress < 0.0) progress = 0.0;
    if (progress > 1.0) progress = 1.0;

    bar_width = 260;
    bar_height = 5;
    x = (screen_width - bar_width) / 2;
    y = (screen_height / 2) + 112;

    bg = Image("progress-bg.png");
    fg = Image("progress-fg.png");
    bg_sprite = Sprite(bg.Scale(bar_width, bar_height));
    fg_sprite = Sprite(fg.Scale(bar_width * progress, bar_height));
    bg_sprite.SetX(x);
    bg_sprite.SetY(y);
    fg_sprite.SetX(x);
    fg_sprite.SetY(y);
}

Plymouth.SetBootProgressFunction(progress_callback);
EOF
fi
