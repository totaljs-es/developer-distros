#!/usr/bin/env bash
# Total.js Developer — Node.js LTS + Total.js (shared, distro-agnostic).
set -euo pipefail

# Pinned official Node.js LTS binary. Avoid mutable repository setup scripts so
# rebuilding this image release always produces the same runtime.
NODE_VERSION="v24.18.0"
NODE_ARCHIVE="node-${NODE_VERSION}-linux-arm64.tar.xz"
NODE_SHA256="58c9520501f6ae2b52d5b210444e24b9d0c029a58c5011b797bc1fe7105886f6"
NODE_PREFIX="/opt/node-${NODE_VERSION}"

curl -fL --retry 5 --retry-delay 2 \
    -o "/tmp/${NODE_ARCHIVE}" "https://nodejs.org/dist/${NODE_VERSION}/${NODE_ARCHIVE}"
echo "${NODE_SHA256}  /tmp/${NODE_ARCHIVE}" | sha256sum -c -
rm -rf "${NODE_PREFIX}"
mkdir -p "${NODE_PREFIX}"
tar -xJf "/tmp/${NODE_ARCHIVE}" --strip-components=1 -C "${NODE_PREFIX}"
rm -f "/tmp/${NODE_ARCHIVE}"
ln -sf "${NODE_PREFIX}/bin/node" /usr/local/bin/node
ln -sf "${NODE_PREFIX}/bin/npm" /usr/local/bin/npm
ln -sf "${NODE_PREFIX}/bin/npx" /usr/local/bin/npx
ln -sf "${NODE_PREFIX}/bin/corepack" /usr/local/bin/corepack
# Also expose node at /usr/bin/node — systemd units and other tools often use
# that absolute path (e.g. totalcenter.service), and not every PATH includes
# /usr/local/bin.
ln -sf "${NODE_PREFIX}/bin/node" /usr/bin/node

npm config set prefix /usr/local

# Framework versions are part of this distro release, not floating channels.
npm install -g total5@0.0.17 total.js@3.4.13

# Record versions for TotalFetch (cached at build time so the terminal greeting
# never has to run a slow `npm ls`).
NPM_ROOT="$(npm root -g 2>/dev/null || echo /usr/lib/node_modules)"
TOTAL5_VERSION="$(node -e "try{process.stdout.write(require('${NPM_ROOT}/total5/package.json').version)}catch(e){process.stdout.write('unknown')}" 2>/dev/null || echo unknown)"
{
    echo "NODE_VERSION=\"$(node --version 2>/dev/null || echo unknown)\""
    echo "NPM_VERSION=\"$(npm --version 2>/dev/null || echo unknown)\""
    echo "TOTAL5_VERSION=\"${TOTAL5_VERSION}\""
} >> /etc/totalvm/release

echo "[10-node-totaljs] done"
