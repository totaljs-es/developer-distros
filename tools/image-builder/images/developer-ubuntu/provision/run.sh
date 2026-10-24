#!/usr/bin/env bash
# TotalVM provisioning entrypoint — runs inside the guest, invoked by cloud-init.
# Executes every numbered step in order. Any failure aborts the build so a
# broken image is never packaged.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export TOTALVM_ASSETS="${TOTALVM_ASSETS:-/mnt/assets}"

# needrestart pops up an interactive whiptail dialog after some apt installs
# ("which services should be restarted?") regardless of DEBIAN_FRONTEND —
# it has its own frontend setting. Left alone it hangs the build forever with
# no error printed. Force it fully automatic.
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

cd "$(dirname "$0")"

STATE_DIR=/var/lib/totaljs-image-build
install -d "${STATE_DIR}"

echo "================ TotalVM provisioning starting ================"
date -u

for step in $(ls -1 [0-9][0-9]-*.sh | sort); do
    marker="${STATE_DIR}/${step}.done"
    if [ -f "${marker}" ]; then
        echo "########## TotalVM step: ${step} (already complete) ##########"
        continue
    fi

    echo
    echo "########## TotalVM step: ${step} ##########"
    bash "./${step}"
    touch "${marker}"

    # Docker image extraction leaves containerd, dockerd and systemd under a
    # burst of I/O and memory pressure. Resume desktop/package provisioning from
    # a clean HWE boot; completed-step markers prevent every pull from repeating.
    if [ "${step}" = "25-code-docker.sh" ] && [ ! -f "${STATE_DIR}/post-docker-rebooted" ]; then
        touch "${STATE_DIR}/post-docker-rebooted"
        echo "Rebooting once after Docker image provisioning..."
        systemctl reboot --no-block
        trap 'exit 1' TERM INT
        while :; do sleep 5; done
    fi

done

echo
echo "================ TotalVM provisioning complete ================"
date -u
