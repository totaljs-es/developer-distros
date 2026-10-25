#!/usr/bin/env bash
# test-install.sh - uses the repository the way a system does, inside a clean Ubuntu container (the CI runs it for each series).
#
#   docker run --rm -v "$PWD/build/site/repo:/repo:ro" -v "$PWD/tools/package-repo/test-install.sh:/test.sh:ro" ubuntu:26.04 bash /test.sh
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
apt-get install -y -qq --no-install-recommends ca-certificates curl gnupg xz-utils bind9-dnsutils >/dev/null

# the first regular person of the system, as the installer would have made it (the image of Ubuntu already has one)
FIRST="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 { print $1; exit }')"
if [ -z "${FIRST}" ]; then useradd -m -u 1000 dev; FIRST=dev; fi
echo "the first person is ${FIRST}"

install -m 0644 /repo/totaljs-developer.gpg /usr/share/keyrings/totaljs-test.gpg
echo "deb [signed-by=/usr/share/keyrings/totaljs-test.gpg] file:///repo/ubuntu ${CODENAME} main" > /etc/apt/sources.list.d/totaljs-test.list
apt-get update -qq
POLICY="$(apt-cache policy totaljs-developer-server)"
case "${POLICY}" in *'Candidate: 1.0.0-1'*) ;; *) echo "${POLICY}" >&2; echo 'totaljs-developer-server 1.0.0-1 is not the candidate' >&2; exit 1 ;; esac

# Two steps, as the installer does them: first the packages that configure the sources of apt (ours and Docker's), then, with the lists
# updated, the layer. Docker Engine comes from the repository of Docker, which apt has to know about before it resolves the layer.
echo "==> the sources: the release package and the source of Docker"
apt-get install -y totaljs-developer-release totaljs-docker-source
# the test source and the one of the package point to the same repository with different keys: apt refuses both at once
rm /etc/apt/sources.list.d/totaljs-test.list
apt-get update -qq
grep -q "Suites: ${CODENAME}" /etc/apt/sources.list.d/docker.sources || { cat /etc/apt/sources.list.d/docker.sources >&2; exit 1; }

echo "==> installing totaljs-developer-server"
apt-get install -y totaljs-developer-server

. /usr/share/totaljs-node/versions
echo "==> the runtime"
test "$(node --version)" = "${NODE_VERSION}"
test "$(/usr/bin/node --version)" = "${NODE_VERSION}"
npm --version
test "$(npm ls -g --depth=0 --prefix /usr/local 2>/dev/null | grep -c -E 'total4@|total5@')" = 2
node -e "require('/usr/local/lib/node_modules/total4/package.json'); require('/usr/local/lib/node_modules/total5/package.json')"

echo "==> the group and the first person"
getent group totaljs-developer
case " $(id -nG "${FIRST}") " in *' totaljs-developer '*) ;; *) echo "${FIRST} is not in totaljs-developer: $(id -nG "${FIRST}")" >&2; exit 1 ;; esac
test "$(cat /var/lib/totaljs-developer/first-user)" = "${FIRST}"
test -f /usr/lib/systemd/system/totaljs-developer-first-user.service

echo "==> the tools and the source that the release package wrote"
for tool in git curl jq tmux ufw fail2ban-client sshd; do command -v "${tool}" >/dev/null || [ -x "/usr/sbin/${tool}" ] || { echo "missing ${tool}" >&2; exit 1; }; done
grep -q "Suites: ${CODENAME}" /etc/apt/sources.list.d/totaljs-developer.sources || { cat /etc/apt/sources.list.d/totaljs-developer.sources >&2; exit 1; }

echo "==> the tools of a developer, the manager of versions of Node.js, the limits of the watchers"
for tool in psql sqlite3 gh rg fd bat fzf http nvim git-lfs fnm pnpm yarn; do command -v "${tool}" >/dev/null || { echo "missing ${tool}" >&2; exit 1; }; done
fnm --version | grep -q '^fnm 1\.'
grep -q 'totaljs-fnm' /etc/bash.bashrc
test "$(grep -c '^# >>> totaljs-fnm >>>$' /etc/bash.bashrc)" = 1
grep -q '^fs.inotify.max_user_watches = 524288$' /etc/sysctl.d/90-totaljs-developer.conf
# fnm installs another Node.js (it is the same program that a person runs), and the one of the system is still the default
FNM_DIR=/tmp/fnm-test fnm install 22 >/dev/null
test "$(FNM_DIR=/tmp/fnm-test fnm exec --using=22 node --version | cut -d. -f1)" = v22
test "$(node --version)" = "${NODE_VERSION}"

echo "==> the brand: the theme of the splash, and the settings of the boot"
test -f /usr/share/plymouth/themes/totaljs/totaljs.script
test -f /usr/share/plymouth/themes/totaljs/logo.png
test -f /usr/share/plymouth/themes/totaljs/totaljs.plymouth
grep -q '^Theme=totaljs$' /etc/plymouth/plymouthd.conf
ALTERNATIVE="$(update-alternatives --query default.plymouth)"
case "${ALTERNATIVE}" in *'Value: /usr/share/plymouth/themes/totaljs/totaljs.plymouth'*) ;; *) echo "${ALTERNATIVE}" >&2; echo 'default.plymouth is not the theme of Total.js' >&2; exit 1 ;; esac
grep -q 'quiet splash' /etc/default/grub.d/99-totaljs.cfg
dpkg -s plymouth-label >/dev/null

echo "==> Docker and the services"
docker --version
docker compose version
case " $(id -nG "${FIRST}") " in *' docker '*) ;; *) echo "${FIRST} is not in docker: $(id -nG "${FIRST}")" >&2; exit 1 ;; esac
for stack in proxy code flow services/postgres; do
    test -f "/www/${stack}/docker-compose.yml"
    docker compose -f "/www/${stack}/docker-compose.yml" config -q
done
test -f /www/proxy/totalcenter-gateway/default.conf
test "$(stat -c %a /www/services/postgres/.env)" = 640
grep -q -E '^PGADMIN_PASSWORD=[0-9a-f]{24}$' /www/services/postgres/.env
test "$(stat -c %G /www)" = totaljs-developer
for unit in totaljs-proxy totaljs-code totaljs-flow totaljs-postgres; do test -f "/usr/lib/systemd/system/${unit}.service"; done
# what the person edits is not overwritten, and what is missing comes back
echo '# edited' >> /www/proxy/docker-compose.yml
rm /www/flow/docker-compose.yml
/usr/lib/totaljs-developer/seed-www
grep -q '^# edited$' /www/proxy/docker-compose.yml
test -f /www/flow/docker-compose.yml

echo "==> the local domain"
test -f /etc/totaljs-developer/dns.conf
test -f /etc/systemd/resolved.conf.d/totaljs-developer.conf
test -f /usr/lib/systemd/system/totaljs-dns.service
/usr/sbin/dnsmasq --test --conf-file=/etc/totaljs-developer/dns.conf
# it answers: the domain, and any name under it, with this computer
/usr/sbin/dnsmasq --keep-in-foreground --conf-file=/etc/totaljs-developer/dns.conf --pid-file=/tmp/dns-test.pid --user=root >/tmp/dns-test.log 2>&1 &
DNS_PID=$!
sleep 1
test "$(dig +short +time=2 +tries=1 @127.0.0.100 code.totaljs.developer)" = 127.0.0.1
test -z "$(dig +short +time=2 +tries=1 @127.0.0.100 example.com)"
kill "${DNS_PID}" 2>/dev/null || true

echo "==> Total.js Center"
test -f /usr/lib/systemd/system/totaljs-center.service
test -f /usr/share/totaljs-developer/center/public/logo.svg
case " $(id -nG totalcenter) " in *' docker '*) echo 'totalcenter is in docker' >&2; exit 1 ;; esac   # it has no access to Docker
test -f /var/lib/totaljs-center/index.js
# the unit needs systemd, which a container does not have: run the same command as the same user
su -s /bin/sh totalcenter -c 'cd /var/lib/totaljs-center && NODE_ENV=production NODE_PATH=/usr/local/lib/node_modules exec node index.js' >/tmp/center.log 2>&1 &
CENTER_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fsS http://127.0.0.1:8010/health/ >/dev/null 2>&1 && break; sleep 1; done
# the output is kept first: grep -q closes the pipe before curl has written everything, and with pipefail that is an error
HEALTH="$(curl -fsS http://127.0.0.1:8010/health/ || { cat /tmp/center.log >&2; exit 1; })"
case "${HEALTH}" in *'"ok":true'*) ;; *) echo "${HEALTH}" >&2; exit 1 ;; esac
PAGE="$(curl -fsS http://127.0.0.1:8010/)"
case "${PAGE}" in *'<title>Total.js Center</title>'*) ;; *) echo 'the page of Center is wrong' >&2; exit 1 ;; esac
LOGO="$(curl -fsS http://127.0.0.1:8010/logo.svg)"
case "${LOGO}" in *'<svg'*) ;; *) echo 'the logo of Center is wrong' >&2; exit 1 ;; esac
STATUS="$(curl -fsS http://127.0.0.1:8010/api/status/)"
printf '%s' "${STATUS}" | node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8")); if (d.domain !== "totaljs.developer" || d.services.length !== 3 || !d.machine.kernel) process.exit(1)'
kill "${CENTER_PID}" 2>/dev/null || true

echo "==> the summary of the terminal"
FETCH="$(totalfetch)"
case "${FETCH}" in *'Total.js Developer'*) ;; *) echo 'totalfetch shows nothing' >&2; exit 1 ;; esac
test "$(grep -c '^# >>> totaljs-fetch >>>$' /etc/bash.bashrc)" = 1

echo "==> the source that the package wrote works by itself"
apt-get update -qq
POLICY="$(apt-cache policy totaljs-node)"
case "${POLICY}" in *'Candidate: 1.0.0-1'*) ;; *) echo "${POLICY}" >&2; echo 'totaljs-node is not available from the source of the package' >&2; exit 1 ;; esac

echo "==> the wallpapers (a package of its own: only the desktop needs them)"
apt-get install -y totaljs-wallpapers >/dev/null
test "$(ls /usr/share/backgrounds/totaljs/*.jpg | wc -l)" = 12
apt-get remove -y totaljs-wallpapers >/dev/null
test ! -e /usr/share/backgrounds/totaljs

echo "==> installing it again changes nothing"
apt-get install -y --reinstall totaljs-node totaljs-fetch >/dev/null
test "$(grep -c '^# >>> totaljs-fetch >>>$' /etc/bash.bashrc)" = 1   # the greeting is not repeated
test "$(node --version)" = "${NODE_VERSION}"

echo "==> removing it"
apt-get remove -y totaljs-developer-server totaljs-docker-stack totaljs-docker-source totaljs-dns totaljs-center totaljs-fetch totaljs-fnm totaljs-brand totaljs-node >/dev/null
test ! -e /usr/local/bin/fnm
test ! -e /usr/local/bin/pnpm
if grep -q 'totaljs-fnm' /etc/bash.bashrc; then echo 'bash.bashrc still has fnm' >&2; exit 1; fi
test ! -e /usr/local/bin/node
test ! -e /usr/bin/node
test ! -e "/opt/node-${NODE_VERSION}"
test ! -e /usr/local/lib/node_modules/total5
test ! -e /usr/local/lib/node_modules/total4
test ! -e /usr/share/plymouth/themes/totaljs
test ! -e /usr/lib/systemd/system/totaljs-proxy.service
test ! -e /usr/lib/systemd/system/totaljs-dns.service
test ! -e /usr/lib/systemd/system/totaljs-center.service
test ! -e /var/lib/totaljs-center
test ! -e /usr/bin/totalfetch
if grep -q 'totaljs-fetch' /etc/bash.bashrc; then echo 'bash.bashrc still has the greeting' >&2; exit 1; fi
test ! -e /etc/systemd/resolved.conf.d/totaljs-developer.conf
test ! -e /etc/apt/sources.list.d/docker.sources
test -f /www/proxy/docker-compose.yml   # /www is where the person works: it stays
test ! -e /etc/default/grub.d/99-totaljs.cfg
REMAINING="$(update-alternatives --query default.plymouth 2>/dev/null || true)"
case "${REMAINING}" in *'themes/totaljs/totaljs.plymouth'*) echo 'the alternative of the theme is still there' >&2; exit 1 ;; esac
if grep -q '^Theme=totaljs$' /etc/plymouth/plymouthd.conf; then echo 'plymouthd.conf still names the theme' >&2; exit 1; fi

echo "OK ${CODENAME}"
