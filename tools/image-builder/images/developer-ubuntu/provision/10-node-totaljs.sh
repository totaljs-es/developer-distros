#!/usr/bin/env bash
# Step 10 (Ubuntu) — Node.js LTS + Total.js. Distro-agnostic; shared body.
set -euo pipefail
bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/node-totaljs.sh"
