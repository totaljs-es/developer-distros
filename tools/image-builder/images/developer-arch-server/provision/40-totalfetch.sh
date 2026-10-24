#!/usr/bin/env bash
# Step 40 (Arch Server) - branded CLI system summary.
set -euo pipefail

bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/totalfetch-server.sh"
