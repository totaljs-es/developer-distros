#!/usr/bin/env bash
# Step 45 (Arch) — GTK first-run wizard shared with Ubuntu.
set -euo pipefail
pac -S --noconfirm --needed python-gobject gtk3 gdk-pixbuf2 glib2
bash "${TOTALVM_ASSETS:-/mnt/assets}/provision/wizard-install.sh"
