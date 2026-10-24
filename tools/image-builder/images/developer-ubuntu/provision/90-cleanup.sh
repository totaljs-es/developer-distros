#!/usr/bin/env bash
# Step 90 — cleanup: shrink the image and reset cloud-init so the published
# image boots as a fresh instance on the user's Mac.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Publishing safety invariant: sparse installed RAWs must never continuously
# discard through Virtualization.framework. Reassert this after every package
# and cloud-init step in case one rewrote fstab during provisioning.
sed -i -E 's/(^|[[:space:],])discard,?/\1/g; s/,,+/,/g' /etc/fstab

# --- Networking: hand eth0 to NetworkManager in the FINAL image ------------
# During the build the guest is on systemd-networkd (set up by cloud-init), but
# the desktop installs NetworkManager too — the two fight over eth0, leaving
# it with no usable address (conky "No Address", TotalFetch shows the docker
# bridge IP). Done here (last step) so the build's own network keeps working;
# it only changes the image the user boots. NetworkManager auto-DHCPs the NIC
# and nm-applet then works in the tray.
printf 'network: {config: disabled}\n' > /etc/cloud/cloud.cfg.d/99-totalvm-disable-net.cfg
rm -f /etc/systemd/network/10-totalvm.network
rm -f /etc/netplan/50-cloud-init.yaml
cat > /etc/netplan/01-totalvm-network.yaml <<'EOF'
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    totaljs-wired:
      match:
        name: "e*"
      dhcp4: true
      dhcp6: false
      optional: true
EOF
chmod 600 /etc/netplan/01-totalvm-network.yaml
# The server cloud image ships NetworkManager with managed=false (it defers to
# networkd), so NM leaves eth0 "unmanaged" and nothing brings it up. Force NM to
# manage every device — that's what Ubuntu Desktop does.
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/10-totalvm-managed.conf <<'EOF'
[keyfile]
unmanaged-devices=none
EOF
sed -i 's/^managed=false/managed=true/' /etc/NetworkManager/NetworkManager.conf 2>/dev/null || true
systemctl enable NetworkManager >/dev/null 2>&1 || true
netplan generate || true
# The bootstrap may temporarily point resolv.conf straight at Apple's NAT DNS
# when networkd/resolved races on the cloud image's first boot. Restore the
# normal resolved stub before publishing; NetworkManager supplies its DNS on
# every user boot.
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# networkd is no longer the manager (NetworkManager is), so its wait-online unit
# would block network-online.target for the FULL timeout (~52s of "Job
# systemd-networkd-wait-online.service/start running") waiting for an interface
# it will never configure — that's the slow boot the user saw. Disable networkd
# and mask its wait-online; NetworkManager-wait-online.service reaches
# network-online.target instead (and is already enabled with NM).
systemctl disable systemd-networkd.service systemd-networkd.socket >/dev/null 2>&1 || true
systemctl mask systemd-networkd-wait-online.service >/dev/null 2>&1 || true
systemctl enable NetworkManager-wait-online.service >/dev/null 2>&1 || true

# cloud-init masks the build console so provisioning owns hvc0 exclusively.
# That seed is not present on user boots, but the /dev/null unit links it wrote
# are persistent; restore the console before publishing the image so recovery
# and update diagnostics remain possible even if the graphical session fails.
systemctl unmask serial-getty@hvc0.service getty@hvc0.service >/dev/null 2>&1 || true
systemctl enable serial-getty@hvc0.service >/dev/null 2>&1 || true

# Apple Virtualization's requestStop() is an ACPI power-button event. Desktop
# power managers may otherwise inhibit it, leaving TotalVM waiting forever when
# the user closes the app. Let logind always own this event and power off cleanly.
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

# Mask units that are pointless inside an Apple Virtualization guest — they only
# add boot time and log noise (no modems, no iSCSI/multipath storage, no LXD).
systemctl mask \
    ModemManager.service \
    iscsid.service iscsid.socket open-iscsi.service \
    multipathd.service multipathd.socket \
    lxd-installer.socket \
    >/dev/null 2>&1 || true

# Move the baked environment to a seed template so /www can become the mount
# point for the host-shared folder (see 00-base totalvm-www-seed). Nothing has
# /www bind-mounted at this point (the Code/Postgres stacks are only pre-pulled
# during the build, never `up`), so the move is safe.
if [ -e /www/code ] && [ ! -d /var/lib/totalvm/www-seed ]; then
    mkdir -p /var/lib/totalvm
    mv /www /var/lib/totalvm/www-seed
    mkdir -p /www
    chown totaljs:totaljs /www
fi

# Drop caches and package lists.
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/* /var/tmp/*
find /var/log -type f -exec truncate -s 0 {} + || true

# Reset cloud-init so first boot on the user's machine re-runs as a new instance
# (regenerates machine-id, SSH host keys, etc.).
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
    # Zero free space so packaged images compress well, but keep enough room for
    # systemd, journald, unmount and shutdown to finish reliably. Filling the
    # filesystem to 100% made those final operations fail after provisioning.
    echo "[90-cleanup] zeroing free space (improves compression)…"
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
