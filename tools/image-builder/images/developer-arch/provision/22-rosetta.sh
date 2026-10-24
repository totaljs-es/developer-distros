#!/usr/bin/env bash
# Step 22 - Apple Rosetta support for Intel Linux binaries.
set -euo pipefail

bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/rosetta-support.sh"
