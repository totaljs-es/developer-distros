#!/usr/bin/env bash
# arch/test-install.sh - installs the server edition from the repository that arch/build.sh made, in a container of Arch, and looks at what it promises.
#
#   arch/test-install.sh /path/to/the/folder/with/the/repository
#
# As root, in a container: there is no systemd running, so the units are checked as files. (No `| grep -q` at the end of a pipe: with pipefail it dies with 141.)
set -euo pipefail

REPO="${1:?the folder of the repository (the one with totaljs-developer.db.tar.zst)}"
test -f "${REPO}/totaljs-developer.db.tar.zst"

echo "==> the repository"
cat >> /etc/pacman.conf <<CONF

[totaljs-developer]
SigLevel = Optional TrustAll
Server = file://${REPO}
CONF
pacman -Syu --noconfirm
pacman -Si totaljs-developer-server >/dev/null

echo "==> install the server edition"
# a second person, made before the layer, like the installer does with the first one
useradd -m -s /bin/bash earlyuser
pacman -S --noconfirm totaljs-developer-server

echo "==> the runtime"
NODE_VERSION="$(sed -n 's/^NODE_VERSION=//p' /usr/share/totaljs-node/versions)"
test "$(node --version)" = "${NODE_VERSION}"
test -x /usr/local/bin/total5
test -x /usr/local/bin/total4
fnm --version | grep '^fnm 1\.' >/dev/null

echo "==> the group and the first person"
getent group totaljs-developer >/dev/null
# the first regular person of the system (in this container it is "builder", the one that built the packages, with the uid 1000: earlyuser has the next one)
FIRST="$(cat /var/lib/totaljs-developer/first-user)"
test -n "${FIRST}"
case " $(id -nG "${FIRST}") " in *' totaljs-developer '*) ;; *) echo "${FIRST} is not in totaljs-developer: $(id -nG "${FIRST}")" >&2; exit 1 ;; esac
case " $(id -nG "${FIRST}") " in *' docker '*) ;; *) echo "${FIRST} is not in docker: $(id -nG "${FIRST}")" >&2; exit 1 ;; esac

echo "==> the splash of the boot"
test -f /usr/share/plymouth/themes/totaljs/totaljs.plymouth
grep '^Theme=totaljs$' /etc/plymouth/plymouthd.conf >/dev/null
if [ -f /etc/mkinitcpio.conf ]; then grep -E '^HOOKS=.*plymouth' /etc/mkinitcpio.conf >/dev/null; fi

echo "==> the tools of a developer"
for c in git curl jq tmux psql sqlite3 git-lfs gh rg fd fzf bat http nvim; do command -v "${c}" >/dev/null || { echo "missing: ${c}" >&2; exit 1; }; done
test "$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo 524288)" -ge 8192
grep -q '^fs.inotify.max_user_watches = 524288$' /etc/sysctl.d/90-totaljs-developer.conf

echo "==> Docker and the services"
docker --version
docker compose version
for stack in proxy code flow services/postgres; do
    test -f "/www/${stack}/docker-compose.yml"
    docker compose -f "/www/${stack}/docker-compose.yml" config -q
done
test "$(stat -c %G /www)" = totaljs-developer
for unit in totaljs-proxy totaljs-code totaljs-flow totaljs-postgres totaljs-dns totaljs-center; do test -f "/usr/lib/systemd/system/${unit}.service"; done
totaljs-service list | grep '^redis .*off' >/dev/null
for svc in redis mailpit mongodb; do
    docker compose -f "/usr/share/totaljs-developer/catalog/${svc}/docker-compose.yml" config -q
done

echo "==> HTTPS"
test -s /usr/local/share/ca-certificates/totaljs-developer.crt
test -s /etc/ca-certificates/trust-source/anchors/totaljs-developer.crt
trust list | grep 'Total.js Developer local CA' >/dev/null
openssl verify -CAfile /usr/local/share/ca-certificates/totaljs-developer.crt /www/proxy/data/certs/totaljs.developer.crt >/dev/null
openssl x509 -in /www/proxy/data/certs/totaljs.developer.crt -noout -text | grep 'DNS:\*\.totaljs\.developer' >/dev/null
test "$(grep -c '^# totaljs-https$' /etc/environment)" = 1

echo "==> the local domain"
test -f /etc/totaljs-developer/dns.conf
test -f /usr/lib/tmpfiles.d/totaljs-dns.conf
test -f /etc/NetworkManager/conf.d/90-totaljs-dns.conf
test -e /etc/systemd/system/sysinit.target.wants/systemd-resolved.service || test -e /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
dnsmasq --test --conf-file=/etc/totaljs-developer/dns.conf
dnsmasq --keep-in-foreground --conf-file=/etc/totaljs-developer/dns.conf --pid-file=/tmp/dns-test.pid >/tmp/dns-test.log 2>&1 &
DNS_PID=$!
sleep 1
if command -v dig >/dev/null 2>&1; then test "$(dig +short +time=2 +tries=1 @127.0.0.100 code.totaljs.developer)" = 127.0.0.1; fi
kill -0 "${DNS_PID}"   # still running: it dropped to its user and group without failing (an unknown group makes it stop)
kill "${DNS_PID}" 2>/dev/null || true

echo "==> Total.js Center"
test -f /var/lib/totaljs-center/index.js
test -f /usr/share/totaljs-developer/center/public/logo.svg   # the mark: it comes from shared/branding with `include`
id totalcenter >/dev/null
case " $(id -nG totalcenter) " in *' docker '*) echo 'totalcenter is in docker' >&2; exit 1 ;; esac

echo "==> remove"
pacman -Rns --noconfirm totaljs-developer-server totaljs-center totaljs-https totaljs-services totaljs-docker-stack totaljs-dns totaljs-fnm totaljs-node totaljs-fetch totaljs-developer-release
test ! -e /usr/local/bin/fnm
test ! -e /usr/local/share/ca-certificates/totaljs-developer.crt
if grep -q totaljs-developer /etc/pacman.conf; then echo 'pacman.conf still has the repository' >&2; exit 1; fi

echo "OK arch"
