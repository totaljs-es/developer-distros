#!/usr/bin/env bash
# Step 34 — clipboard sync (copy & paste Mac ↔ VM).
# A tiny vsock agent bridges the Linux clipboard with the Mac host's
# NSPasteboard; TotalVM.app listens on the vsock port and runs the host side.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

ASSETS="${TOTALVM_ASSETS:-/mnt/assets}"
USER_HOME=/home/totaljs

# xclip drives the X11 clipboard; the agent itself is plain Python 3 (already
# present). Non-fatal if the repo hiccups — the desktop still works without sync.
apt-get install -y --no-install-recommends xclip || true

# Install the agent.
install -D -m 0755 "${ASSETS}/clipboard/totalvm-clipboard-agent.py" \
    /usr/local/bin/totalvm-clipboard-agent

# Launch it from the Openbox session (it needs DISPLAY/XAUTHORITY). Add the
# entry both to the bootstrap account and to /etc/skel: useradd creates the real
# first-run account from the skeleton before the wizard considers copying the
# bootstrap profile, so updating only /home/totaljs leaves new users without
# the clipboard agent.
for AUTOSTART in \
    "${USER_HOME}/.config/openbox/autostart" \
    /etc/skel/.config/openbox/autostart; do
    if [ -f "${AUTOSTART}" ] && ! grep -q "totalvm-clipboard-agent" "${AUTOSTART}"; then
        printf '# Clipboard sync with the Mac host (copy & paste both ways).\n%s\n' \
            '/usr/local/bin/totalvm-clipboard-agent &' >> "${AUTOSTART}"
    fi
done
[ ! -f "${USER_HOME}/.config/openbox/autostart" ] \
    || chown totaljs:totaljs "${USER_HOME}/.config/openbox/autostart"

echo "### TotalVM step 34: clipboard agent installed ###"
