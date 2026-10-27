# AGENTS.md

Guidance for AI coding agents that work on this repository.

## Project

Official Total.js Developer Distros: Linux environments for Total.js development, on Ubuntu LTS and Arch, with the same desktop on both. The repository holds the recipes that build their images, the scripts that publish the Total.js package repository and the catalog that TotalVM reads. The Total.js layer is a set of packages (`packages/`) in a signed APT repository, installed on Ubuntu 26.04 LTS by a seed image that travels next to the official Ubuntu ISO (`iso/ubuntu/`). The recipes in `tools/image-builder/` build arm64 images for TotalVM on macOS.

## Layout

- `tools/image-builder/` builds an image: `scripts/build.sh <id>`, a Swift runner in `Sources/` that boots the VM with Apple's Virtualization framework, and one recipe per distro in `images/<id>/` (`image.json`, `provision/*.sh` run in order inside the guest, `cloud-init/`, `assets/`).
- `packages/<name>/` is the source of one package of the Total.js layer: `control`, the maintainer scripts and `files/` (what it installs). `tools/package-repo/build.sh` builds every one of them into the repository, and `tools/package-repo/test-install.sh` installs them in a clean Ubuntu (the workflow `package-repo` runs it in a container of Ubuntu 26.04, the series of the repository). The design is `docs/layer.md`.
- `tools/package-repo/` builds and signs the APT and Pacman repository (`build.sh`) and prepares the branch `pages` that serves it (`publish-pages.sh`). The key of Total.js signs it on a maintainer's computer and is never in GitHub; the workflow `package-repo` tests the build with a throwaway key. Its scripts assume the layout of this repository.
- `iso/ubuntu/` has the installer. `build-iso.sh` remasters the official `live-server` ISO of Ubuntu with our seed and a boot menu (desktop and server edition): that is **the ISO of Total.js Developer, an Ubuntu remix**, published by `.github/workflows/release-iso.yml` on a tag `v*`, together with two seed images. It carries the marks of Canonical, so **its publication depends on the approval that Canonical was asked for** (`docs/legal.md` says the state: read it before changing how it is named or published, and never call it "Ubuntu"). `build-seed.sh` makes the seed images (a few hundred kilobytes with the volume label `CIDATA`, with nothing of Ubuntu inside) that go next to the **unmodified** official ISO, from `seed-image/user-data.in` and `install-layer.sh`. `test-install.sh` installs and boots an ISO in QEMU (the remastered one, and the official one with a seed), and `.github/workflows/iso-ubuntu.yml` runs the tests. `seed-ci/` and `seed-ci-layer/` are the seeds of those tests.
- `iso/own/` builds our own live image from the packages of Ubuntu (`build.sh`, in a privileged container of Ubuntu 26.04: `debootstrap`, `live-boot`, a squashfs and `grub-mkrescue`), with our identity and no marks of Canonical, and `test-boot.sh` starts it in QEMU with BIOS and UEFI; `.github/workflows/iso-own.yml` runs both only when manually dispatched. This is an experimental prototype, not part of the published ISO pipeline.
- `manifests/` is the catalog: `index.json` and `manifests/<id>/manifest.json`. `size` and `sha256` are filled when an image is published.
- `shared/` is the Total.js layer common to every distro. `shared/plymouth/` has the boot splash (a Plymouth `script` theme in `totaljs/`; the images come from `generate.py` and `export.sh`, and `preview.py` draws the movement of the script on a sheet: keep it in step with the script). `shared/wallpapers/` has the wallpapers: they are drawn by `generate.py` and exported by `export.sh`; change the generator and export, never the SVG or the JPEG by hand. `shared/branding/logo-totaljs.svg` is the official logo and `shared/branding/mascot.png` is the legacy Tux artwork. Toto, the European red fox mascot of Spanish Total.js, lives in `shared/branding/toto/`: use these official poses for welcome/help, with attribution and the included proprietary license. Keep the Total.js logo for system icons and the boot splash; do not redraw either character. The rest of the layer receives files from the recipes one piece at a time.
- `scripts/check.js` is the check that runs in `.github/workflows/check.yml`.

## Commands

```bash
node scripts/check.js                    # JSON, catalog and recipes agree, shell syntax
cd tools/image-builder && scripts/build.sh developer-ubuntu    # needs macOS on Apple Silicon
```

## Conventions

- **Never customize Ubuntu or Arch directly.** Everything that makes it a Total.js distro goes in the shared layer, and the two distros must look and behave the same.
- Shell scripts use `set -euo pipefail`, are idempotent (a provisioning step may run twice) and must not touch the user's projects or home-directory configuration.
- A provisioning script that runs inside the image is numbered (`00-base.sh`, `10-node-totaljs.sh`...) and runs in that order.
- The passwords that exist while an image is built are temporary or hashes of discarded random secrets, and the first-run wizard sets the real ones. Never add a permanent or shared password, and never commit a key, a token or the private signing key of the package repository (it lives outside the repository).

## Pitfalls

- Do not commit images, disks, ISOs or built packages (`*.raw`, `*.aar`, `*.iso`, `*.deb`, `*.pkg.tar.zst`); `.gitignore` lists them. Images go to GitHub Releases.
- `tools/package-repo/build.sh` writes into `tools/image-builder/images/developer-ubuntu/assets/`: that is why the two folders stay together.
- An image needs minutes to hours to build and a Mac with Apple Silicon: say which checks you ran and which you could not run.
