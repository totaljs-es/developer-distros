#!/usr/bin/env bash
# test-install.sh - uses the repository the way a system does, inside a clean Ubuntu container (the CI runs it for each series).
#
#   docker run --rm -v "$PWD/build/site/repo:/repo:ro" -v "$PWD/tools/package-repo/test-install.sh:/test.sh:ro" ubuntu:24.04 bash /test.sh
#
# The repository has to be built with BASE_URL=file:///repo and signed with a throwaway key. It installs the server layer,
# checks what it promises, removes it and checks that nothing of it stays.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
# a container has no services to start
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
echo "==> ${CODENAME}: $(. /etc/os-release && echo "${PRETTY_NAME}")"

apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl gnupg xz-utils >/dev/null

# the first regular person of the system, as the installer would have made it (the image of Ubuntu already has one)
FIRST="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 { print $1; exit }')"
if [ -z "${FIRST}" ]; then useradd -m -u 1000 dev; FIRST=dev; fi
echo "the first person is ${FIRST}"

install -m 0644 /repo/totaljs-developer.gpg /usr/share/keyrings/totaljs-test.gpg
echo "deb [signed-by=/usr/share/keyrings/totaljs-test.gpg] file:///repo/ubuntu ${CODENAME} main" > /etc/apt/sources.list.d/totaljs-test.list
apt-get update -qq
POLICY="$(apt-cache policy totaljs-developer-server)"
case "${POLICY}" in *'Candidate: 1.0.0-1'*) ;; *) echo "${POLICY}" >&2; echo 'totaljs-developer-server 1.0.0-1 is not the candidate' >&2; exit 1 ;; esac

echo "==> installing totaljs-developer-server"
apt-get install -y totaljs-developer-server

. /usr/share/totaljs-node/versions
echo "==> the runtime"
test "$(node --version)" = "${NODE_VERSION}"
test "$(/usr/bin/node --version)" = "${NODE_VERSION}"
npm --version
test "$(npm ls -g --depth=0 --prefix /usr/local 2>/dev/null | grep -c -E 'total5@|total.js@')" = 2
node -e "require('/usr/local/lib/node_modules/total5/package.json')"

echo "==> the group and the first person"
getent group totaljs-developer
case " $(id -nG "${FIRST}") " in *' totaljs-developer '*) ;; *) echo "${FIRST} is not in totaljs-developer: $(id -nG "${FIRST}")" >&2; exit 1 ;; esac
test "$(cat /var/lib/totaljs-developer/first-user)" = "${FIRST}"
test -f /usr/lib/systemd/system/totaljs-developer-first-user.service

echo "==> the tools and the source that the release package wrote"
for tool in git curl jq tmux ufw fail2ban-client sshd; do command -v "${tool}" >/dev/null || [ -x "/usr/sbin/${tool}" ] || { echo "missing ${tool}" >&2; exit 1; }; done
grep -q "Suites: ${CODENAME}" /etc/apt/sources.list.d/totaljs-developer.sources || { cat /etc/apt/sources.list.d/totaljs-developer.sources >&2; exit 1; }

echo "==> the brand: the theme of the splash, and the settings of the boot"
test -f /usr/share/plymouth/themes/totaljs/totaljs.script
test -f /usr/share/plymouth/themes/totaljs/logo.png
test -f /usr/share/plymouth/themes/totaljs/totaljs.plymouth
grep -q '^Theme=totaljs$' /etc/plymouth/plymouthd.conf
ALTERNATIVE="$(update-alternatives --query default.plymouth)"
case "${ALTERNATIVE}" in *'Value: /usr/share/plymouth/themes/totaljs/totaljs.plymouth'*) ;; *) echo "${ALTERNATIVE}" >&2; echo 'default.plymouth is not the theme of Total.js' >&2; exit 1 ;; esac
grep -q 'quiet splash' /etc/default/grub.d/99-totaljs.cfg
dpkg -s plymouth-label >/dev/null

echo "==> the wallpapers (a package of its own: only the desktop needs them)"
apt-get install -y totaljs-wallpapers >/dev/null
test "$(ls /usr/share/backgrounds/totaljs/*.jpg | wc -l)" = 12
apt-get remove -y totaljs-wallpapers >/dev/null
test ! -e /usr/share/backgrounds/totaljs

echo "==> the source that the package wrote works by itself"
# the test source and the one of the package point to the same repository with different keys: apt refuses both at once
rm /etc/apt/sources.list.d/totaljs-test.list
apt-get update -qq
POLICY="$(apt-cache policy totaljs-node)"
case "${POLICY}" in *'Candidate: 1.0.0-1'*) ;; *) echo "${POLICY}" >&2; echo 'totaljs-node is not available from the source of the package' >&2; exit 1 ;; esac

echo "==> installing it again changes nothing"
apt-get install -y --reinstall totaljs-node >/dev/null
test "$(node --version)" = "${NODE_VERSION}"

echo "==> removing it"
apt-get remove -y totaljs-developer-server totaljs-brand totaljs-node >/dev/null
test ! -e /usr/local/bin/node
test ! -e /usr/bin/node
test ! -e "/opt/node-${NODE_VERSION}"
test ! -e /usr/local/lib/node_modules/total5
test ! -e /usr/share/plymouth/themes/totaljs
test ! -e /etc/default/grub.d/99-totaljs.cfg
REMAINING="$(update-alternatives --query default.plymouth 2>/dev/null || true)"
case "${REMAINING}" in *'themes/totaljs/totaljs.plymouth'*) echo 'the alternative of the theme is still there' >&2; exit 1 ;; esac
if grep -q '^Theme=totaljs$' /etc/plymouth/plymouthd.conf; then echo 'plymouthd.conf still names the theme' >&2; exit 1; fi

echo "OK ${CODENAME}"
