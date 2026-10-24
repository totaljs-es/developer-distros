#!/usr/bin/expect -f
# Install the Arch Linux ARM base by booting the Archboot ISO under the
# totalvm-builder runner (Apple Virtualization framework — no QEMU). The blank
# RAW is the install target; the ISO is attached read-only and the firmware
# boots it via the EFI removable-media fallback path.
set timeout 2400
if {$argc != 7} {
    puts stderr "usage: arch-install-vz-expect.tcl <runner> <raw> <iso> <cpus> <memory> <rootfs-dir> <installer-script>"
    exit 64
}
lassign $argv runner raw iso cpus memory rootfsdir script
# Archboot ships almost no userland; hand the installer over as \xHH escapes and
# rebuild it with Bash's printf, exactly as the old QEMU path did.
set payload [exec /usr/bin/python3 -c {import pathlib,sys; print(''.join(f'\\x{b:02x}' for b in pathlib.Path(sys.argv[1]).read_bytes()))} $script]

spawn -noecho $runner run \
    --disk $raw --seed $iso \
    --share rootfs=$rootfsdir \
    --cpus $cpus --memory $memory --interactive

expect {
    -re {archboot[^#]*#} {}
    timeout { puts stderr "Archboot did not reach its root shell"; exit 2 }
    eof { puts stderr "Archboot stopped before installation"; exit 2 }
}
# Reconstruct the installer, mount the host rootfs share (best effort — the
# installer falls back to the mirror if virtiofs is unavailable), then run it.
send -- "printf '%b' '$payload' > /tmp/totaljs-install-base.sh; chmod +x /tmp/totaljs-install-base.sh; modprobe virtiofs 2>/dev/null; mkdir -p /mnt/rootfs; mount -t virtiofs rootfs /mnt/rootfs 2>/dev/null || true; ROOTFS_LOCAL=/mnt/rootfs/ArchLinuxARM-aarch64-latest.tar.gz bash /tmp/totaljs-install-base.sh\r"
expect {
    "TOTALJS_ARCH_BASE_READY" { set ready 1 }
    "TOTALJS_ARCH_BASE_FAILED" { puts stderr "Arch base installation failed"; exit 3 }
    timeout { puts stderr "Arch base installation timed out"; exit 3 }
    eof { puts stderr "Archboot stopped before reporting success"; exit 3 }
}
expect eof
exit 0
