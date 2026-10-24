#!/usr/bin/expect -f
# Destructive update/reboot smoke test for a disposable clone of an Ubuntu RAW.
set timeout 7200
if {$argc != 5} {
    puts stderr "usage: ubuntu-update-smoke-expect.tcl <runner> <raw-clone> <rescue-iso> <cpus> <memory>"
    exit 64
}
lassign $argv runner raw rescue cpus memory

file delete -force "${raw}.nvram"
spawn -noecho $runner run --disk $raw --seed $rescue --boot-seed --cpus $cpus --memory $memory --interactive
expect {
    -re {archboot[^#]*#} {}
    timeout { puts stderr "Archboot rescue did not reach its root shell"; exit 2 }
    eof { puts stderr "Archboot rescue stopped unexpectedly"; exit 2 }
}

# Enable a temporary root console on the clone. The production image is never
# modified: callers must pass an APFS clone made specifically for this test.
# The rescue ISO is vda because --boot-seed presents it first; the cloned
# Ubuntu disk is therefore vdb. Archboot intentionally strips chpasswd and
# sync, so write a test-only root hash directly and rely on clean unmount.
send -- {mkdir -p /mnt/ubuntu; mount /dev/vdb1 /mnt/ubuntu; sed -i 's|^root:[^:]*:|root:$6$totaljstest$lQmWtiFyrWpoKSlbkHi9O0Luh2gFku8wT9NBwy290r/XhofJ0qSD4fk61Y7V4cmjSz83RyDeQy58ZPIgFbfIe.:|' /mnt/ubuntu/etc/shadow; rm -f /mnt/ubuntu/etc/systemd/system/serial-getty@hvc0.service /mnt/ubuntu/etc/systemd/system/getty@hvc0.service; mkdir -p /mnt/ubuntu/etc/systemd/system/getty.target.wants; ln -sf /lib/systemd/system/serial-getty@.service /mnt/ubuntu/etc/systemd/system/getty.target.wants/serial-getty@hvc0.service; umount /mnt/ubuntu; poweroff}
send -- "\r"
expect eof

file delete -force "${raw}.nvram"
spawn -noecho $runner run --disk $raw --cpus $cpus --memory $memory --interactive

proc login_root {} {
    expect {
        -re {login: ?$} {}
        timeout { puts stderr "Ubuntu did not reach its serial login"; exit 3 }
        eof { puts stderr "Ubuntu stopped before login"; exit 3 }
    }
    send -- "root\r"
    expect {
        -re {Password: ?$} { send -- "root\r" }
        -re {root@[^#]+# ?$} {}
        timeout { puts stderr "Ubuntu did not accept the diagnostic root login"; exit 3 }
    }
    expect {
        -re {root@[^#]+# ?$} {}
        timeout { puts stderr "Ubuntu did not open its root shell"; exit 3 }
    }
}

login_root
# Refuse stale package lists: this only counts when DNS and the Ubuntu archive
# are genuinely reachable. Rebuild initramfs and GRUB before the test reboot.
send -- "export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a; for i in \$(seq 1 30); do getent ahostsv4 ports.ubuntu.com >/dev/null 2>&1 && break; systemctl restart totaljs-dns-refresh.service 2>/dev/null || true; sleep 2; done; getent ahostsv4 ports.ubuntu.com >/dev/null 2>&1 && rm -rf /var/lib/apt/lists/* && apt-get update && test -s /var/lib/apt/lists/ports.ubuntu.com_ubuntu-ports_dists_noble-updates_InRelease && apt-get dist-upgrade -y && update-initramfs -u -k all && update-grub; rc=\$?; printf 'TOTALJS_UPDATE_%s\\n' \"\$(\[ \$rc -eq 0 ] && echo READY || echo FAILED)\"; sync; \[ \$rc -eq 0 ] && reboot\r"
expect {
    "TOTALJS_UPDATE_READY" {}
    "TOTALJS_UPDATE_FAILED" { puts stderr "Ubuntu package upgrade failed"; exit 4 }
    timeout { puts stderr "Ubuntu package upgrade timed out"; exit 4 }
    eof { puts stderr "Ubuntu stopped during package upgrade"; exit 4 }
}

login_root
send -- "uname -r; systemctl --version | head -1; findmnt -n -o SOURCE,FSTYPE,OPTIONS /; opts=\$(findmnt -n -o OPTIONS /); test -s /boot/initrd.img-\$(uname -r) && ! printf '%s' \"\$opts\" | tr ',' '\\n' | grep -qx discard && systemctl is-active --quiet lightdm NetworkManager docker && getent ahostsv4 ports.ubuntu.com >/dev/null; rc=\$?; printf 'TOTALJS_UPDATE_%s\\n' \"\$(\[ \$rc -eq 0 ] && echo VERIFIED || echo FAILED)\"; sync; poweroff\r"
expect {
    "TOTALJS_UPDATE_VERIFIED" {}
    "TOTALJS_UPDATE_FAILED" { puts stderr "Ubuntu failed its post-update health checks"; exit 5 }
    timeout { puts stderr "Ubuntu did not survive the update reboot"; exit 5 }
    eof { puts stderr "Ubuntu stopped before update verification"; exit 5 }
}
expect eof
exit 0
