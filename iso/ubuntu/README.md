# Ubuntu ISO (amd64)

The installable ISO of the Total.js Developer Distro on Ubuntu, for computers with an amd64 processor. It is built in GitHub Actions from the newest Ubuntu LTS and it installs over the network: the ISO is small and the Total.js packages are downloaded while it installs.

## How it is made

`build-iso.sh` does not build a system: it remasters the official `live-server` ISO of Ubuntu.

1. It downloads `SHA256SUMS` of the series (`UBUNTU_RELEASE`, 26.04 by default) and checks its signature with the signing keys of Ubuntu.
2. It takes the newest `live-server-amd64` ISO of that list and checks its checksum.
3. It adds an autoinstall seed (`user-data` and `meta-data`, as `/nocloud`) and changes the boot menu so the installer uses it.
4. It writes the new ISO with `xorriso`, keeping the way the original boots (BIOS and UEFI).

## What the test proves

`test-install.sh` installs the ISO unattended in QEMU, powers off, boots the installed system and waits for a marker on the serial console. `seed-ci/` is that test seed, only for the CI: it installs the stock server with a random password that nobody knows. The seed of the real distro is not here yet.

Run it on Linux with `xorriso`, `qemu-system-x86`, `qemu-utils` and `gnupg`:

```bash
iso/ubuntu/build-iso.sh iso/ubuntu/seed-ci build/test.iso
iso/ubuntu/test-install.sh build/test.iso
```

The workflow `.github/workflows/iso-ubuntu.yml` runs both, and keeps the logs of the installer and of the first boot.

## The server edition

`seed/` is the seed that people use: it keeps the installer's own questions (keyboard, network, disk, who you are) and, when it has installed Ubuntu, `install-layer.sh` downloads the key and the source of the Total.js repository and installs `totaljs-developer-server` into the new system. The address of the repository is `REPO_URL` (the default is GitHub Pages). It needs a network connection: if the repository cannot be reached it says so and stops.

The workflow builds a repository with a throwaway key, serves it on the computer of the runner (`10.0.2.2` for the guest of QEMU) and installs the ISO of `seed-ci-layer/` unattended. The installed system must boot, have Node.js 24 and have its first person in the group `totaljs-developer`. The ISO of `seed/` is only built there: its questions need a person.

## What is not done yet

- The rest of the layer in the seed: today `totaljs-developer-server` has the runtime, the tools and SSH; the Docker stack, the DNS, Total.js Center and the brand are still to be packages. The desktop edition and its entry in the boot menu.
- A test of the UEFI boot, and of the desktop edition.
- Publishing the ISO in a release (the limit of a file in a release is 2 GiB, and the size is measured first).
