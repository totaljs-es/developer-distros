# Experimental own live ISO

**Status: experimental and outside the published installation path.** The workflow runs manually only; it is not a release check for the Arch ISOs or the Ubuntu ISO/seeds. The optional Calamares installer has been built locally on arm64 and validated through Server and Desktop installations, disk-only boot, restart and HTTPS services. Desktop password login was checked. amd64 installation remains pending; see [the evidence](../../docs/validation-2026-11-03.md). Distribution status remains documented in `docs/legal.md`.

The graphical installer uses the [shared Calamares interface](../../shared/calamares/README.md)
and [online installation design](../../docs/installer.md). Set `CALAMARES=1` to
include a graphical live session and the experimental online installer. The
default command-line build (`CALAMARES=0`) remains available.

The ISO of Total.js Developer that is ours: a live image made from the packages of Ubuntu 26.04, with our identity and **no installer of Canonical** in it. It is what
`docs/legal.md` calls the way out of publishing the modified installer of Ubuntu: Ubuntu is the base (`ID_LIKE=ubuntu debian`), and what carries its marks is replaced.

## How it is made

`build.sh` runs natively in a clean Ubuntu 26.04 amd64 or arm64 container (privileged, because it mounts and uses `chroot`):

1. `debootstrap` makes a minimal system from the archive of Ubuntu (`main` and `universe`).
2. `chroot-setup.sh` installs, inside it, the kernel, `live-boot` (the Debian tool that starts a system from a CD, with nothing of Ubuntu in it) and the base of a system that boots and has a
   network, and writes the identity: `os-release`, `issue`, the name of the machine.
3. The files of `rootfs/` are copied into the system (the service that says on the console that it booted).
4. With `CALAMARES=1`, the live root gets Calamares, Openbox, LightDM and NetworkManager. A locked, temporary `live` account starts the root-owned installer profile. Its live-only configuration never reaches an installed target, which is bootstrapped from packages.
5. The system is packed in a squashfs (`xz`), and `grub-mkrescue` writes the ISO: BIOS/UEFI on amd64, UEFI on arm64. The menu is `grub.cfg`.

`test-boot.sh` starts the ISO in QEMU, with BIOS or UEFI (`UEFI=1`), and waits for `TOTALJS-LIVE-OK` on the serial console. `ARCH=arm64` selects QEMU AArch64 and always uses UEFI. For the graphical build, `MARKER_PATTERN=TOTALJS-CALAMARES-READY QEMU_MEMORY=4096` waits for LightDM, the Calamares process and its successful native-module-load log marker. This proves startup only, not installation.

The manually dispatched workflow `.github/workflows/iso-own.yml` has an installer checkbox (on by default), builds on native amd64 and arm64 runners and retains each ISO for seven days as a run artifact. It creates no public release and has no tag trigger.

## What carries marks of Ubuntu and what is done about it

| Where | State |
| --- | --- |
| `os-release`, `issue` | Ours (`ID=totaljs-developer`, `ID_LIKE="ubuntu debian"`). Only in the live image, which is rebuilt from scratch on every build (it is never updated, so nothing puts the old identity back); `VERSION_CODENAME` and `UBUNTU_CODENAME` stay, because tools such as the Docker source read them. The installed system is bootstrapped from the packages of Ubuntu as they are, and keeps the `os-release` of Ubuntu (it is Ubuntu with the Total.js layer). |
| The installer | Optional Calamares, with shared Total.js branding and online installation jobs. Ubuntu arm64 UI, Server and Desktop installation validated locally; amd64 pending. |
| GRUB, the boot splash, the wallpapers | Ours (`grub.cfg`, `shared/plymouth`, `shared/wallpapers`). |
| The packages of Ubuntu | Redistributed as they are, from the archive of Ubuntu. |

## Build it

```bash
docker run --rm --privileged -v "$PWD:/src" -v "$PWD/build/own:/out" ubuntu:26.04 bash /src/iso/own/build.sh /out/totaljs-ubuntu-amd64.iso
iso/own/test-boot.sh build/own/totaljs-ubuntu-amd64.iso
```

For the graphical installer, on a native Linux machine with Docker:

```bash
docker run --rm --privileged -e CALAMARES=1 -v "$PWD:/src:ro" -v "$PWD/build/own:/out" ubuntu:26.04 bash /src/iso/own/build.sh /out/totaljs-ubuntu-amd64.iso
UEFI=1 QEMU_MEMORY=4096 MARKER_PATTERN=TOTALJS-CALAMARES-READY iso/own/test-boot.sh build/own/totaljs-ubuntu-amd64.iso
```

Use an arm64 host/container and an `arm64` output name for ARM, and set
`ARCH=arm64` on the test command. No cross-architecture chroot is attempted.
An installation needs internet and a disposable disk of at least 30 GiB. The
boot check attaches no disk; attach a fresh disk separately for a manual
installation, then remove the ISO and prove the target boots by itself.

Source/command-double checks are not a substitute for these VM checks. Inspect
the welcome, edition, partition summary and completion pages, and exercise
download failure, first login and reboot in both editions before release.

## Local build on Apple Silicon

The local arm64 validation uses Homebrew QEMU and Docker through a dedicated
Colima context. The default Docker context is left unchanged:

```bash
brew install docker colima qemu
colima start distros --vm-type vz --cpu 4 --memory 6 --disk 50 --mount "$PWD:w" --activate=false --ssh-config=false
mkdir -p build/own/local
docker --context colima-distros run --rm --privileged -e ARCH=arm64 -e CALAMARES=1 -v "$PWD:/src:ro" -v "$PWD/build/own/local:/out" ubuntu:26.04 bash /src/iso/own/build.sh /out/totaljs-ubuntu-arm64.iso
ARCH=arm64 UEFI=1 QEMU_MEMORY=4096 MARKER_PATTERN=TOTALJS-CALAMARES-READY WORK_DIR=build/own/local/boot-arm64 iso/own/test-boot.sh build/own/local/totaljs-ubuntu-arm64.iso
```

On Apple Silicon the boot test selects HVF automatically and finds the UEFI
firmware installed by Homebrew. `QEMU_ACCEL=tcg` forces software emulation;
`QEMU_FIRMWARE` selects a different firmware file. amd64 UEFI uses split
OVMF flash and a fresh copy of its matching variable template; set
`QEMU_FIRMWARE_VARS` when it cannot be inferred from the code filename. The boot check has no target
disk and proves graphical startup only. The separate installation evidence is
in [the local validation report](../../docs/validation-2026-11-03.md).


## Generate the ISOs in GitHub Actions

After pushing the commit to `main`, open **Actions → iso-own → Run workflow**.
Select `main`, leave **Include the experimental graphical Calamares installer**
checked, and start the run. Pushing alone runs source checks; ISO generation
requires this manual dispatch.

The two native jobs build amd64 and arm64. When they pass, download the
`totaljs-ubuntu-amd64` and `totaljs-ubuntu-arm64` artifacts;
each contains its ISO and SHA-256 checksum file. Artifacts expire after seven
days. Boot logs are retained separately. These builds do not create a release.
