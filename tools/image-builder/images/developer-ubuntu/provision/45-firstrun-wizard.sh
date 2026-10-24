#!/usr/bin/env bash
# Step 45 (Ubuntu) — first-run wizard. Install GTK3/PyGObject, then shared install.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends \
    python3-gi gir1.2-gtk-3.0 gir1.2-gdkpixbuf-2.0 locales
bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/wizard-install.sh"
