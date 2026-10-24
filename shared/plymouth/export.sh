#!/usr/bin/env bash
# export.sh - makes the images of the boot splash (totaljs/*.png) from the official logo.
#
#   shared/plymouth/export.sh
#
# It needs Python 3 and Inkscape. The images are small on purpose: they go into the initramfs.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
command -v inkscape >/dev/null || { echo "inkscape is required (brew install --cask inkscape)" >&2; exit 1; }

python3 "${HERE}/generate.py" "${HERE}/svg" >/dev/null
rm -rf "${HERE}/__pycache__" "${HERE}/../wallpapers/__pycache__"

png() {   # png <name> <size>
    inkscape --export-type=png --export-width="$2" --export-height="$2" --export-filename="${HERE}/totaljs/$1.png" "${HERE}/svg/$1.svg" >/dev/null 2>&1
    [ -s "${HERE}/totaljs/$1.png" ] || { echo "inkscape did not make $1" >&2; exit 1; }
}

for name in body side arrow logo; do png "${name}" 1024; done
png glow 512
for name in dot-off dot-on; do png "${name}" 32; done

ls -l "${HERE}"/totaljs/*.png | awk '{ printf "%7.1f KB  %s\n", $5 / 1024, $NF }'
