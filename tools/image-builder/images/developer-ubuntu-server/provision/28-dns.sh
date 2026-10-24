#!/usr/bin/env bash
# Step 28 (Ubuntu Server) - wildcard DNS for totaljs.developer.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends dnsmasq-base
systemctl enable systemd-resolved.service >/dev/null 2>&1 || true
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/dns-core.sh"
