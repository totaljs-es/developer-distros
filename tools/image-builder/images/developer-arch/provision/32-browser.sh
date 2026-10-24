#!/usr/bin/env bash
# Step 32 (Arch) - native Firefox ARM64 from the Arch Linux ARM repository.
set -euo pipefail

pac -S --noconfirm --needed firefox

BIN=/usr/bin/firefox
DESKTOP=firefox.desktop
[ -x "${BIN}" ] || { echo "[32-browser] Firefox executable is missing" >&2; exit 1; }

sed -i '/^BROWSER=/d' /etc/environment
echo "BROWSER=${BIN}" >> /etc/environment
install -d /etc/xdg
cat > /etc/xdg/mimeapps.list <<EOF
[Default Applications]
text/html=${DESKTOP}
x-scheme-handler/http=${DESKTOP}
x-scheme-handler/https=${DESKTOP}
x-scheme-handler/about=${DESKTOP}
x-scheme-handler/unknown=${DESKTOP}
EOF

# Open Firefox on the local Total.js Center dashboard. Keep the setting unlocked
# so each developer can choose a different homepage later.
install -d /etc/firefox/policies
cat > /etc/firefox/policies/policies.json <<'EOF'
{
  "policies": {
    "DontCheckDefaultBrowser": true,
    "Homepage": {
      "URL": "http://totaljs.developer",
      "Locked": false,
      "StartPage": "homepage"
    }
  }
}
EOF

echo "[32-browser] Firefox installed (${BIN})"
