#!/usr/bin/expect -f
# Boot a disposable release-image clone and verify the installed system from
# its serial console. The caller supplies the virtiofs /www share.
set timeout 900
if {$argc != 8} {
    puts stderr "usage: smoke-test-expect.tcl <runner> <raw-clone> <www-share> <distro> <user> <password> <memory> <rescue-iso|->"
    exit 64
}
lassign $argv runner raw www distro user password memory rescue

if {$rescue ne "-"} {
    file delete -force "${raw}.nvram"
    spawn -noecho $runner run --disk $raw --seed $rescue --boot-seed --cpus 2 --memory 4096 --interactive
    expect {
        -re {archboot[^#]*#} {}
        timeout { puts stderr "${distro}: rescue environment did not reach its root shell"; exit 2 }
        eof { puts stderr "${distro}: rescue environment stopped unexpectedly"; exit 2 }
    }
    # Test-only root password and serial console. The production RAW is never
    # touched because the caller passes an APFS clone.
    send -- {set -e; rootdev="$(blkid -L TOTALJS_ARCH 2>/dev/null || blkid -L cloudimg-rootfs 2>/dev/null || true)"; test -n "$rootdev"; mkdir -p /mnt/guest; mount "$rootdev" /mnt/guest; test -f /mnt/guest/etc/shadow; sed -i 's|^root:[^:]*:|root:$6$totaljstest$lQmWtiFyrWpoKSlbkHi9O0Luh2gFku8wT9NBwy290r/XhofJ0qSD4fk61Y7V4cmjSz83RyDeQy58ZPIgFbfIe.:|' /mnt/guest/etc/shadow; rm -f /mnt/guest/etc/systemd/system/serial-getty@hvc0.service /mnt/guest/etc/systemd/system/getty@hvc0.service; mkdir -p /mnt/guest/etc/systemd/system/getty.target.wants; ln -sf /lib/systemd/system/serial-getty@.service /mnt/guest/etc/systemd/system/getty.target.wants/serial-getty@hvc0.service; umount /mnt/guest; poweroff}
    send -- "\r"
    expect eof
}

file delete -force "${raw}.nvram"
spawn -noecho $runner run --disk $raw --share "www=$www" --cpus 4 --memory $memory --interactive

expect {
    -re {Select \[[^\]]+\]: ?$} {
        send -- "\r"
        exp_continue
    }
    -re {Username: ?$} {
        send -- "$user\r"
        expect {
            -re {(Password|Contraseña): ?$} { send -- "$password\r" }
            timeout { puts stderr "${distro}: first-run password prompt did not appear"; exit 3 }
            eof { puts stderr "${distro}: guest stopped during first-run setup"; exit 3 }
        }
        expect {
            -re {Confirm password: ?$} { send -- "$password\r" }
            timeout { puts stderr "${distro}: first-run confirm prompt did not appear"; exit 3 }
            eof { puts stderr "${distro}: guest stopped during first-run setup"; exit 3 }
        }
        exp_continue
    }
    -re {login: ?$} {}
    timeout { puts stderr "${distro}: serial login did not appear"; exit 2 }
    eof { puts stderr "${distro}: guest stopped before serial login"; exit 2 }
}
send -- "$user\r"
expect {
    -re {(Password|Contraseña): ?$} { send -- "$password\r" }
    -re {[#$] ?$} {}
    timeout { puts stderr "${distro}: password prompt did not appear"; exit 3 }
}
expect {
    -re {[#$] ?$} {}
    timeout { puts stderr "${distro}: login did not open a shell"; exit 3 }
}

# Do not let expect mistake diagnostic strings in the echoed command for real
# guest output. The terminal settings live only in this disposable session.
send -- "stty -echo\r"
after 500

# Keep the diagnostic in one shell command so it works before the first-run
# wizard has replaced the bootstrap account. The success token is assembled
# inside the guest, preventing expect from matching the echoed command itself.
if {$distro eq "developer-ubuntu-server" || $distro eq "developer-arch-server"} {
    set checks {set -eu; fail(){ echo "SMOKE_FAIL:$*"; exit 1; }; wait_active(){ unit="$1"; i=0; while [ "$i" -lt 90 ]; do systemctl is-active --quiet "$unit" && return 0; sleep 2; i=$((i+1)); done; systemctl --no-pager --full status "$unit" || true; fail "$unit is not active"; }; wait_any_active(){ i=0; while [ "$i" -lt 90 ]; do for unit in "$@"; do systemctl is-active --quiet "$unit" && return 0; done; sleep 2; i=$((i+1)); done; for unit in "$@"; do systemctl --no-pager --full status "$unit" || true; done; fail "$* are not active"; }; wait_http(){ url="$1"; pattern="$2"; i=0; while [ "$i" -lt 60 ]; do timeout 5 curl -fsS "$url" 2>/dev/null | grep -q "$pattern" && return 0; sleep 1; i=$((i+1)); done; fail "$url did not return $pattern"; }; wait_host(){ host="$1"; i=0; while [ "$i" -lt 60 ]; do timeout 5 curl -fsS -H "Host: ${host}" http://127.0.0.1/ >/dev/null 2>&1 && return 0; sleep 1; i=$((i+1)); done; fail "${host} did not answer through proxy"; }; wait_any_active ssh sshd; wait_any_active systemd-networkd NetworkManager; wait_active systemd-resolved; wait_active totalvm-growroot; ip route | grep -q '^default ' || fail "default route is missing"; timeout 10 getent ahostsv4 totalvm.totaljs.es >/dev/null 2>&1 || fail "DNS resolution failed"; root_options="$(findmnt -n -o OPTIONS /)"; printf '%s\n' "$root_options" | tr ',' '\n' | grep -qx discard && fail "root filesystem is mounted with discard"; grep -q 'TOTALVM_ID="__DISTRO__"' /etc/totalvm/release || fail "release metadata is wrong"; test -s /etc/totalvm/firstboot.done || fail "first-run marker is missing"; ! id totaljs >/dev/null 2>&1 || fail "bootstrap totaljs user still exists"; grep -q "^${SUDO_USER:-$USER} " /etc/sudoers.d/10-totalvm-admin || fail "user-specific sudoers entry is missing"; grep -q 'TOTALVM_LOCALE=' /etc/totalvm/firstboot.done || fail "regional setup marker is missing"; node --version >/dev/null || fail "node is missing"; npm --version >/dev/null || fail "npm is missing"; test -x /usr/local/bin/totalctl || fail "totalctl is missing"; test -x /usr/local/bin/totalfetch || fail "totalfetch is missing"; test -d /srv/total/apps || fail "apps directory is missing"; if [ "__DISTRO__" = "developer-ubuntu-server" ] || [ "__DISTRO__" = "developer-arch-server" ]; then for unit in docker totalvm-www-seed totalvm-proxy totalvm-code totalvm-flow totaljs-postgres totalcenter; do wait_active "$unit"; done; curl -fsS http://127.0.0.1:8010/healthz >/dev/null || fail "Total Center health check failed"; id -nG "${SUDO_USER:-$(id -un)}" | tr ' ' '\n' | grep -qx docker || fail "admin user is not in docker group"; test -d /www/www || fail "/www/www is missing"; docker image inspect nginxproxy/nginx-proxy:1.8.0 totalplatform/code:latest totalplatform/flow:latest postgres:17-alpine dpage/pgadmin4:latest totalplatform/run:npm >/dev/null || fail "required Docker image is missing"; wait_http "http://127.0.0.1/" 'Total.js Code'; wait_host flow.totaljs.developer; fi; ! pgrep -x Xorg >/dev/null || fail "Xorg should not be running"; totalctl new smoketest; totalctl start smoketest; wait_active total-smoketest.service; port="$(cat /srv/total/apps/smoketest/.port)"; wait_http "http://127.0.0.1:${port}/healthz" '"app":"smoketest"'; test "$(df --output=avail -m / | tail -1)" -gt 512 || fail "less than 512 MiB free on root"; printf 'TOTALJS_SMOKE_%s\n' PASSED; sync; poweroff}
    regsub -all __DISTRO__ $checks $distro checks
} else {
    set checks {set -eu; fail(){ echo "SMOKE_FAIL:$*"; exit 1; }; wait_active(){ unit="$1"; i=0; while [ "$i" -lt 90 ]; do systemctl is-active --quiet "$unit" && return 0; sleep 2; i=$((i+1)); done; systemctl --no-pager --full status "$unit" || true; fail "$unit is not active"; }; wait_dns(){ i=0; while [ "$i" -lt 30 ]; do getent ahostsv4 totalvm.totaljs.es >/dev/null 2>&1 && return 0; sleep 1; i=$((i+1)); done; return 1; }; for unit in NetworkManager docker lightdm totalvm-www-seed totalvm-proxy totalvm-code totalvm-flow totaljs-postgres totalcenter totaljs-dnsmasq; do wait_active "$unit"; done; systemctl start totalvm-dns; test "$(systemctl show -p Result --value totalvm-dns)" = success || fail "totalvm-dns did not finish successfully"; wait_dns || fail "DNS resolution failed"; test -s /www/.totalvm/network.json || fail "host network publication is missing"; grep -q '"domain":"totaljs.developer"' /www/.totalvm/network.json || fail "host network publication has the wrong domain"; root_options="$(findmnt -n -o OPTIONS /)"; printf '%s\n' "$root_options" | tr ',' '\n' | grep -qx discard && fail "root filesystem is mounted with discard"; systemctl is-active --quiet graphical.target || fail "graphical target is not active"; pgrep -x Xorg >/dev/null || fail "Xorg is not running"; ip route | grep -q '^default ' || fail "default route is missing"; modprobe virtio_snd || fail "virtio_snd could not be loaded"; aplay -l | grep -qi virtio || fail "VirtIO ALSA card is missing"; pgrep -x pipewire >/dev/null || fail "PipeWire is not running"; pgrep -x wireplumber >/dev/null || fail "WirePlumber is not running"; pgrep -x pasystray >/dev/null || fail "pasystray is not running"; browser="$(command -v chromium || command -v firefox || true)"; test -n "$browser" || fail "web browser is missing"; "$browser" --version >/dev/null 2>&1 || fail "web browser cannot start"; curl -fsS http://127.0.0.1:8010/healthz >/dev/null || fail "Total Center health check failed"; docker image inspect nginxproxy/nginx-proxy:1.8.0 totalplatform/code:latest totalplatform/flow:latest postgres:17-alpine dpage/pgadmin4:latest totalplatform/run:npm >/dev/null || fail "required Docker image is missing"; test "$(df --output=avail -m / | tail -1)" -gt 512 || fail "less than 512 MiB free on root"; printf 'TOTALJS_SMOKE_%s\n' PASSED; sync; poweroff}
}

send -- "cat >/tmp/totalvm-smoke.sh <<'TOTALVM_SMOKE'\r$checks\rTOTALVM_SMOKE\rchmod +x /tmp/totalvm-smoke.sh\r"
expect {
    -re {[#$] ?$} {}
    timeout { puts stderr "${distro}: could not stage smoke script"; exit 4 }
    eof { puts stderr "${distro}: guest stopped while staging smoke script"; exit 4 }
}

if {$user eq "root"} {
    send -- "bash /tmp/totalvm-smoke.sh\r"
} else {
    # The bootstrap Ubuntu account deliberately uses the same temporary
    # password for sudo; the first-run wizard replaces it.
    send -- "printf '%s\\n' '$password' | sudo -S bash /tmp/totalvm-smoke.sh\r"
}

expect {
    "TOTALJS_SMOKE_PASSED" {}
    -re {SMOKE_FAIL:([^\r\n]+)} { puts stderr "${distro}: $expect_out(0,string)"; exit 4 }
    timeout { puts stderr "${distro}: release checks timed out"; exit 4 }
    eof { puts stderr "${distro}: guest stopped before checks completed"; exit 4 }
}
expect eof
exit 0
