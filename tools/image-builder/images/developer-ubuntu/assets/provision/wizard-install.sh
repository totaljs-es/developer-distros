#!/usr/bin/env bash
# Total.js Developer — install the first-run wizard files + sudoers (shared).
# The distro wrapper installs the GTK3/PyGObject packages before running this.
# Replaces the old terminal-prompt totaljs-first-run with a real desktop app.
set -euo pipefail

# GTK3 + the GdkPixbuf typelib (the wizard imports GdkPixbuf for the logo).
# gir1.2-gdkpixbuf-2.0 is listed explicitly: with --no-install-recommends it
# is NOT guaranteed to come in, and a missing namespace would crash the whole
# wizard at import time before any window appears.
WIZARD_SRC="${TOTALVM_ASSETS:-/mnt/assets}/wizard"
install -d /usr/local/share/totaljs-wizard

install -m 0755 "${WIZARD_SRC}/wizard.py" /usr/local/share/totaljs-wizard/wizard.py
install -m 0700 -o root -g root "${WIZARD_SRC}/totaljs-apply-firstrun.py" /usr/local/sbin/totaljs-apply-firstrun.py
install -m 0440 -o root -g root "${WIZARD_SRC}/90-totaljs-wizard" /etc/sudoers.d/90-totaljs-wizard
visudo -cf /etc/sudoers.d/90-totaljs-wizard
install -m 0644 "${WIZARD_SRC}/toto-welcome.png" /usr/local/share/totaljs-wizard/toto-welcome.png
install -m 0644 "${WIZARD_SRC}/TOTO-LICENSE.md" /usr/local/share/totaljs-wizard/TOTO-LICENSE.md

# Logo: take it straight from the shipped assets (don't depend on 35-branding,
# which may take a different code path and not stage it).
for logo in "${TOTALVM_ASSETS:-/mnt/assets}/totalvm.png" /usr/share/totalvm/totalvm.png; do
    if [ -f "${logo}" ]; then
        cp "${logo}" /usr/local/share/totaljs-wizard/logo.png
        break
    fi
done

# Thin launcher shim. Logs stderr so a wizard crash is visible (in
# ~/.cache/totaljs-wizard.log) instead of failing silently with no window.
cat > /usr/local/bin/totaljs-first-run <<'EOF'
#!/usr/bin/env bash
mkdir -p "${HOME}/.cache"
exec python3 /usr/local/share/totaljs-wizard/wizard.py \
    >"${HOME}/.cache/totaljs-wizard.log" 2>&1
EOF
chmod +x /usr/local/bin/totaljs-first-run
ln -sf /usr/local/bin/totaljs-first-run /usr/local/bin/totalvm-first-run

# Keep older image recipes compatible too: replace the obsolete terminal
# wrapper if an existing autostart file still contains it.
AUTOSTART=/home/totaljs/.config/openbox/autostart
if [ -f "${AUTOSTART}" ]; then
    sed -i "s#alacritty --class TotalJSSetup -e /usr/local/bin/totaljs-first-run &#/usr/local/bin/totaljs-first-run \&#" "${AUTOSTART}"
fi

echo "[45-firstrun-wizard] done"
