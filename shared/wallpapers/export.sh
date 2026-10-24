#!/usr/bin/env bash
# export.sh - makes the wallpapers: the SVGs (svg/) from generate.py and the images at 4K (4k/*.jpg) from them.
#
#   shared/wallpapers/export.sh [width]       # 3840 by default (16:9)
#
# It needs Python 3, Inkscape and a way to make JPEG: `sips` (macOS) or ImageMagick (`magick` or `convert`).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WIDTH="${1:-3840}"
QUALITY="${JPEG_QUALITY:-90}"
OUT="${HERE}/${WIDTH}"
[ "${WIDTH}" != 3840 ] || OUT="${HERE}/4k"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
command -v python3 >/dev/null || die "python3 is required"
command -v inkscape >/dev/null || die "inkscape is required (brew install --cask inkscape)"

jpeg() {   # jpeg <png> <jpg>
    if command -v sips >/dev/null; then sips -s format jpeg -s formatOptions "${QUALITY}" "$1" --out "$2" >/dev/null
    elif command -v magick >/dev/null; then magick "$1" -background '#000000' -alpha remove -quality "${QUALITY}" "$2"
    elif command -v convert >/dev/null; then convert "$1" -background '#000000' -alpha remove -quality "${QUALITY}" "$2"
    else die "sips or ImageMagick is required to make the JPEG"
    fi
}

python3 "${HERE}/generate.py" "${HERE}/svg" >/dev/null
mkdir -p "${OUT}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

for svg in "${HERE}"/svg/*.svg; do
    name="$(basename "${svg}" .svg)"
    echo "==> ${name}"
    inkscape --export-type=png --export-width="${WIDTH}" --export-filename="${TMP}/${name}.png" "${svg}" >/dev/null 2>&1
    [ -s "${TMP}/${name}.png" ] || die "inkscape did not make ${name}"
    jpeg "${TMP}/${name}.png" "${OUT}/${name}.jpg"
    ls -l "${OUT}/${name}.jpg" | awk '{ printf "    %.0f KB\n", $5 / 1024 }'
done
