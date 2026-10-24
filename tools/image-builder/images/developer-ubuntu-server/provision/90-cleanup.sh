#!/usr/bin/env bash
# Step 90 - cleanup for the headless server image.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

sed -i -E 's/(^|[[:space:],])discard,?/\1/g; s/,,+/,/g' /etc/fstab

printf 'network: {config: disabled}\n' > /etc/cloud/cloud.cfg.d/99-totalvm-disable-net.cfg
rm -f /etc/netplan/50-cloud-init.yaml
cat > /etc/netplan/01-totalvm-server.yaml <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    totaljs-wired:
      match:
        name: "e*"
      dhcp4: true
      dhcp6: false
      optional: true
EOF
chmod 600 /etc/netplan/01-totalvm-server.yaml
netplan generate || true

systemctl disable serial-getty@hvc0.service getty@hvc0.service >/dev/null 2>&1 || true
systemctl mask serial-getty@hvc0.service getty@hvc0.service >/dev/null 2>&1 || true
systemctl enable getty@tty1.service >/dev/null 2>&1 || true
systemctl enable systemd-networkd systemd-resolved systemd-networkd-wait-online.service >/dev/null 2>&1 || true
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/10-totaljs-server-power.conf <<'EOF'
[Login]
HandlePowerKey=poweroff
PowerKeyIgnoreInhibited=yes
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
IdleAction=ignore
EOF

systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
systemctl mask \
    ModemManager.service \
    iscsid.service iscsid.socket open-iscsi.service \
    multipathd.service multipathd.socket \
    lxd-installer.socket \
    >/dev/null 2>&1 || true

if [ -e /www/code ] && [ ! -d /var/lib/totalvm/www-seed ]; then
    mkdir -p /var/lib/totalvm
    mv /www /var/lib/totalvm/www-seed
    mkdir -p /www
    chown totaljs:totaljs /www
fi

apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/* /var/tmp/*
find /var/log -type f -exec truncate -s 0 {} + || true

cloud-init clean --logs --seed || true
truncate -s 0 /etc/machine-id || true
rm -f /var/lib/dbus/machine-id || true
rm -f /etc/ssh/ssh_host_* || true

rm -f /ZERO
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "${SCRIPT_DIR}/skip-zero" ] \
    || [ -f "${TOTALVM_ASSETS:-/mnt/assets}/SKIP_ZERO" ] \
    || [ -f /mnt/totalvm-seed/SKIP_ZERO ]; then
    echo "[90-cleanup] raw-only build: skipping free-space zeroing"
else
    echo "[90-cleanup] zeroing free space (improves compression)..."
    AVAILABLE_KB="$(df --output=avail / | tail -n 1 | tr -d ' ')"
    RESERVE_KB=$((384 * 1024))
    if [ "${AVAILABLE_KB}" -gt "${RESERVE_KB}" ]; then
        ZERO_MB=$(((AVAILABLE_KB - RESERVE_KB) / 1024))
        dd if=/dev/zero of=/ZERO bs=1M count="${ZERO_MB}" status=none
    fi
    rm -f /ZERO
    sync
fi

echo "[90-cleanup] done"
