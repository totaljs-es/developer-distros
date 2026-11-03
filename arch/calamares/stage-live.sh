#!/usr/bin/env bash
# Stage only files: pacman's post-transaction hook configures the live rootfs.
set -euo pipefail
RFS="${1:?usage: stage-live.sh <live-rootfs> <amd64|arm64>}"
ARCH="${2:?usage: stage-live.sh <live-rootfs> <amd64|arm64>}"
case "${ARCH}" in amd64|arm64) ;; *) echo 'Unsupported architecture' >&2; exit 1 ;; esac
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RFS="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "${RFS}")"
[ "${RFS}" != / ] || { echo 'Refusing to stage into the host root' >&2; exit 1; }
SOURCE="${RFS}/usr/share/totaljs-live/source"
[ ! -e "${SOURCE}" ] || { echo 'Live sources already staged' >&2; exit 1; }
mkdir -p "${SOURCE}/shared" "${SOURCE}/docs/images" "${RFS}/etc/pacman.d/hooks" "${RFS}/usr/lib/totaljs-live"
cp -R "${ROOT}/shared/calamares" "${ROOT}/shared/branding" "${SOURCE}/shared/"
cp "${ROOT}/docs/images/desktop.jpg" "${ROOT}/docs/images/terminal.jpg" "${SOURCE}/docs/images/"
cat > "${RFS}/usr/lib/totaljs-live/configure-installer" <<CONFIGURE
#!/usr/bin/env bash
set -euo pipefail
TOTALJS_LIVE_BUILD=1 bash /usr/share/totaljs-live/source/shared/calamares/setup-live.sh arch ${ARCH}
CONFIGURE
chmod 0755 "${RFS}/usr/lib/totaljs-live/configure-installer"
cat > "${RFS}/etc/pacman.d/hooks/99-totaljs-live-installer.hook" <<'HOOK'
[Trigger]
Operation = Install
Type = Package
Target = calamares
[Action]
Description = Configure the shared Total.js live installer
When = PostTransaction
Exec = /usr/lib/totaljs-live/configure-installer
HOOK
