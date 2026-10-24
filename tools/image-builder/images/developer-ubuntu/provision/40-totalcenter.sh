#!/usr/bin/env bash
# Step 40 (Ubuntu) — Total.js Center dashboard. Distro-agnostic; shared body.
set -euo pipefail
bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/totalcenter.sh"
