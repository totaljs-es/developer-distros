#!/usr/bin/env bash
# Step 20 - keep the headless login clean; projects are managed from Code.
set -euo pipefail

rm -f /usr/local/bin/totalctl
truncate -s 0 /etc/motd

echo "[20-login-cleanup] done"
