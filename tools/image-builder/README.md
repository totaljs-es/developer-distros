# TotalVM — Image Builder

The native pipeline that turns a stock Linux cloud image into a ready-to-use
**Total.js development environment**, published as a sparse RAW disk inside a
native LZFSE-compressed Apple Archive.

It is built on Apple's **Virtualization framework** — no VMware, VirtualBox,
QEMU runtime, or Docker. The small Swift VM runner here (`totalvm-builder`) is
also the prototype of the VM engine the future TotalVM SwiftUI app will use.

## How it works

```
Ubuntu cloud image (qcow2)
        │  qemu-img convert → sparse RAW, grow to 16G
        ▼
   RAW disk  ──────────────┐
        │                  │ virtiofs: provision/ + assets/
   cloud-init seed (ISO)   │
        ▼                  ▼
  totalvm-builder run  →  Linux VM boots
        │                 cloud-init runs provision/*.sh in order
        │                 (Node, Total.js, Docker, Postgres, Code,
        │                  Flow, Openbox, Total Center)
        ▼                 → poweroff
   provisioned RAM
        │  qemu-img sparse conversion + Apple Archive (LZFSE)
        ▼
  dist/developer-ubuntu/developer.raw.aar + manifest.json
```

The VM **powers itself off** when provisioning finishes; that is how the runner
knows the image is ready.

## Requirements

- macOS 14+ on Apple Silicon
- Xcode / Swift toolchain
- `qemu-img` — `brew install qemu`
- `jq` — `brew install jq`
- `gpg` — `brew install gnupg` (Arch image signature verification)
- `aa` — included with macOS (Apple Archive)

## Build an image

```bash
cd tools/image-builder
scripts/build.sh developer-ubuntu
```

The headless Server Edition uses the same pipeline:

```bash
scripts/build.sh developer-ubuntu-server
```

Arch also has matching desktop/server image IDs:

```bash
scripts/build.sh developer-arch
scripts/build.sh developer-arch-server
```

Outputs land in `dist/developer-ubuntu/`:

- `developer.raw.aar` — the compressed archive containing the sparse disk
- `manifest.json` — filled from `images/<id>/manifest.template.json`

Upload `developer.raw.aar` first and `manifest.json` last. Then verify that the
server exposes the exact artifact described by the manifest:

```bash
scripts/verify-release.sh developer-ubuntu
```

The image starts at 16 GiB and TotalVM expands it to the disk limit selected by
the user. The guest grows its root partition automatically on first boot.

Builder storage can live outside the repository when local space is tight:

```bash
TOTALVM_WORK_DIR=/Volumes/Build/TotalVM/work \
TOTALVM_CACHE_DIR=/Volumes/Build/TotalVM/cache \
scripts/build.sh developer-ubuntu
```

The first run downloads the Ubuntu cloud image into `build/cache/` (reused on
later builds). Watch the serial console for cloud-init progress.

## Layout

```
tools/image-builder/
  Package.swift                      Swift VM runner package
  totalvm-builder.entitlements       com.apple.security.virtualization
  Sources/totalvm-builder/           runner source (main.swift, VMRunner.swift)
  scripts/
    lib.sh        shared helpers
    build.sh      end-to-end build
    package.sh    sparse RAW + Apple Archive + manifest
  images/developer-ubuntu/
    image.json                 build + runtime config
    manifest.template.json     published manifest skeleton
    cloud-init/                user-data + meta-data (NoCloud seed)
    provision/                 00-base … 90-cleanup (run in order in the guest)
    assets/                    wallpapers, Total Center app (optional)
  build/    (gitignored)       cache + work disks
  dist/     (gitignored)       packaged images
```

## Run the VM runner directly

```bash
.build/release/totalvm-builder run \
    --disk build/work/developer-ubuntu.raw \
    --seed build/work/seed.iso \
    --share provision=images/developer-ubuntu/provision \
    --share assets=images/developer-ubuntu/assets \
    --cpus 4 --memory 4096
```

## Add a new image

1. Copy `images/developer-ubuntu/` to `images/<your-id>/`.
2. Edit `image.json` (base image URL, disk size, name).
3. Adjust `provision/*.sh` for the software you want.
4. `scripts/build.sh <your-id>`.

## Publishing

Upload `dist/<id>/developer.raw.aar` and `manifest.json` to the matching directory
on `totalvm.totaljs.es`, then publish the updated catalog. No app update is
needed to publish a new image.
