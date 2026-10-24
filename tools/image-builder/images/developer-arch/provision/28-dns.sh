#!/usr/bin/env bash
# Step 28 (Arch) — wildcard DNS, shared with Ubuntu.
set -euo pipefail
pac -S --noconfirm --needed dnsmasq
systemctl enable systemd-resolved.service
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/dns-core.sh"
