#!/usr/bin/expect -f
# Destructive update/reboot smoke test for a disposable clone of an Arch RAW.
set timeout 7200
if {$argc != 5} {
    puts stderr "usage: arch-update-smoke-expect.tcl <runner> <raw-clone> <rescue-iso> <cpus> <memory>"
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

send -- {set -e; rootdev="$(blkid -L TOTALJS_ARCH)"; mkdir -p /mnt/arch; mount "$rootdev" /mnt/arch; sed -i 's|^root:[^:]*:|root:$6$totaljstest$lQmWtiFyrWpoKSlbkHi9O0Luh2gFku8wT9NBwy290r/XhofJ0qSD4fk61Y7V4cmjSz83RyDeQy58ZPIgFbfIe.:|' /mnt/arch/etc/shadow; rm -f /mnt/arch/etc/systemd/system/serial-getty@hvc0.service /mnt/arch/etc/systemd/system/getty@hvc0.service; mkdir -p /mnt/arch/etc/systemd/system/getty.target.wants; ln -sf /lib/systemd/system/serial-getty@.service /mnt/arch/etc/systemd/system/getty.target.wants/serial-getty@hvc0.service; umount /mnt/arch; poweroff}
send -- "\r"
expect eof

proc boot_guest {runner raw cpus memory} {
    global spawn_id
    file delete -force "${raw}.nvram"
    spawn -noecho $runner run --disk $raw --cpus $cpus --memory $memory --interactive
}

proc login_root {} {
    expect {
        -re {login: ?$} {}
        timeout { puts stderr "Arch did not reach its serial login"; exit 3 }
        eof { puts stderr "Arch stopped before login"; exit 3 }
    }
    send -- "root\r"
    expect {
        -re {Password: ?$} { send -- "root\r" }
        timeout { puts stderr "Arch did not request the diagnostic password"; exit 3 }
    }
    expect {
        -re {\[root@[^#]+# ?$} {}
        timeout { puts stderr "Arch did not open its root shell"; exit 3 }
    }
}

boot_guest $runner $raw $cpus $memory
login_root
send -- "for i in \$(seq 1 30); do getent ahostsv4 mirror.archlinuxarm.org >/dev/null 2>&1 && break; systemctl restart totaljs-dns-refresh.service 2>/dev/null || true; sleep 2; done; getent ahostsv4 mirror.archlinuxarm.org >/dev/null 2>&1 && pacman -Syu --noconfirm && mkinitcpio -P; rc=\$?; printf 'TOTALJS_ARCH_UPDATE_%s\\n' \"\$(\[ \$rc -eq 0 ] && echo READY || echo FAILED)\"; sync; \[ \$rc -eq 0 ] && reboot\r"
expect {
    "TOTALJS_ARCH_UPDATE_READY" {}
    "TOTALJS_ARCH_UPDATE_FAILED" { puts stderr "Arch package upgrade failed"; exit 4 }
    timeout { puts stderr "Arch package upgrade timed out"; exit 4 }
    eof { puts stderr "Arch stopped during package upgrade"; exit 4 }
}

login_root
send -- "opts=\$(findmnt -n -o OPTIONS /); test -s /boot/initramfs-linux.img && ! printf '%s' \"\$opts\" | tr ',' '\\n' | grep -qx discard && systemctl is-active --quiet lightdm NetworkManager docker && getent ahostsv4 mirror.archlinuxarm.org >/dev/null && modprobe virtio_snd && aplay -l | grep -qi virtio; rc=\$?; printf 'TOTALJS_ARCH_UPDATE_%s\\n' \"\$(\[ \$rc -eq 0 ] && echo VERIFIED || echo FAILED)\"; sync; poweroff\r"
expect {
    "TOTALJS_ARCH_UPDATE_VERIFIED" {}
    "TOTALJS_ARCH_UPDATE_FAILED" { puts stderr "Arch failed its post-update health checks"; exit 5 }
    timeout { puts stderr "Arch did not survive the update reboot"; exit 5 }
    eof { puts stderr "Arch stopped before update verification"; exit 5 }
}
expect eof
exit 0
