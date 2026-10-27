#!/usr/bin/env bash
# Shared helpers for the TotalVM image build scripts.
set -euo pipefail

# Repository layout (relative to this file).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK_DIR="${TOTALVM_WORK_DIR:-${BUILDER_DIR}/build/work}"
CACHE_DIR="${TOTALVM_CACHE_DIR:-${BUILDER_DIR}/build/cache}"
DIST_DIR="${TOTALVM_DIST_DIR:-${BUILDER_DIR}/dist}"
RUNNER_BIN="${BUILDER_DIR}/.build/release/totalvm-builder"
MENU_ICON_SOURCE="${BUILDER_DIR}/../package-repo/icons"

log()  { printf '\033[38;5;39m[totalvm]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[totalvm]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[totalvm] error:\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing required tool '$1'${2:+ ($2)}"
}

# Read a value from an image.json with jq.
image_get() { jq -r "$2" "$1"; }

# Copy the Openbox artwork from its canonical package-repository source into
# the assets presented to the guest. This keeps image builds independent from
# whichever (possibly older) totaljs-desktop package happens to be cached.
stage_menu_icons() {
    local destination="$1" icon
    local icons="applications browser developer launcher logout preferences projects restart services shutdown terminal total-center totaljs"

    [ -d "${MENU_ICON_SOURCE}" ] \
        || die "missing Openbox icon source: ${MENU_ICON_SOURCE}"
    mkdir -p "${destination}/menu-icons"
    for icon in ${icons}; do
        [ -f "${MENU_ICON_SOURCE}/${icon}.svg" ] \
            || die "missing Openbox icon: ${MENU_ICON_SOURCE}/${icon}.svg"
        cp "${MENU_ICON_SOURCE}/${icon}.svg" "${destination}/menu-icons/${icon}.svg"
    done
    log "staged Openbox menu icons from tools/package-repo/icons"
}

# Build + ad-hoc-sign the Swift VM runner with the virtualization entitlement.
build_runner() {
    log "building totalvm-builder (Swift)…"
    ( cd "${BUILDER_DIR}" && swift build -c release )
    log "code-signing with virtualization entitlement…"
    codesign --force --sign - \
        --entitlements "${BUILDER_DIR}/totalvm-builder.entitlements" \
        "${RUNNER_BIN}"
}

# The same official welcome artwork for both first-run wizards.
stage_toto() {
    local source="${BUILDER_DIR}/../../shared/branding/toto" destination="$1"
    mkdir -p "${destination}/wizard"
    cp "${source}/toto-welcome.png" "${destination}/wizard/toto-welcome.png"
    cp "${source}/LICENSE.md" "${destination}/wizard/TOTO-LICENSE.md"
}
