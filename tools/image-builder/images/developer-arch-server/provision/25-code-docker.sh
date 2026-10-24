#!/usr/bin/env bash
# Step 25 (Arch) — Code + nginx-proxy + Postgres/pgAdmin stacks. Distro-agnostic;
# shared body (writes docker-compose files + systemd units). Docker comes from 20.
set -euo pipefail
bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/code-docker.sh"
