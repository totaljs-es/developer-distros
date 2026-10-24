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

## What is not done yet

- The seed that installs the Total.js layer (desktop, Docker, PostgreSQL, Code, Flow...) and asks the person for the user and the disk.
- A test of the UEFI boot, and of the desktop edition.
- Publishing the ISO in a release (the limit of a file in a release is 2 GiB, and the size is measured first).
