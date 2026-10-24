#!/usr/bin/env bash
# Step 45 - minimal console first-run setup.
set -euo pipefail

bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/server-console-wizard.sh"
