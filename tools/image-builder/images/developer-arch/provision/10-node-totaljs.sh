#!/usr/bin/env bash
# Step 10 (Arch) — Node.js LTS + Total.js. Distro-agnostic; shared body (it
# installs Node from the official tarball, so no pacman package is needed).
set -euo pipefail
bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/node-totaljs.sh"
