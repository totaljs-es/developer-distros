#!/usr/bin/env bash
# Step 28 (Ubuntu) — wildcard DNS (dnsmasq). Install the package, then shared config.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends dnsmasq
bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/dns-core.sh"
