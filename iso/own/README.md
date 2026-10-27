# Experimental own live ISO

**Status: experimental and outside the published installation path.** The workflow runs manually only; it is not a release check for the Arch ISOs or the Ubuntu ISO/seeds. This prototype has no installer and has not been cleared for public distribution.

The ISO of Total.js Developer that is ours: a live image made from the packages of Ubuntu 26.04, with our identity and **no installer, logo or name of Canonical** in it. It is what
`docs/legal.md` calls the way out of publishing the modified installer of Ubuntu: Ubuntu is the base (`ID_LIKE=ubuntu debian`), and what carries its marks is replaced.

## How it is made

`build.sh` runs in a clean Ubuntu 26.04 (a privileged container, because it mounts and uses `chroot`):

1. `debootstrap` makes a minimal system from the archive of Ubuntu (`main` and `universe`).
2. `chroot-setup.sh` installs, inside it, the kernel, `live-boot` (the Debian tool that starts a system from a CD, with nothing of Ubuntu in it) and the base of a system that boots and has a
   network, and writes the identity: `os-release`, `issue`, the name of the machine.
3. The files of `rootfs/` are copied into the system (the service that says on the console that it booted).
4. The system is packed in a squashfs (`xz`), and `grub-mkrescue` writes a hybrid ISO that starts with BIOS and with UEFI. The menu is `grub.cfg`.

`test-boot.sh` starts the ISO in QEMU, with the BIOS or with UEFI (`UEFI=1`), and waits for `TOTALJS-LIVE-OK` on the serial console. The workflow `.github/workflows/iso-own.yml` does all of it.

## What carries marks of Ubuntu and what is done about it

| Where | State |
| --- | --- |
| `os-release`, `issue` | Ours (`ID=totaljs-developer`, `ID_LIKE="ubuntu debian"`). They are files of the package `base-files`: a later version of that package has to be rebuilt with our identity, so that an update does not put the old one back. |
| The installer | None yet: the image only starts. Ours will be Calamares, with our branding. |
| GRUB, the boot splash, the wallpapers | Ours (`grub.cfg`, `shared/plymouth`, `shared/wallpapers`). |
| The packages of Ubuntu | Redistributed as they are, from the archive of Ubuntu. |

## Build it

```bash
docker run --rm --privileged -v "$PWD:/src" -v "$PWD/build/own:/out" ubuntu:26.04 bash /src/iso/own/build.sh /out/totaljs-developer-live-amd64.iso
iso/own/test-boot.sh build/own/totaljs-developer-live-amd64.iso
```
