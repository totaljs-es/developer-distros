#!/usr/bin/env bash
# Step 35 (Arch) — shared Plymouth theme + systemd-boot configuration.
# The splash is cosmetic, so the whole Plymouth wiring is best-effort: a failure
# here must never abort the build (and now actually would, since the provision
# runner reports failures correctly).
set -euo pipefail

prepare_mkinitcpio() {
    [ -f /etc/mkinitcpio.conf ] || return 0
    if grep -q '^MODULES=' /etc/mkinitcpio.conf; then
        grep -q 'virtio_gpu' /etc/mkinitcpio.conf \
            || sed -i 's/^MODULES=(/MODULES=(virtio_gpu virtio_pci /' /etc/mkinitcpio.conf
    else
        echo 'MODULES=(virtio_gpu virtio_pci)' >> /etc/mkinitcpio.conf
    fi
    # AArch64 has no x86 CPU microcode image, and this fixed virtual display
    # needs only virtio_gpu rather than the KMS hook's full physical-GPU scan.
    sed -Ei '/^HOOKS=/ {
        s/[[:space:]]+microcode([[:space:]])/\1/
        s/[[:space:]]+kms([[:space:]])/\1/
    }' /etc/mkinitcpio.conf
}

# Do this before installing Plymouth: its package transaction can regenerate
# the initramfs immediately.
prepare_mkinitcpio
pac -S --noconfirm --needed plymouth imagemagick
export TOTALVM_SPLASH_TITLE="Total.js Developer Distro"
export TOTALVM_SPLASH_SUBTITLE="Server Edition"
bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/plymouth-theme.sh"

setup_plymouth() {
    set -e
    # Activate our theme so mkinitcpio bundles it into the initramfs.
    plymouth-set-default-theme totalvm

    if [ -f /etc/mkinitcpio.conf ]; then
        # Reassert the fixed virtual-GPU configuration before the final image.
        prepare_mkinitcpio
        # Hook names vary between Plymouth packages. Select a hook that actually
        # exists instead of assuming sd-plymouth (Arch Linux ARM currently ships
        # the regular `plymouth` hook even with a systemd initramfs).
        PLYMOUTH_HOOK=""
        for candidate in sd-plymouth plymouth; do
            if [ -f "/usr/lib/initcpio/install/${candidate}" ]; then
                PLYMOUTH_HOOK="${candidate}"
                break
            fi
        done
        [ -n "${PLYMOUTH_HOOK}" ] || {
            echo "No mkinitcpio Plymouth hook was installed" >&2
            return 1
        }

        if ! grep -qE "^HOOKS=.*\\b${PLYMOUTH_HOOK}\\b" /etc/mkinitcpio.conf; then
            if grep -qE '^HOOKS=.*\bsystemd\b' /etc/mkinitcpio.conf; then
                sed -i "s/\\bsystemd\\b/systemd ${PLYMOUTH_HOOK}/" /etc/mkinitcpio.conf
            else
                sed -i "s/\\budev\\b/udev ${PLYMOUTH_HOOK}/" /etc/mkinitcpio.conf
            fi
        fi
        mkinitcpio -P
    fi
}
setup_plymouth

# Kernel cmdline: drop the serial-only console and ask for a quiet graphical boot
# so Plymouth can paint on the virtio-gpu framebuffer.
for entry in /boot/loader/entries/*.conf; do
    [ -f "${entry}" ] || continue
    sed -i 's/ console=hvc0//' "${entry}"
    grep -q ' quiet splash' "${entry}" || sed -i '/^options /s/$/ quiet splash net.ifnames=0/' "${entry}"
done
systemctl disable serial-getty@hvc0.service getty@hvc0.service >/dev/null 2>&1 || true
systemctl mask serial-getty@hvc0.service getty@hvc0.service >/dev/null 2>&1 || true
systemctl enable getty@tty1.service >/dev/null 2>&1 || true
echo "[35-branding] done"
