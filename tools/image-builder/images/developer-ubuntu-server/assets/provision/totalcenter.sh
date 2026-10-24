#!/usr/bin/env bash
# Total.js Developer — Total.js Center dashboard (shared, distro-agnostic).
set -euo pipefail

# --- Total.js Center: a local Total.js app on :8010 ------------------------
# Scaffolded here; the full UI is iterated on separately. The systemd unit and
# port are fixed so the desktop menu and reverse proxy can rely on them.
getent group totalcenter >/dev/null || groupadd --system totalcenter
NOLOGIN="$(command -v nologin || echo /bin/false)"
id totalcenter >/dev/null 2>&1 || useradd --system --gid totalcenter \
    --home-dir /var/lib/totalcenter --create-home --shell "${NOLOGIN}" totalcenter
getent group docker >/dev/null && usermod -aG docker totalcenter || true
install -d -o totalcenter -g totalcenter /opt/totalcenter
if [ -d "${TOTALVM_ASSETS:-/mnt/assets}/totalcenter" ]; then
    cp -a "${TOTALVM_ASSETS}/totalcenter/." /opt/totalcenter/
else
    # Zero-dependency fallback (only reached if the assets share is missing) —
    # no total5/npm to resolve under /opt, so the service can never fail to
    # start. The full dashboard ships in assets/totalcenter/index.js.
    cat > /opt/totalcenter/index.js <<'EOF'
const http = require('http');
http.createServer((req, res) => {
  if (req.url === '/healthz') { res.writeHead(200); res.end('{"ok":true}'); return; }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end('<h1>Total.js Center</h1><p>Total.js Developer environment manager</p>');
}).listen(8010, '0.0.0.0');
EOF
fi
chown -R totalcenter:totalcenter /opt/totalcenter

cat > /etc/systemd/system/totalcenter.service <<'EOF'
[Unit]
Description=Total.js Center (Total.js Developer environment manager)
After=network.target
ConditionPathExists=!/etc/nologin

[Service]
Type=simple
User=totalcenter
Group=totalcenter
WorkingDirectory=/opt/totalcenter
ExecStart=/usr/local/bin/node /opt/totalcenter/index.js
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl enable totalcenter

# --- TotalFetch: branded neofetch-style system summary ---------------------
# Same design as the macOS TotalFetch app: Gera's hand-crafted Total.js mark
# (`*` body + `+` chevron), Total.js green (#66B639) in truecolor, logo on the
# left and info on the right, neofetch-aligned. Kept fast (no npm calls) so it
# can greet on every terminal without adding latency.
cat > /usr/local/bin/totalfetch <<'TOTALFETCH'
#!/usr/bin/env bash
# TotalFetch — Total.js Developer system summary.
[ -f /etc/totalvm/release ] && . /etc/totalvm/release 2>/dev/null

G=$'\033[38;2;102;182;57m'
GB=$'\033[1m\033[38;2;102;182;57m'
R=$'\033[0m'

logo=(
"              ++              "
"          ++++++++++          "
"       ***+++++++++++++       "
"    ******++++++++++++++++    "
"  *********+++++++++++++++++  "
"  **********       +++++++++  "
"  ***********       ++++++++  "
"  ************      ++++++++  "
"  ***********       ++++++++  "
"  **********      ++++++++++  "
"  *********+++++++++++++++++  "
"    ******++++++++++++++++    "
"       ***+++++++++++++       "
"          ++++++++++          "
"              ++              "
)

user="${USER:-$(id -un 2>/dev/null)}"
host="$(hostname 2>/dev/null)"
title="${user}@${host}"
os="${TOTALVM_NAME:-$( . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}")}"
kernel="$(uname -r 2>/dev/null)"
up="$(uptime -p 2>/dev/null | sed 's/^up //')"; [ -z "$up" ] && up="-"
shell_n="$(basename "${SHELL:-bash}")"
res="$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}')"; [ -z "$res" ] && res="-"
cpu="$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//')"
[ -z "$cpu" ] && cpu="$(uname -m 2>/dev/null)"
cores="$(nproc 2>/dev/null)"
mem="$(free -m 2>/dev/null | awk '/Mem:/{printf "%d / %d MiB", $3, $2}')"
disk="$(df -h --output=used,size / 2>/dev/null | awk 'NR==2{print $1" / "$2}')"
# Real LAN IP = the source address of the default route (not docker0's bridge).
ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
[ -z "$ip" ] && ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "$ip" ] && ip="-"

pair() { printf '%s%s%s%s:%s %s' "$GB" "$1" "$R" "$G" "$R" "$2"; }

dots=""
for c in 0 1 2 3 4 5 6 7; do dots+=$'\033'"[4${c}m   "; done
dots+="$R"

info=()
info+=( "${GB}${title}${R}" )
info+=( "${G}$(printf '%*s' "${#title}" '' | tr ' ' '-')${R}" )
info+=( "$(pair 'os'         "$os")" )
info+=( "$(pair 'host'       'Total.js Developer')" )
info+=( "$(pair 'kernel'     "$kernel")" )
info+=( "$(pair 'uptime'     "$up")" )
info+=( "$(pair 'shell'      "$shell_n")" )
info+=( "$(pair 'wm'         'Openbox')" )
info+=( "$(pair 'resolution' "$res")" )
info+=( "$(pair 'cpu'        "${cpu} (${cores})")" )
info+=( "$(pair 'memory'     "$mem")" )
info+=( "$(pair 'disk'       "$disk")" )
info+=( "$(pair 'network ip' "$ip")" )
info+=( "" )
info+=( "$dots" )

rows=${#logo[@]}
[ ${#info[@]} -gt $rows ] && rows=${#info[@]}
echo
i=0
while [ $i -lt $rows ]; do
    l="${logo[i]:-}"
    if [ -n "$l" ]; then
        printf '%s%s%s' "$G" "$l" "$R"
        pad=$(( 30 - ${#l} + 4 ))
    else
        pad=$(( 30 + 4 ))
    fi
    printf '%*s' "$pad" ''
    printf '%s\n' "${info[i]:-}"
    i=$(( i + 1 ))
done
echo
TOTALFETCH
chmod +x /usr/local/bin/totalfetch

# Greet on every interactive terminal — not just login shells. /etc/profile.d
# only runs for login shells (SSH/console), NOT for a normal terminal like
# Alacritty (interactive non-login). /etc/bash.bashrc covers both on Ubuntu.
rm -f /etc/profile.d/totalfetch.sh
cat >> /etc/bash.bashrc <<'EOF'

# TotalFetch greeting — interactive shells, once per shell.
if [ -n "$PS1" ] && [ -z "${TOTALFETCH_SHOWN:-}" ] && [ -t 1 ]; then
    export TOTALFETCH_SHOWN=1
    totalfetch
fi
EOF

echo "[40-totalcenter] done"
