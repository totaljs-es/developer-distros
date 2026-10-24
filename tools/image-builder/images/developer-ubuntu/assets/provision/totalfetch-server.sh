#!/usr/bin/env bash
# TotalFetch for the headless server editions.
set -euo pipefail

cat > /usr/local/bin/totalfetch <<'TOTALFETCH'
#!/usr/bin/env bash
[ -f /etc/totalvm/release ] && . /etc/totalvm/release 2>/dev/null

G=$'\033[38;2;102;182;57m'
GB=$'\033[1m\033[38;2;102;182;57m'
M=$'\033[38;2;148;163;184m'
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

user="${USER:-$(id -un 2>/dev/null || echo user)}"
host="$(hostname 2>/dev/null || echo totaljs-server)"
title="${user}@${host}"
os="${TOTALVM_NAME:-Total.js Developer (Server Edition)}"
base="Linux"
kernel="$(uname -r 2>/dev/null || echo "-")"
up="$(uptime -p 2>/dev/null | sed 's/^up //')"; [ -n "$up" ] || up="-"
shell_n="$(basename "${SHELL:-bash}")"
cpu="$(awk -F: '/model name|Hardware/{print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^ *//')"
[ -n "$cpu" ] || cpu="$(uname -m 2>/dev/null || echo "-")"
cores="$(nproc 2>/dev/null || echo 1)"
mem="$(free -m 2>/dev/null | awk '/Mem:/{printf "%d / %d MiB", $3, $2}')"
[ -n "$mem" ] || mem="-"
disk="$(df -h --output=used,size / 2>/dev/null | awk 'NR==2{print $1" / "$2}')"
[ -n "$disk" ] || disk="-"
ipaddr="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
[ -n "$ipaddr" ] || ipaddr="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -n "$ipaddr" ] || ipaddr="-"

pair() { printf '%s%s%s:%s %s' "$GB" "$1" "$R" "$M" "$2"; }
block() { printf '\033[48;2;%s;%s;%sm   %s' "$1" "$2" "$3" "$R"; }

palette=""
palette+="$(block 21 24 28)"
palette+="$(block 231 90 90)"
palette+="$(block 106 192 67)"
palette+="$(block 216 180 93)"
palette+="$(block 77 163 255)"
palette+="$(block 180 124 255)"
palette+="$(block 85 199 194)"
palette+="$(block 215 217 220)"

info=()
info+=( "${GB}${title}${R}" )
info+=( "${G}$(printf '%*s' "${#title}" '' | tr ' ' '-')${R}" )
info+=( "$(pair 'os'         "$os")" )
info+=( "$(pair 'base'       "$base")" )
info+=( "$(pair 'kernel'     "$kernel")" )
info+=( "$(pair 'uptime'     "$up")" )
info+=( "$(pair 'shell'      "$shell_n")" )
info+=( "$(pair 'cpu'        "${cpu} (${cores})")" )
info+=( "$(pair 'memory'     "$mem")" )
info+=( "$(pair 'disk'       "$disk")" )
info+=( "$(pair 'ip'         "$ipaddr")" )
info+=( "" )
info+=( "$palette" )

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
    i=$((i + 1))
done
echo
TOTALFETCH
chmod +x /usr/local/bin/totalfetch

cat > /etc/profile.d/totaljs-terminal-colors.sh <<'EOF'
# Total.js terminal palette shared with the desktop distro.
if [ -n "${PS1:-}" ]; then
    export LS_COLORS="${LS_COLORS:-di=38;2;106;192;67:ln=38;2;85;199;194:ex=38;2;154;217;89:*.js=38;2;216;180;93:*.json=38;2;116;185;255:*.md=38;2;180;124;255}"
    if [ "${TERM:-}" != "dumb" ]; then
        PS1='\[\033[38;2;106;192;67m\]\u@\h\[\033[0m\]:\[\033[38;2;148;163;184m\]\w\[\033[0m\]\$ '
    fi
fi
EOF

cat > /etc/profile.d/totalfetch.sh <<'EOF'
# TotalFetch greeting.
if [ -n "${PS1:-}" ] && [ -z "${TOTALFETCH_SHOWN:-}" ] && [ -t 1 ]; then
    export TOTALFETCH_SHOWN=1
    command -v totalfetch >/dev/null 2>&1 && totalfetch
fi
EOF

if [ -f /etc/bash.bashrc ] && ! grep -q 'TOTALFETCH_SHOWN' /etc/bash.bashrc; then
    cat >> /etc/bash.bashrc <<'EOF'

# TotalFetch greeting.
if [ -n "${PS1:-}" ] && [ -z "${TOTALFETCH_SHOWN:-}" ] && [ -t 1 ]; then
    export TOTALFETCH_SHOWN=1
    command -v totalfetch >/dev/null 2>&1 && totalfetch
fi
EOF
fi

echo "[totalfetch-server] done"
