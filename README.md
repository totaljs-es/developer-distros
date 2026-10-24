# Total.js Developer Distros

Official Linux environments for Total.js development: **Ubuntu LTS** and **Arch**, with the same desktop, the same tools and the same first-run experience on both. Everything a developer needs is installed: Node.js, npm, Git, Docker, PostgreSQL, an Nginx proxy, Total.js, the Total.js CLI, Code, Flow, Firefox and SSH.

The desktop belongs to Total.js, not to Ubuntu or Arch. The operating system is only the foundation: the distros are customized only through the shared Total.js layer, never by patching Ubuntu or Arch themselves.

> **Status: work in progress, private.** The recipes below build the images for [TotalVM](https://totalvm.totaljs.es) on a Mac with Apple Silicon (arm64). The installable ISOs for amd64 and the GitHub Actions builds are the next step and do not exist yet. The repository will be made public when the first ISO is built.

## The distros

| Id | What it is |
|---|---|
| `developer-ubuntu` | Desktop (Openbox) on Ubuntu LTS |
| `developer-ubuntu-server` | Headless server edition on Ubuntu LTS |
| `developer-arch` | Desktop (Openbox) on Arch |
| `developer-arch-server` | Headless server edition on Arch |

## What is in this repository

```text
tools/image-builder/   builds an image from a stock cloud image or rootfs (macOS, Apple Virtualization)
  images/<id>/         the recipe of each distro: image.json, provision/*.sh, cloud-init, assets
tools/package-repo/    builds and signs the APT and Pacman repository with the Total.js packages
manifests/             the catalog that TotalVM reads: index.json and one manifest.json per image
shared/                the Total.js layer common to every distro (being moved here from the recipes)
scripts/check.js       the checks that run on every change
```

`tools/image-builder/README.md` explains how an image is built today, and `tools/package-repo/README.md` how the package repository is made and signed.

## Build an image (today)

On macOS 14 or newer with Apple Silicon, Xcode, `qemu-img`, `jq` and `gpg`:

```bash
cd tools/image-builder
scripts/build.sh developer-ubuntu
```

The first run downloads the base image into `build/cache/`. The result is a sparse RAW disk in an Apple Archive and a filled manifest in `dist/`.

## Checks

```bash
node scripts/check.js
```

It validates the JSON files, that the catalog and the recipes agree on the ids, and the syntax of every shell script. It needs Node.js 20 or newer and nothing else.

## Roadmap

1. **Now:** the recipes and the catalog are in this repository, with checks in GitHub Actions.
2. A build of `developer-ubuntu-server` for amd64 in GitHub Actions, measuring size and time.
3. The installable ISO for amd64, with a boot test in QEMU, and the same for Arch.
4. The shared Total.js layer in `shared/`, used by every distro and by the images of TotalVM.
5. The package repository served from GitHub Pages.

## License

To be decided before the repository is made public (the code, and the wallpapers, sounds and logos that are in `assets/`).
