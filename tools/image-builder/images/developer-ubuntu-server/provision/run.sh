#!/usr/bin/env bash
# TotalVM Server provisioning entrypoint.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export TOTALVM_ASSETS="${TOTALVM_ASSETS:-/mnt/assets}"
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

cd "$(dirname "$0")"

STATE_DIR=/var/lib/totaljs-image-build
install -d "${STATE_DIR}"

echo "================ TotalVM Server provisioning starting ================"
date -u

for step in $(ls -1 [0-9][0-9]-*.sh | sort); do
    marker="${STATE_DIR}/${step}.done"
    if [ -f "${marker}" ]; then
        echo "########## TotalVM Server step: ${step} (already complete) ##########"
        continue
    fi

    echo
    echo "########## TotalVM Server step: ${step} ##########"
    bash "./${step}"
    touch "${marker}"

    if [ "${step}" = "25-code-docker.sh" ] && [ ! -f "${STATE_DIR}/post-docker-rebooted" ]; then
        touch "${STATE_DIR}/post-docker-rebooted"
        echo "Rebooting once after Docker image provisioning..."
        systemctl reboot --no-block
        trap 'exit 1' TERM INT
        while :; do sleep 5; done
    fi
done

echo
echo "================ TotalVM Server provisioning complete ================"
date -u
