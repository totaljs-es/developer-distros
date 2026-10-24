#!/usr/bin/env bash
# Step 20 (Arch) — Docker Engine + Compose.
set -euo pipefail
pac -S --noconfirm --needed docker docker-compose
groupadd -f docker
usermod -aG docker totaljs
systemctl enable docker.service
echo "[20-services] done"
