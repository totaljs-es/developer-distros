#!/usr/bin/env bash
# Step 20 - keep the headless login clean; projects are managed from Code.
set -euo pipefail

rm -f /usr/local/bin/totalctl
truncate -s 0 /etc/motd
rm -f /etc/legal /run/motd.dynamic
if [ -d /etc/update-motd.d ]; then
    chmod -x /etc/update-motd.d/* 2>/dev/null || true
fi

echo "[20-login-cleanup] done"
