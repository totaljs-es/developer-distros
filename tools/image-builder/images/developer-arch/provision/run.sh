#!/usr/bin/env bash
# Total.js Developer (Arch) provisioning entrypoint.
#
# The base system is installed automatically by build-arch.sh. This idempotent
# second stage layers the shared Total.js Developer experience on top.
set -euo pipefail

export TOTALVM_ASSETS="${TOTALVM_ASSETS:-/mnt/assets}"

if [ "$(id -u)" -ne 0 ]; then
    echo "run.sh must run as root (use: sudo bash run.sh)" >&2
    exit 1
fi

# Resilient pacman, inherited by every step (each runs as a child `bash`). The
# Arch Linux ARM mirror redirect is flaky — single files time out and a lagging
# mirror can 404 a package the freshly-synced DB still lists — so retry a few
# times, refreshing the DB each round (a retry often lands on a healthier
# mirror) and disabling the 10s per-file timeout.
pac() {
    local n=0
    until command pacman "$@" --disable-download-timeout; do
        n=$((n + 1))
        if [ "${n}" -ge 5 ]; then
            echo "[provision] pacman failed after ${n} attempts: $*" >&2
            return 1
        fi
        echo "[provision] pacman attempt ${n} failed; refreshing DB and retrying…" >&2
        sleep $((n * 5))
        command pacman -Syy --noconfirm --disable-download-timeout >/dev/null 2>&1 || true
    done
}
export -f pac

cd "$(dirname "$0")"

STATE_DIR=/var/lib/totaljs-image-build
install -d "${STATE_DIR}"

echo "================ TotalVM (Arch) provisioning starting ================"
date -u

for step in $(ls -1 [0-9][0-9]-*.sh 2>/dev/null | sort); do
    marker="${STATE_DIR}/${step}.done"
    if [ -f "${marker}" ]; then
        echo "########## TotalVM (Arch) step: ${step} (already complete) ##########"
        continue
    fi
    echo
    echo "########## TotalVM (Arch) step: ${step} ##########"
    bash "./${step}"
    touch "${marker}"

    # Docker occasionally cannot start reliably in the same boot in which its
    # runtime and kernel-facing components were installed. Resume provisioning
    # after one clean reboot so the service starts through normal systemd boot.
    if [ "${step}" = "20-services.sh" ] && [ ! -f "${STATE_DIR}/post-docker-install-rebooted" ]; then
        touch "${STATE_DIR}/post-docker-install-rebooted"
        echo "TOTALVM_PROV_REBOOT"
        systemctl reboot --no-block
        while :; do sleep 1; done
    fi
done

rm -rf "${STATE_DIR}"

echo
echo "================ TotalVM (Arch) provisioning complete ================"
date -u
