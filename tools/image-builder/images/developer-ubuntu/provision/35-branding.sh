#!/usr/bin/env bash
# Step 35 (Ubuntu) — boot splash. Install plymouth, write the shared theme, then
# wire it into the Ubuntu initramfs (initramfs-tools) and GRUB.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get install -y --no-install-recommends plymouth plymouth-themes imagemagick

export TOTALVM_SPLASH_TITLE="Total.js Developer Distro"
export TOTALVM_SPLASH_SUBTITLE="Desktop Edition"
bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/plymouth-theme.sh"

# For Plymouth to paint a GRAPHICAL splash early in boot, the virtio-gpu DRM
# (KMS) driver must be in the initramfs — otherwise the framebuffer isn't ready
# and the splash never shows (the likely reason it wasn't appearing in the
# Apple Virtualization guest). Force the modules in early.
mkdir -p /etc/initramfs-tools
if ! grep -q '^virtio_gpu' /etc/initramfs-tools/modules 2>/dev/null; then
    {
        echo "virtio_gpu"
        echo "virtio_pci"
        echo "drm"
    } >> /etc/initramfs-tools/modules
fi
# Tell Plymouth/KMS to bring up the framebuffer ASAP.
mkdir -p /etc/initramfs-tools/conf.d
echo "FRAMEBUFFER=y" > /etc/initramfs-tools/conf.d/totalvm-splash

# Make OUR theme the default. plymouth-set-default-theme alone wasn't winning
# over Ubuntu's bgrt/ubuntu-logo, so also force the update-alternatives link
# directly at a higher priority and pin it (manual mode). Logged so the build
# output shows what actually got set.
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
    plymouth-set-default-theme totalvm \
        || echo "[35-branding] WARNING: plymouth-set-default-theme totalvm failed" >&2
fi
if command -v update-alternatives >/dev/null 2>&1; then
    update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
        default.plymouth /usr/share/plymouth/themes/totalvm/totalvm.plymouth 200 || true
    update-alternatives --set default.plymouth \
        /usr/share/plymouth/themes/totalvm/totalvm.plymouth || true
fi
echo "[35-branding] plymouth default theme -> $(readlink -f /etc/alternatives/default.plymouth 2>/dev/null || echo unknown)"

if [ -f /etc/default/grub ]; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash net.ifnames=0"/' /etc/default/grub
    grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub \
        || echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash net.ifnames=0"' >> /etc/default/grub
fi

# The cloud image ships /etc/default/grub.d/50-cloudimg-settings.cfg which sets
# a verbose SERIAL-console cmdline (console=ttyS0...) and OVERRIDES the line
# above — that's why boot is verbose and the splash never starts (no "splash"
# kernel arg). A 99-* snippet is sourced LAST, so it wins: clean graphical
# boot + Plymouth. net.ifnames=0 also pins the NIC name to eth0 so the network
# config and conky always target the right interface.
mkdir -p /etc/default/grub.d
cat > /etc/default/grub.d/99-totalvm.cfg <<'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash net.ifnames=0"
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
# Normal boots stay instant. If the previous kernel never reached userspace,
# GRUB exposes the retained, known-good kernel on the next start instead of
# repeatedly selecting a broken update with no recovery path.
GRUB_RECORDFAIL_TIMEOUT=5
EOF
update-grub || true

update-initramfs -u || true

echo "[35-branding] done"
