#!/usr/bin/env bash
# Total.js Developer — wildcard DNS config (dnsmasq + systemd-resolved). Shared.
# The distro wrapper installs dnsmasq (and, on Arch, enables systemd-resolved)
# before running this.
#
# Goal: make `code.<domain>` and every `<project>.<domain>` resolve to THIS
# VM's LAN/NAT address, both inside the VM and — crucially — from the Mac that
# runs it. TotalVM's split-DNS extension routes only *.domain queries here, so
# dnsmasq answers the wildcard and nothing else.
#
# Design notes:
#   * dnsmasq binds ONLY the active NIC's IP — never loopback. systemd-resolved
#     owns port 53 on 127.0.0.53/127.0.0.54, and dnsmasq can't share lo there.
#   * systemd-resolved routes only *.<domain> to dnsmasq AT THAT NIC IP; every
#     other lookup uses the normal upstream DNS.
#   * The NIC IP is DHCP-assigned and changes, so a tiny refresh script rewrites
#     both the dnsmasq record and the resolved drop-in, wired to run at boot
#     (after the network is up) and on every NetworkManager IP change.
set -euo pipefail


# dnsmasq must NOT touch the system resolver or listen broadly — our drop-in is
# the whole config. Keep the stock /etc/dnsmasq.conf (it just includes .d/*).
install -d /etc/dnsmasq.d

# The VM ITSELF resolves *.<domain> via dnsmasq too. dnsmasq listens ONLY on the
# active NIC's IP — NOT loopback — because systemd-resolved already owns port 53
# on 127.0.0.53/127.0.0.54 and dnsmasq cannot share it there ("port 53 address
# already in use"). So systemd-resolved must route the domain to that NIC IP; the
# refresh script writes that drop-in with the live IP. Just ensure the dir exists.
install -d /etc/systemd/resolved.conf.d

# Let NetworkManager publish the DHCP-provided upstream DNS servers to
# systemd-resolved when NetworkManager is present. Ubuntu Server uses
# systemd-networkd instead; this drop-in is harmless there.
install -d /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/20-totaljs-resolved.conf <<'EOF'
[main]
dns=systemd-resolved
rc-manager=symlink
EOF
systemctl enable systemd-resolved.service >/dev/null 2>&1 || true
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# Ubuntu and Arch ship different dnsmasq units and defaults. Own the tiny
# authoritative instance we need so both images load exactly this one config.
DNSMASQ_BIN="$(command -v dnsmasq)"
cat > /etc/systemd/system/totaljs-dnsmasq.service <<EOF
[Unit]
Description=Total.js Developer local domain DNS
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${DNSMASQ_BIN} --keep-in-foreground --conf-file=/etc/dnsmasq.d/totalvm.conf
Restart=on-failure
RestartSec=2
EOF

# --- Refresh script: write the wildcard record for the current domain+IP ----
cat > /usr/local/sbin/totalvm-dns-refresh <<'EOF'
#!/usr/bin/env bash
# Regenerate the dnsmasq wildcard record from the configured domain and the
# VM's current primary IPv4. Safe to run repeatedly (idempotent).
set -euo pipefail
DOMAIN="$(cat /etc/totalvm/domain 2>/dev/null || echo totaljs.developer)"
ROUTE="$(ip route get 1.1.1.1 2>/dev/null || true)"
IP="$(awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' <<<"${ROUTE}")"
IFACE="$(awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"${ROUTE}")"
[ -z "${IP}" ] && IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "${IP}" ] && IP="127.0.0.1"
[ -z "${IFACE}" ] && IFACE="$(ls /sys/class/net 2>/dev/null | grep -v '^lo$' | head -n1)"
[ -z "${IFACE}" ] && IFACE="eth0"

# Keep normal Internet DNS working even if resolved temporarily falls back to
# this server. Prefer DHCP DNS from NetworkManager, then the NAT gateway.
UPSTREAMS="$(nmcli -g IP4.DNS device show "${IFACE}" 2>/dev/null | sed '/^$/d' || true)"
if [ -z "${UPSTREAMS}" ]; then
    UPSTREAMS="$(ip route show default 2>/dev/null | awk '{print $3; exit}')"
fi
UPSTREAM_CONFIG=""
while IFS= read -r server; do
    [ -n "${server}" ] || continue
    [ "${server}" = "${IP}" ] && continue
    UPSTREAM_CONFIG+="server=${server}"$'\n'
done <<< "${UPSTREAMS}"

cat > /etc/dnsmasq.d/totalvm.conf <<CONF
# Managed by totalvm-dns-refresh — do not edit by hand.
# Answer the local dev domain (and every subdomain) with this VM's IP, listening
# ONLY on the active NIC (so the host Mac reaches it through TotalVM, and the VM
# itself reaches it at the same IP). We deliberately do NOT listen on loopback:
# systemd-resolved owns port 53 on 127.0.0.53/127.0.0.54 there. We use
# Listen on the NIC's SPECIFIC IP only. bind-interfaces makes dnsmasq bind just
# that address (no 0.0.0.0 wildcard, no loopback), so it never races with
# systemd-resolved on 127.0.0.53/127.0.0.54. We bind by IP (not interface name)
# because it's deterministic — and this config is only ever started AFTER the
# network is up (by totalvm-dns.service), so the IP always exists.
bind-interfaces
listen-address=${IP}
no-resolv
no-poll
no-hosts
local-ttl=30
address=/${DOMAIN}/${IP}
${UPSTREAM_CONFIG}
CONF

# Route the VM's own *.${DOMAIN} lookups to dnsmasq at the NIC IP (everything
# else still uses the normal upstream DNS via systemd-resolved).
install -d /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/totalvm.conf <<RESOLVED
[Resolve]
DNS=${IP}
Domains=~${DOMAIN}
RESOLVED

# (Re)start dnsmasq with the fresh record. Clear any start-limit left by failed
# early-boot attempts (before the network was up), then start it even if a prior
# attempt left it stopped. This runs from totalvm-dns.service at boot (after the
# network is online) and on every NetworkManager IP change — never at build time.
systemctl daemon-reload 2>/dev/null || true
systemctl reset-failed totaljs-dnsmasq 2>/dev/null || true
"$(command -v dnsmasq)" --test --conf-file=/etc/dnsmasq.d/totalvm.conf
systemctl restart totaljs-dnsmasq
# Apply the resolved drop-in (so the VM resolves *.${DOMAIN} via the NIC IP).
systemctl restart systemd-resolved 2>/dev/null || true

# Do not advertise a half-ready DNS server to the Mac. Publishing happens only
# after the guest itself resolves the wildcard to its real NAT address.
RESOLVED_IP=""
for _ in $(seq 1 10); do
    RESOLVED_IP="$(getent ahostsv4 "code.${DOMAIN}" 2>/dev/null | awk 'NR==1 {print $1}')"
    [ "${RESOLVED_IP}" = "${IP}" ] && break
    sleep 1
done
if [ "${RESOLVED_IP}" != "${IP}" ]; then
    echo "totalvm-dns-refresh: expected code.${DOMAIN} -> ${IP}, got ${RESOLVED_IP:-nothing}" >&2
    exit 1
fi

# Publish the verified IP + domain into the host-shared environment. TotalVM
# watches this file and gives the IP to its DNS proxy extension.
if [ -d /www ]; then
    mkdir -p /www/.totalvm 2>/dev/null || true
    printf '{"ip":"%s","domain":"%s","code":"http://code.%s","updated":"%s"}\n' \
        "${IP}" "${DOMAIN}" "${DOMAIN}" "$(date -u +%FT%TZ)" \
        > /www/.totalvm/network.json 2>/dev/null || true
fi
EOF
chmod +x /usr/local/sbin/totalvm-dns-refresh

# Seed an initial config so dnsmasq has something valid to start with on first
# boot even before the refresh service runs (uses a placeholder IP).
DOMAIN_NOW="$(cat /etc/totalvm/domain 2>/dev/null || echo totaljs.developer)"
IFACE_NOW="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
[ -z "${IFACE_NOW}" ] && IFACE_NOW="$(ls /sys/class/net 2>/dev/null | grep -v '^lo$' | head -n1)"
[ -z "${IFACE_NOW}" ] && IFACE_NOW="eth0"
cat > /etc/dnsmasq.d/totalvm.conf <<EOF
# Managed by totalvm-dns-refresh — do not edit by hand. Placeholder until the
# refresh runs (after the network is up) and rewrites it with the real NIC IP.
bind-interfaces
listen-address=127.0.0.1
no-resolv
no-poll
no-hosts
local-ttl=30
address=/${DOMAIN_NOW}/127.0.0.1
EOF

# --- Run the refresh at boot, once the network is actually up --------------
cat > /etc/systemd/system/totalvm-dns.service <<'EOF'
[Unit]
Description=Total.js Developer wildcard DNS refresh
After=network-online.target NetworkManager.service systemd-networkd.service www.mount totalvm-www-seed.service
Wants=network-online.target
# NOTE: deliberately NOT "Before=dnsmasq.service". Ordering before dnsmasq while
# also ordering After=network-online.target created a systemd ordering cycle
# (dnsmasq → totalvm-dns → network-online → dnsmasq), so systemd dropped
# dnsmasq's start job and it failed to start in a loop. The refresh script
# restarts dnsmasq itself once it has written the real wildcard record.

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/totalvm-dns-refresh

[Install]
WantedBy=multi-user.target
EOF

# --- And re-run whenever NetworkManager changes the address ----------------
install -d /etc/NetworkManager/dispatcher.d
cat > /etc/NetworkManager/dispatcher.d/50-totalvm-dns <<'EOF'
#!/usr/bin/env bash
# Refresh the wildcard DNS record when the active NIC comes up or changes.
iface="$1"; action="$2"
case "${action}" in
    up|dhcp4-change|dhcp6-change|reapply)
        [ "${iface}" != "lo" ] && /usr/local/sbin/totalvm-dns-refresh || true
        ;;
esac
EOF
chmod +x /etc/NetworkManager/dispatcher.d/50-totalvm-dns

# --- Keep the virtio NIC and published address healthy --------------------
# A host sleep/wake or a brief Apple NAT reset can leave NetworkManager with a
# visible Ethernet device but no default route. Recover it automatically, then
# refresh DNS whenever the lease or dnsmasq state changed. This also prevents a
# stale network.json from keeping the Mac tunnel attached to a dead address.
cat > /usr/local/sbin/totaljs-network-guard <<'EOF'
#!/usr/bin/env bash
set -u

IFACE=""
if command -v nmcli >/dev/null 2>&1; then
    IFACE="$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null \
        | awk -F: '$2=="ethernet" {print $1; exit}')"
fi
[ -n "${IFACE}" ] || IFACE="$(ip route get 1.1.1.1 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
[ -n "${IFACE}" ] || exit 0

if command -v nmcli >/dev/null 2>&1; then
    STATE="$(nmcli -g GENERAL.STATE device show "${IFACE}" 2>/dev/null || true)"
else
    STATE=100
fi
if [[ "${STATE}" != 100* ]] || ! ip route show default 2>/dev/null | grep -q .; then
    if command -v nmcli >/dev/null 2>&1; then
        nmcli networking on >/dev/null 2>&1 || true
        nmcli device set "${IFACE}" managed yes >/dev/null 2>&1 || true
        nmcli device connect "${IFACE}" >/dev/null 2>&1 || true
    else
        networkctl renew "${IFACE}" >/dev/null 2>&1 || true
    fi
fi

# A stale Apple NAT link can retain its route while carrying no traffic. Only
# bounce it after three consecutive failed DNS probes to avoid reacting to a
# momentary upstream delay.
FAILURES=/run/totaljs-network-guard.failures
if timeout 5 getent ahostsv4 ports.ubuntu.com >/dev/null 2>&1 \
    || timeout 5 getent ahostsv4 archlinux.org >/dev/null 2>&1; then
    rm -f "${FAILURES}"
else
    count="$(cat "${FAILURES}" 2>/dev/null || echo 0)"
    count=$((count + 1))
    printf '%s\n' "${count}" > "${FAILURES}"
    if [ "${count}" -ge 3 ]; then
        if command -v nmcli >/dev/null 2>&1; then
            nmcli device disconnect "${IFACE}" >/dev/null 2>&1 || true
            sleep 1
            nmcli device connect "${IFACE}" >/dev/null 2>&1 || true
        else
            networkctl renew "${IFACE}" >/dev/null 2>&1 || true
        fi
        rm -f "${FAILURES}"
    fi
fi

ROUTE="$(ip route get 1.1.1.1 2>/dev/null || true)"
IP="$(awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}' <<<"${ROUTE}")"
[ -n "${IP}" ] || exit 0

PUBLISHED="$(sed -n 's/.*"ip":"\([^"]*\)".*/\1/p' /www/.totalvm/network.json 2>/dev/null || true)"
if [ "${PUBLISHED}" != "${IP}" ] || ! systemctl is-active --quiet totaljs-dnsmasq; then
    /usr/local/sbin/totalvm-dns-refresh || true
fi
EOF
chmod +x /usr/local/sbin/totaljs-network-guard

cat > /etc/systemd/system/totaljs-network-guard.service <<'EOF'
[Unit]
Description=Total.js Developer network health check
After=NetworkManager.service systemd-networkd.service www.mount
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/totaljs-network-guard
EOF

cat > /etc/systemd/system/totaljs-network-guard.timer <<'EOF'
[Unit]
Description=Keep the Total.js Developer network available

[Timer]
OnBootSec=20s
OnUnitActiveSec=15s
AccuracySec=3s
Unit=totaljs-network-guard.service

[Install]
WantedBy=timers.target
EOF

# Do NOT enable dnsmasq.service: at early boot the NIC has no IP yet, so a
# listen-address bind would fail. totalvm-dns.service (after network-online)
# computes the IP, writes the config and starts dnsmasq itself.
systemctl disable --now dnsmasq >/dev/null 2>&1 || true
systemctl enable totalvm-dns.service >/dev/null 2>&1 || true
systemctl enable totaljs-network-guard.timer >/dev/null 2>&1 || true

echo "[28-dns] done"
