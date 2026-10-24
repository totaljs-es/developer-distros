#!/usr/bin/env bash
# Step 90 (Arch) — publishable-image cleanup and reliable ACPI shutdown.
set -euo pipefail

# Sparse installed RAWs must never continuously discard through the host.
sed -i -E 's/(^|[[:space:],])discard,?/\1/g; s/,,+/,/g' /etc/fstab
if ! awk '$2 == "/" && $4 ~ /(^|,)nodiscard(,|$)/ { found=1 } END { exit !found }' /etc/fstab; then
    sed -i -E '/[[:space:]]\/[[:space:]]+ext4[[:space:]]/ s/(defaults|noatime)(,|[[:space:]])/\1,nodiscard\2/' /etc/fstab
fi

systemctl disable systemd-networkd.service systemd-networkd.socket >/dev/null 2>&1 || true
systemctl enable NetworkManager.service NetworkManager-wait-online.service >/dev/null 2>&1 || true

# Never publish the well-known bootstrap credentials inherited from the generic
# Arch Linux ARM rootfs. The console first-run wizard replaces this discarded
# random password with the developer's choice.
if id alarm >/dev/null 2>&1; then
    userdel -r alarm >/dev/null 2>&1 || usermod -L -s /usr/bin/nologin alarm
fi
if id totaljs >/dev/null 2>&1; then
    TEMP_PASSWORD="$(cat /proc/sys/kernel/random/uuid)$(cat /proc/sys/kernel/random/uuid)"
    echo "totaljs:${TEMP_PASSWORD}" | chpasswd
    unset TEMP_PASSWORD
fi
passwd -l root >/dev/null 2>&1 || true

mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-totaljs-developer-power.conf <<'EOF'
[Login]
HandlePowerKey=poweroff
PowerKeyIgnoreInhibited=yes
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
EOF

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true

if [ -e /www/code ] && [ ! -d /var/lib/totalvm/www-seed ]; then
    mkdir -p /var/lib/totalvm
    mv /www /var/lib/totalvm/www-seed
    mkdir -p /www
    chown totaljs:totaljs /www
fi

pacman -Scc --noconfirm || true
rm -rf /tmp/* /var/tmp/*
find /var/log -type f -exec truncate -s 0 {} + || true
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id /etc/ssh/ssh_host_*
if [ ! -f "$(dirname "$0")/skip-zero" ]; then
    echo "[90-cleanup] zeroing free space while reserving shutdown headroom"
    AVAILABLE_KB="$(df --output=avail / | tail -n 1 | tr -d ' ')"
    RESERVE_KB=$((512 * 1024))
    if [ "${AVAILABLE_KB}" -gt "${RESERVE_KB}" ]; then
        ZERO_MB=$(((AVAILABLE_KB - RESERVE_KB) / 1024))
        dd if=/dev/zero of=/ZERO bs=1M count="${ZERO_MB}" status=none
    fi
    rm -f /ZERO
    sync
fi
echo "[90-cleanup] done"
