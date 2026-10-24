#!/usr/bin/env bash
# Step 25 (Ubuntu) — Code + nginx-proxy + Postgres/pgAdmin. Distro-agnostic; shared body.
set -euo pipefail
bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/code-docker.sh"
