#!/usr/bin/expect -f
set timeout 14400
if {$argc != 6} {
    puts stderr "usage: arch-provision-expect.tcl <runner> <raw> <cpus> <memory> <provision-dir> <assets-dir>"
    exit 64
}
lassign $argv runner raw cpus memory provision assets

spawn -noecho $runner run --disk $raw --cpus $cpus --memory $memory \
    --share provision=$provision --share assets=$assets --interactive

set reboots 0
while {1} {
    expect {
        -re {login: ?$} {}
        timeout { puts stderr "Installed Arch did not reach its login console"; exit 4 }
        eof { puts stderr "Installed Arch stopped before provisioning"; exit 4 }
    }
    send -- "root\r"
    expect {
        -re {Password: ?$} { send -- "root\r" }
        -re {root@[^#]+# ?$} {}
        timeout { puts stderr "Installed Arch did not accept the root login"; exit 4 }
    }
    expect {
        -re {root@[^#]+# ?$} {}
        timeout { puts stderr "Installed Arch did not open its root shell"; exit 4 }
    }

    # The result token is assembled at runtime so the success literal never
    # appears in the echoed command line and cannot create a false positive.
    send -- "mkdir -p /mnt/provision /mnt/assets; mountpoint -q /mnt/provision || mount -t virtiofs provision /mnt/provision; mountpoint -q /mnt/assets || mount -t virtiofs assets /mnt/assets; TOTALVM_ASSETS=/mnt/assets bash /mnt/provision/run.sh; rc=\$?; printf 'TOTALVM_PROV_%s\\n' \"\$(\[ \$rc -eq 0 ] && echo OKOK || echo FAILFAIL)\"; sync; poweroff\r"
    expect {
        "TOTALVM_PROV_OKOK" { break }
        "TOTALVM_PROV_FAILFAIL" { puts stderr "Arch provisioning failed"; exit 5 }
        "TOTALVM_PROV_REBOOT" {
            incr reboots
            if {$reboots > 2} {
                puts stderr "Arch provisioning requested too many reboots"
                exit 5
            }
            puts "Arch provisioning is resuming after a required reboot"
            continue
        }
        timeout { puts stderr "Arch provisioning timed out"; exit 5 }
        eof { puts stderr "Arch stopped before reporting provisioning success"; exit 5 }
    }
}
expect eof
exit 0
