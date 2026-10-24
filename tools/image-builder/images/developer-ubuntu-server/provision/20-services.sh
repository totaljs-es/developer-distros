#!/usr/bin/env bash
# Step 20 — Docker runtime. Developer services live in Compose so users can
# change versions or remove them without modifying the Ubuntu base system.
# The reverse proxy for *.total domains is the dockerized nginx-proxy started
# in 25-code-docker.sh (it owns port 80 and routes by VIRTUAL_HOST), so no
# standalone nginx package is installed here anymore.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# --- Docker CE + Compose plugin -------------------------------------------
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

groupadd -f docker
usermod -aG docker totaljs
systemctl enable docker

echo "[20-services] done"
