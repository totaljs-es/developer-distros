# The installer (Ubuntu 26.04, amd64)

People install Total.js Developer with the **official ISO of Ubuntu Server, unmodified**, and a **seed image** next to it. The seed is ours, a few kilobytes,
and has nothing of Ubuntu inside: that is what is published in a release (`docs/legal.md` explains why the ISO of Ubuntu is not modified and republished).

## The seed image

`build-seed.sh <desktop|server> <output.iso>` makes it:

- an ISO with the volume label `CIDATA` and two files, `user-data` and `meta-data`. The installer of Ubuntu reads an autoinstall configuration from such a device;
  without `autoinstall` on the kernel command line it asks the person to confirm it first.
- the template is `seed-image/user-data.in`. It keeps the questions of the installer for the person (keyboard, network, disk and who they are) and, when Ubuntu is installed, runs
  `install-layer.sh`, which travels **inside** the `user-data` (the seed is the only thing that is read from the device).
- `install-layer.sh` writes the key and the source of the repository of packages into the new system, installs `totaljs-developer-release` and the sources of Docker (and of Mozilla,
  for the desktop), updates the lists and installs `totaljs-developer-server` or `totaljs-developer-desktop`.
- `REPO_URL` changes the repository that the seed installs from (the default is the one of GitHub Pages).

The workflow `.github/workflows/release-seed.yml` builds both seeds when a tag `v*` is pushed, checks that the repository of packages answers, and publishes the seeds with their `SHA256SUMS`,
an attestation of where they were built and the notes of the release (which say where to get the official ISO and its checksum).

## The tests

`build-iso.sh` remasters the official `live-server` ISO of Ubuntu with a seed in it and a boot menu that uses it. **That ISO is for the tests and for whoever builds it for themselves: it is never published.**

1. It downloads `SHA256SUMS` of the series (`UBUNTU_RELEASE`, 26.04 by default) and checks its signature with the signing keys of Ubuntu.
2. It takes the newest `live-server-amd64` ISO of that list and checks its checksum.
3. It adds an autoinstall seed (`/nocloud`) and changes the boot menu (two entries: desktop and server, which differ in `totaljs.edition=` on the kernel command line).
4. It writes the new ISO with `xorriso`, keeping the way the original boots (BIOS and UEFI).

`test-install.sh` installs such an ISO unattended in QEMU, powers off, boots the installed system and waits for a marker on the serial console. Run it on Linux with `xorriso`,
`qemu-system-x86`, `qemu-utils` and `gnupg`:

```bash
iso/ubuntu/build-iso.sh iso/ubuntu/seed-ci build/test.iso
iso/ubuntu/test-install.sh build/test.iso
```

The seeds of the tests are `seed-ci/` (stock server, random password) and `seed-ci-layer/` (also installs the Total.js layer, from a repository with a throwaway key that the
workflow serves on the computer of the runner, `10.0.2.2` for the guest of QEMU). The installed system must boot, have Node.js 24 and its first person in the group `totaljs-developer`.
`seed/` is the seed of the remastered ISO that builds by hand. The workflow `.github/workflows/iso-ubuntu.yml` runs all this and keeps the logs of the installer and of the first boot;
`.github/workflows/release-iso.yml` builds the remastered ISO by hand and keeps it as an artifact of the run, to try it.

## The size of the remastered ISO

The official ISO of Ubuntu Server 26.04.1 is 2792 MiB. `build-iso.sh` can take the packages out of it, because this installer downloads them (`SLIM`):

| | Size | Install | First boot |
|---|---|---|---|
| Original (`SLIM=0`, control) | 2792 MiB | 395 s | 15 s |
| `SLIM=pool` (the default: takes out `pool/`, keeps `dists/`) | 1578 MiB | 425 s | 16 s |
| `SLIM=all` (takes out `pool/` and `dists/`) | 1578 MiB | fails in `apt-get update` | |

`SLIM=all` does not work: the CD is a source of apt of the installer, and a source without its `Release` makes `apt-get update` of the new system fail.
