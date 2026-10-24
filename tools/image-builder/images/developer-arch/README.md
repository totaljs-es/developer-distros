# Total.js Developer (Arch Linux)

The Arch image provides the same Total.js Developer experience as Ubuntu:
Openbox desktop, shared wallpapers and menus, Code, Flow, Docker
services, Total.js Center, first-run wizard, clipboard integration and local DNS.

The complete image is built non-interactively:

```bash
cd tools/image-builder
scripts/build.sh developer-arch
```

The whole pipeline runs on Apple's Virtualization framework — no QEMU. The
builder:

1. Resolves and downloads the current Archboot AArch64 ISO.
2. Downloads and verifies the official Arch Linux ARM generic root filesystem.
3. Creates a 15 GB sparse RAW, then boots the Archboot ISO under Apple
   Virtualization (the blank RAW is the install target) and installs a portable
   UEFI base: GPT + ESP, the Arch Linux ARM rootfs, and systemd-boot.
4. Boots the installed disk under Apple Virtualization and applies the shared
   Total.js assets (provisioning).
5. Produces `dist/developer-arch/developer.raw.aar` and `manifest.json`.

> Archboot's published ISO is a minimal environment that stores packages in
> pacman's DB with their binaries stripped, so the installer reinstalls the few
> tools it needs (`coreutils gptfdisk dosfstools e2fsprogs util-linux shadow`)
> over its working NAT network before partitioning.

For a quick uncompressed test build:

```bash
scripts/build.sh developer-arch --raw-only
```

The published image defaults to a 15 GB virtual limit. TotalVM restores the
sparse RAW from its Apple Archive and expands it to the capacity selected at
installation time, while the guest grows its root filesystem on first boot.
Empty capacity does not consume host storage.

Manual helpers remain available for diagnosis (all Apple Virtualization):

```bash
scripts/arch-prepare.sh developer-arch      # download ISO + rootfs, blank RAW
scripts/arch-run-totalvm.sh developer-arch  # boot the installed RAW to a console
```
