#!/usr/bin/env bash
# Step 34 (Arch) — clipboard sync (copy & paste Mac ↔ VM).
# Pacman counterpart of the Ubuntu image's 34-clipboard.sh: the same vsock agent
# (shared asset) bridges the Linux clipboard with the Mac host's NSPasteboard;
# TotalVM.app listens on the vsock port and runs the host side.
set -euo pipefail

ASSETS="${TOTALVM_ASSETS:-/mnt/assets}"
USER_HOME=/home/totaljs

# xclip drives the X11 clipboard; python runs the agent. --needed is a no-op if
# the desktop step already pulled them in.
pac -S --noconfirm --needed xclip python || true

# Install the agent (same script as the Ubuntu image, shared via the assets mount).
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

echo "[34-clipboard] clipboard agent installed"
