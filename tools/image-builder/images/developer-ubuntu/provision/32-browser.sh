#!/usr/bin/env bash
# Step 32 - native Firefox ARM64 from Mozilla's signed APT repository.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

KEYRING=/etc/apt/keyrings/packages.mozilla.org.asc
EXPECTED_FINGERPRINT=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3

install -d -m 0755 /etc/apt/keyrings
curl -fsSL --retry 5 https://packages.mozilla.org/apt/repo-signing-key.gpg \
    -o "${KEYRING}"
fingerprint="$(gpg --show-keys --with-colons "${KEYRING}" 2>/dev/null \
    | awk -F: '$1 == "fpr" { print $10; exit }')"
[ "${fingerprint}" = "${EXPECTED_FINGERPRINT}" ] || {
    echo "[32-browser] Mozilla repository key fingerprint mismatch" >&2
    exit 1
}

cat > /etc/apt/sources.list.d/mozilla.list <<EOF
deb [arch=arm64 signed-by=${KEYRING}] https://packages.mozilla.org/apt mozilla main
EOF
cat > /etc/apt/preferences.d/mozilla <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

installed=false
for attempt in 1 2 3; do
    if apt-get update && apt-get install -y --no-install-recommends firefox; then
        installed=true
        break
    fi
    echo "[32-browser] Firefox install failed (${attempt}/3); retrying" >&2
    sleep $((attempt * 5))
done
${installed} || { echo "[32-browser] Firefox is required; aborting the image build" >&2; exit 1; }

BIN=/usr/bin/firefox
DESKTOP=firefox.desktop
[ -x "${BIN}" ] || { echo "[32-browser] Firefox executable is missing" >&2; exit 1; }

sed -i '/^BROWSER=/d' /etc/environment
echo "BROWSER=${BIN}" >> /etc/environment
update-alternatives --install /usr/bin/x-www-browser x-www-browser "${BIN}" 200 || true
update-alternatives --set x-www-browser "${BIN}" || true

install -d /etc/xdg
cat > /etc/xdg/mimeapps.list <<EOF
[Default Applications]
text/html=${DESKTOP}
application/xhtml+xml=${DESKTOP}
x-scheme-handler/http=${DESKTOP}
x-scheme-handler/https=${DESKTOP}
x-scheme-handler/about=${DESKTOP}
x-scheme-handler/unknown=${DESKTOP}
EOF

# Keep the system default and every user profile in agreement. A user-level
# mimeapps.list has higher precedence than /etc/xdg and is also what Firefox's
# first-start default-browser check expects in a lightweight Openbox session.
install -d /etc/skel/.config /home/totaljs/.config
install -m 0644 /etc/xdg/mimeapps.list /etc/skel/.config/mimeapps.list
install -m 0644 /etc/xdg/mimeapps.list /home/totaljs/.config/mimeapps.list
chown totaljs:totaljs /home/totaljs/.config/mimeapps.list

# Firefox is genuinely the system/user default above, so suppress its redundant
# first-start prompt with Mozilla's supported system-wide enterprise policy.
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

echo "[32-browser] Firefox installed from Mozilla (${BIN})"
