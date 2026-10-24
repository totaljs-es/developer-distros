#!/usr/bin/env bash
# Install the minimal first-boot console wizard used by server editions.
set -euo pipefail

cat > /usr/local/sbin/totalvm-server-firstboot <<'FIRSTBOOT'
#!/usr/bin/env bash
set -euo pipefail

MARKER=/etc/totalvm/firstboot.done
[ ! -f "${MARKER}" ] || exit 0

for _ in $(seq 1 60); do
    [ -e /dev/tty1 ] && break
    sleep 0.2
done

CONSOLE_TTY=/dev/tty1
if [ -e /dev/tty1 ]; then
    CONSOLE_TTY=/dev/tty1
    exec <"${CONSOLE_TTY}" >"${CONSOLE_TTY}" 2>&1
elif [ -e /dev/hvc0 ]; then
    CONSOLE_TTY=/dev/hvc0
    exec <"${CONSOLE_TTY}" >"${CONSOLE_TTY}" 2>&1
fi

admin_group=sudo
if getent group wheel >/dev/null 2>&1; then
    admin_group=wheel
fi

list_keymaps() {
    # Prefer real console keymaps, then include XKB layout codes. Ubuntu Server
    # can ship only a tiny console map set while still carrying the full XKB
    # layout catalog through keyboard-configuration/xkb-data.
    for root in /usr/share/kbd/keymaps /usr/share/keymaps; do
        [ -d "${root}" ] || continue
        find "${root}" -type f \( -name '*.map' -o -name '*.map.gz' \) 2>/dev/null \
            | sed -E 's#.*/##; s#\.map(\.gz)?$##'
    done
    if command -v localectl >/dev/null 2>&1; then
        localectl list-keymaps 2>/dev/null || true
        localectl list-x11-keymap-layouts 2>/dev/null || true
    fi
    for rules in /usr/share/X11/xkb/rules/evdev.lst /usr/share/X11/xkb/rules/base.lst; do
        [ -f "${rules}" ] || continue
        awk '
            /^![[:space:]]*layout/ {in_layout=1; next}
            /^!/ {in_layout=0}
            in_layout && NF && $1 ~ /^[A-Za-z0-9_-]+$/ {print $1}
        ' "${rules}"
    done
    printf '%s\n' \
        us gb es fr de it pt br nl be ca ch cz dk fi gr hu ie is jp latam no pl ro se sk tr ua
}

x11_layout_for_keymap() {
    keymap="$1"
    layout="${keymap%%-*}"
    case "${layout}" in
        uk) layout=gb ;;
        be-latin1) layout=be ;;
        br-abnt2) layout=br ;;
        cf|ca-fr) layout=ca ;;
        dvorak) layout=us ;;
        gr) layout=gr ;;
        jp106) layout=jp ;;
        no-latin1) layout=no ;;
        pt-latin1) layout=pt ;;
        sg|sg-latin1) layout=ch ;;
        sv-latin1) layout=se ;;
    esac
    printf '%s\n' "${layout}"
}

list_locales() {
    locale -a 2>/dev/null | sed 's/utf8$/UTF-8/' || true
    awk '/UTF-8/ {print $1}' /usr/share/i18n/SUPPORTED 2>/dev/null || true
    sed -nE 's/^#?[[:space:]]*([^[:space:]#]+\.UTF-8)[[:space:]]+UTF-8.*/\1/p' /etc/locale.gen 2>/dev/null || true
}

list_timezones() {
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl list-timezones 2>/dev/null || true
    fi
    find /usr/share/zoneinfo -type f 2>/dev/null \
        | sed 's#^/usr/share/zoneinfo/##' \
        | grep -Ev '^(posix|right)/|^(Etc/)?(GMT|UTC|UCT|Universal|Zulu)$|\.tab$|leapseconds$|localtime$'
}

current_keymap() {
    if command -v localectl >/dev/null 2>&1; then
        localectl status 2>/dev/null | awk -F: '/VC Keymap/ {gsub(/^[[:space:]]+/, "", $2); if ($2 != "" && $2 != "n/a" && $2 != "(unset)") print $2; exit}'
        localectl status 2>/dev/null | awk -F: '/X11 Layout/ {gsub(/^[[:space:]]+/, "", $2); if ($2 != "" && $2 != "n/a" && $2 != "(unset)") print $2; exit}'
    fi
    awk -F= '/^KEYMAP=/ {gsub(/"/, "", $2); print $2; exit}' /etc/vconsole.conf 2>/dev/null || true
    awk -F= '/^XKBLAYOUT=/ {gsub(/"/, "", $2); split($2, layouts, ","); print layouts[1]; exit}' /etc/default/keyboard 2>/dev/null || true
    printf 'us\n'
}

current_locale() {
    awk -F= '/^LANG=/ {gsub(/"/, "", $2); print $2; exit}' /etc/default/locale /etc/locale.conf 2>/dev/null || true
    locale 2>/dev/null | awk -F= '/^LANG=/ {gsub(/"/, "", $2); print $2; exit}' || true
    printf 'C.UTF-8\n'
}

current_timezone() {
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl show -p Timezone --value 2>/dev/null | sed '/^$/d' || true
    fi
    sed -n '1p' /etc/timezone 2>/dev/null || true
    if [ -L /etc/localtime ]; then
        readlink /etc/localtime 2>/dev/null | sed 's#^/usr/share/zoneinfo/##' || true
    fi
    printf 'UTC\n'
}

choose_from_list() {
    title="$1"
    default="$2"
    provider="$3"
    options_file="$(mktemp)"
    result_file="$(mktemp)"

    "${provider}" | sed '/^$/d' | sort -u > "${options_file}"
    TERM="${TERM:-linux}" /usr/local/sbin/totalvm-console-select "${title}" "${default}" "${options_file}" "${result_file}" <"${CONSOLE_TTY}" >"${CONSOLE_TTY}" 2>&1
    value="$(sed -n '1p' "${result_file}" 2>/dev/null || true)"
    rm -f "${options_file}" "${result_file}"
    [ -n "${value}" ] || value="${default}"
    printf '%s\n' "${value}"
}

clear 2>/dev/null || true
printf '\n'
printf 'Total.js Developer\n'
printf 'First-run setup\n'
printf '====================\n\n'
printf 'Configure keyboard, region and administrator account.\n\n'

keyboard="$(choose_from_list 'Keyboard layout:' "$(current_keymap | sed -n '1p')" list_keymaps)"
locale_value="$(choose_from_list 'Regional locale:' "$(current_locale | sed -n '1p')" list_locales)"
timezone_value="$(choose_from_list 'Timezone:' "$(current_timezone | sed -n '1p')" list_timezones)"

printf '\nApplying regional settings...\n'
x11_layout="$(x11_layout_for_keymap "${keyboard}")"
if command -v localectl >/dev/null 2>&1; then
    localectl set-keymap "${keyboard}" >/dev/null 2>&1 || true
    localectl set-x11-keymap "${x11_layout}" >/dev/null 2>&1 || true
fi
if command -v loadkeys >/dev/null 2>&1; then
    loadkeys -C "${CONSOLE_TTY}" "${keyboard}" >/dev/null 2>&1 \
        || loadkeys -C "${CONSOLE_TTY}" "${keyboard%%-*}" >/dev/null 2>&1 \
        || loadkeys "${keyboard}" >/dev/null 2>&1 \
        || loadkeys "${keyboard%%-*}" >/dev/null 2>&1 \
        || true
fi
install -d /etc
if [ -f /etc/vconsole.conf ]; then
    sed -i '/^KEYMAP=/d; /^XKBLAYOUT=/d; /^XKBVARIANT=/d' /etc/vconsole.conf 2>/dev/null || true
fi
printf 'KEYMAP=%s\n' "${keyboard}" >> /etc/vconsole.conf
if [ -f /etc/default/keyboard ]; then
    sed -i '/^XKBLAYOUT=/d; /^XKBVARIANT=/d' /etc/default/keyboard 2>/dev/null || true
    {
        printf 'XKBLAYOUT="%s"\n' "${x11_layout}"
        printf 'XKBVARIANT=""\n'
    } >> /etc/default/keyboard
fi
if command -v setupcon >/dev/null 2>&1; then
    setupcon --force --save >/dev/null 2>&1 || setupcon -k >/dev/null 2>&1 || true
fi
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart systemd-vconsole-setup.service >/dev/null 2>&1 || true
    systemctl restart totalvm-keymap.service >/dev/null 2>&1 || true
fi
if command -v loadkeys >/dev/null 2>&1; then
    loadkeys -C "${CONSOLE_TTY}" "${keyboard}" >/dev/null 2>&1 \
        || loadkeys -C "${CONSOLE_TTY}" "${keyboard%%-*}" >/dev/null 2>&1 \
        || true
fi

locale_base="${locale_value%%.*}"
if [ -f /etc/locale.gen ] && [ "${locale_value}" != "C.UTF-8" ] && [ "${locale_value}" != "C" ] && [ "${locale_value}" != "POSIX" ]; then
    sed -i "s/^#\\(${locale_value//\//\\/} UTF-8\\)/\\1/" /etc/locale.gen 2>/dev/null || true
    grep -qxF "${locale_value} UTF-8" /etc/locale.gen 2>/dev/null \
        || printf '%s UTF-8\n' "${locale_value}" >> /etc/locale.gen
fi
command -v locale-gen >/dev/null 2>&1 && locale-gen >/dev/null 2>&1 || true
printf 'LANG=%s\n' "${locale_value}" > /etc/locale.conf
if command -v update-locale >/dev/null 2>&1; then
    update-locale "LANG=${locale_value}" >/dev/null 2>&1 || true
fi
if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-timezone "${timezone_value}" >/dev/null 2>&1 || true
elif [ -f "/usr/share/zoneinfo/${timezone_value}" ]; then
    ln -sf "/usr/share/zoneinfo/${timezone_value}" /etc/localtime
fi

printf '\nCreate your administrator account.\n\n'

while :; do
    printf 'Username: '
    IFS= read -r username
    username="$(printf '%s' "${username}" | tr '[:upper:]' '[:lower:]')"
    case "${username}" in
        ""|root|totaljs)
            printf 'Please choose a username other than root or totaljs.\n'
            continue
            ;;
    esac
    if ! printf '%s' "${username}" | grep -Eq '^[a-z_][a-z0-9_-]{1,31}$'; then
        printf 'Use 2-32 chars: lowercase letters, numbers, _ or -, starting with a letter/_\n'
        continue
    fi
    if id "${username}" >/dev/null 2>&1; then
        printf 'That user already exists.\n'
        continue
    fi
    break
done

while :; do
    printf 'Password: '
    stty -echo 2>/dev/null || true
    IFS= read -r password
    stty echo 2>/dev/null || true
    printf '\n'
    if [ "${#password}" -lt 4 ]; then
        printf 'Please use at least 4 characters.\n'
        continue
    fi
    printf 'Confirm password: '
    stty -echo 2>/dev/null || true
    IFS= read -r confirm
    stty echo 2>/dev/null || true
    printf '\n'
    if [ "${password}" != "${confirm}" ]; then
        printf 'Passwords did not match.\n'
        continue
    fi
    break
done

extra_groups="${admin_group}"
if getent group docker >/dev/null 2>&1; then
    extra_groups="${extra_groups},docker"
fi

useradd -m -s /bin/bash -G "${extra_groups}" "${username}"
printf '%s:%s\n' "${username}" "${password}" | chpasswd

printf '%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "${username}" > /etc/sudoers.d/10-totalvm-admin
chmod 0440 /etc/sudoers.d/10-totalvm-admin
command -v visudo >/dev/null 2>&1 && visudo -cf /etc/sudoers.d/10-totalvm-admin >/dev/null

install -d -o "${username}" -g "${username}" /srv/total/apps /srv/total/templates /srv/total/logs
chown -R "${username}:${username}" /srv/total
if [ -d /www ]; then
    chown -R "${username}:${username}" /www 2>/dev/null || true
fi
if [ -d /var/lib/totalvm/www-seed ]; then
    chown -R "${username}:${username}" /var/lib/totalvm/www-seed 2>/dev/null || true
fi

if id totaljs >/dev/null 2>&1; then
    userdel -r totaljs >/dev/null 2>&1 || {
        passwd -l totaljs >/dev/null 2>&1 || true
        chage -E 0 totaljs >/dev/null 2>&1 || true
        usermod -s "$(command -v nologin || echo /usr/sbin/nologin)" totaljs >/dev/null 2>&1 || true
    }
fi
rm -f /etc/sudoers.d/90-totaljs

mkdir -p /etc/totalvm
cat > "${MARKER}" <<EOF
TOTALVM_USER="${username}"
TOTALVM_KEYMAP="${keyboard}"
TOTALVM_LOCALE="${locale_value}"
TOTALVM_TIMEZONE="${timezone_value}"
EOF

rm -f /etc/nologin
systemctl disable totalvm-server-firstboot.service >/dev/null 2>&1 || true
printf '\nReady. Rebooting so you can login as %s.\n\n' "${username}"
sync
systemctl reboot --no-block >/dev/null 2>&1 || reboot || true
sleep 5
FIRSTBOOT
chmod +x /usr/local/sbin/totalvm-server-firstboot

cat > /usr/local/sbin/totalvm-console-select <<'PYSELECT'
#!/usr/bin/env python3
import curses
import sys


def filtered(options, query):
    query = query.casefold()
    if not query:
        return options
    return [item for item in options if query in item.casefold()]


def draw(stdscr, title, default, query, matches, index):
    stdscr.erase()
    height, width = stdscr.getmaxyx()
    stdscr.addstr(1, 2, "Total.js Developer", curses.A_BOLD)
    stdscr.addstr(2, 2, "First-run setup")
    stdscr.hline(3, 2, "-", max(10, width - 4))
    stdscr.addstr(5, 2, title, curses.A_BOLD)
    stdscr.addstr(6, 2, "Type to filter. Use arrows to move. Enter selects. Esc clears.")
    stdscr.addstr(7, 2, "Default: {}".format(default or "(none)"))
    stdscr.addstr(9, 2, "Search: {}".format(query))

    top = 11
    visible = max(4, height - top - 3)
    if matches:
        if index >= len(matches):
            index = len(matches) - 1
        start = max(0, min(index - visible // 2, len(matches) - visible))
        for row, item in enumerate(matches[start:start + visible], start=top):
            selected = start + row - top == index
            marker = "> " if selected else "  "
            attr = curses.A_REVERSE if selected else curses.A_NORMAL
            stdscr.addnstr(row, 2, marker + item, width - 4, attr)
        stdscr.addstr(height - 2, 2, "{} matches".format(len(matches)))
    else:
        stdscr.addstr(top, 2, "No matches. Press Enter to use this text as a custom value.")
    stdscr.refresh()
    return index


def plain_select(title, default, options):
    query = ""
    while True:
        matches = filtered(options, query)
        print("\n{}".format(title), file=sys.stderr)
        print("  Type text to filter, Enter accepts default, exact/custom values are allowed.", file=sys.stderr)
        print("  Default: {}".format(default or "(none)"), file=sys.stderr)
        shown = matches[:12]
        for number, item in enumerate(shown, start=1):
            print("  {:2d}) {}".format(number, item), file=sys.stderr)
        if len(matches) > len(shown):
            print("  ... {} more".format(len(matches) - len(shown)), file=sys.stderr)
        choice = input("Select [{}]: ".format(default or "")).strip()
        if not choice:
            return default
        if choice.isdigit() and 1 <= int(choice) <= len(shown):
            return shown[int(choice) - 1]
        exact = [item for item in options if item == choice]
        if exact:
            return exact[0]
        query = choice
        if not matches:
            return choice


def emit(value, result_path):
    if result_path:
        with open(result_path, "w", encoding="utf-8") as handle:
            handle.write(value + "\n")
    else:
        print(value)


def main(stdscr):
    curses.curs_set(1)
    title = sys.argv[1] if len(sys.argv) > 1 else "Select:"
    default = sys.argv[2] if len(sys.argv) > 2 else ""
    options_file = sys.argv[3] if len(sys.argv) > 3 else ""
    result_file = sys.argv[4] if len(sys.argv) > 4 else ""
    if options_file:
        with open(options_file, "r", encoding="utf-8", errors="replace") as handle:
            options = [line.strip() for line in handle if line.strip()]
    else:
        options = [line.strip() for line in sys.stdin if line.strip()]
    if default and default not in options:
        options.insert(0, default)

    query = ""
    index = 0
    while True:
        matches = filtered(options, query)
        index = draw(stdscr, title, default, query, matches, index)
        key = stdscr.get_wch()
        if key in ("\n", "\r", curses.KEY_ENTER):
            if matches:
                emit(matches[index], result_file)
            elif query:
                emit(query, result_file)
            else:
                emit(default, result_file)
            return
        if key == "\x1b":
            query = ""
            index = 0
        elif key in (curses.KEY_UP,):
            index = max(0, index - 1)
        elif key in (curses.KEY_DOWN,):
            index = min(max(0, len(matches) - 1), index + 1)
        elif key in (curses.KEY_PPAGE,):
            index = max(0, index - 10)
        elif key in (curses.KEY_NPAGE,):
            index = min(max(0, len(matches) - 1), index + 10)
        elif key in (curses.KEY_BACKSPACE, "\b", "\x7f"):
            query = query[:-1]
            index = 0
        elif isinstance(key, str) and key.isprintable():
            query += key
            index = 0


if __name__ == "__main__":
    title_arg = sys.argv[1] if len(sys.argv) > 1 else "Select:"
    default_arg = sys.argv[2] if len(sys.argv) > 2 else ""
    options_arg = sys.argv[3] if len(sys.argv) > 3 else ""
    result_arg = sys.argv[4] if len(sys.argv) > 4 else ""
    try:
        curses.wrapper(main)
    except curses.error:
        if options_arg:
            with open(options_arg, "r", encoding="utf-8", errors="replace") as handle:
                fallback_options = [line.strip() for line in handle if line.strip()]
        else:
            fallback_options = [line.strip() for line in sys.stdin if line.strip()]
        if default_arg and default_arg not in fallback_options:
            fallback_options.insert(0, default_arg)
        emit(plain_select(title_arg, default_arg, fallback_options), result_arg)
PYSELECT
chmod +x /usr/local/sbin/totalvm-console-select

cat > /etc/nologin <<'EOF'
Total.js Developer is waiting for first-run setup on the console.
Create your administrator account there before logging in.
EOF

cat > /etc/systemd/system/totalvm-server-firstboot.service <<'EOF'
[Unit]
Description=Total.js Developer Server first-run setup
DefaultDependencies=no
After=local-fs.target systemd-vconsole-setup.service plymouth-quit.service
Before=getty.target getty@tty1.service ssh.service sshd.service multi-user.target
Conflicts=getty@tty1.service
ConditionPathExists=!/etc/totalvm/firstboot.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/totalvm-server-firstboot
StandardInput=tty-force
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=no
TimeoutSec=0

[Install]
WantedBy=getty.target multi-user.target
EOF

systemctl daemon-reload >/dev/null 2>&1 || true
systemctl enable totalvm-server-firstboot.service >/dev/null 2>&1 || true

echo "[server-console-wizard] done"
