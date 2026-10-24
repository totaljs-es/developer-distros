# AGENTS.md

Guidance for AI coding agents that work on this repository.

## Project

Official Total.js Developer Distros: Linux environments for Total.js development, on Ubuntu LTS and Arch, with the same desktop on both. The repository holds the recipes that build their images, the scripts that publish the Total.js package repository and the catalog that TotalVM reads. Today it builds arm64 images on macOS; amd64 ISOs built in GitHub Actions are planned.

## Layout

- `tools/image-builder/` builds an image: `scripts/build.sh <id>`, a Swift runner in `Sources/` that boots the VM with Apple's Virtualization framework, and one recipe per distro in `images/<id>/` (`image.json`, `provision/*.sh` run in order inside the guest, `cloud-init/`, `assets/`).
- `packages/<name>/` is the source of one package of the Total.js layer: `control`, the maintainer scripts and `files/` (what it installs). `tools/package-repo/build.sh` builds every one of them into the repository, and `tools/package-repo/test-install.sh` installs them in a clean Ubuntu (the workflow `package-repo` runs it in a container for 24.04 and 26.04). The design is `docs/layer.md`.
- `tools/package-repo/` builds and signs the APT and Pacman repository (`build.sh`) and prepares the branch `pages` that serves it (`publish-pages.sh`). The key of Total.js signs it on a maintainer's computer and is never in GitHub; the workflow `package-repo` tests the build with a throwaway key. Its scripts assume the layout of this repository.
- `iso/ubuntu/` builds the installable ISO for amd64 by remastering the official Ubuntu `live-server` ISO (`build-iso.sh`) and tests it by installing and booting it in QEMU (`test-install.sh`); `.github/workflows/iso-ubuntu.yml` runs both. The seed in `iso/ubuntu/seed-ci/` is only for that test.
- `manifests/` is the catalog: `index.json` and `manifests/<id>/manifest.json`. `size` and `sha256` are filled when an image is published.
- `shared/` is the Total.js layer common to every distro. `shared/branding/mascot.png` is the official mascot (Tux hugging the Total.js logo): use it for anything visual (README, boot screen, login, wallpapers, icons) and do not draw another. The rest of the layer receives files from the recipes one piece at a time.
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
