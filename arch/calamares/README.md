# Calamares on the Arch installation media

Experimental live-only packaging and integration for x86_64 and aarch64.
The installer uses `shared/calamares` and the official shared artwork, with
the same online Desktop/Server flow as Ubuntu. Native ARM live startup was validated locally; x86 live startup and target
installation remain pending. See [the evidence](../../docs/validation-2026-11-03.md).

`PKGBUILD` builds upstream Calamares 3.3.14 with Qt 6.7+ and the modules used by
our shared profile. `ckbcomp/PKGBUILD` packages the keyboard compiler from
Debian's console-setup 1.240. Both downloads have pinned SHA-256 checksums.
These are build dependencies of the live medium, separate from the signed
Total.js target package repository. No signing key is needed to build them.

## x86_64

On a disposable native Arch build machine, install the build dependencies
listed in `PKGBUILD`, plus `base-devel`, `archiso` and Python. As a normal user:

```bash
bash arch/calamares/build-packages.sh "$PWD/build/arch-calamares"
```

Then, as root:

```bash
CALAMARES=1 CALAMARES_PACKAGES="$PWD/build/arch-calamares" KEY_FILE="$PWD/tools/image-builder/images/developer-ubuntu/assets/totaljs-repository.gpg" bash arch/iso/build.sh
```

The build makes a temporary local pacman repository from these packages.
Only that local build repository allows unsigned packages. Official archive
signatures and the pinned Total.js target key remain required for installation.
Keep package outputs outside `build/arch-iso`, which the ISO builder replaces.

## aarch64

The existing native ARM builder prepares its Arch Linux ARM rootfs, installs
build dependencies and compiles both packages as an unprivileged temporary
user. It installs the framework and graphical live dependencies and removes
the temporary user's home and source tree before packing the image.
Build tools currently remain in this experimental live image. Extraction and
compilation require a case-sensitive Linux filesystem; on macOS Docker bind
mounts, set `ARCH_ARM_BUILD_DIR` to a directory inside the Linux container and
copy only the resulting ISO back to the host.

```bash
sudo env CALAMARES=1 KEY_FILE="$PWD/tools/image-builder/images/developer-ubuntu/assets/totaljs-repository.gpg" bash arch/iso-arm/build.sh
```

`ROOTFS_URL` can select another official Arch Linux ARM mirror when needed.
The upstream `alarm` account and enabled SSH are removed from the live image.
New target users are created separately by Calamares.

## Configuration and CI

`stage-live.sh` copies shared sources into the disposable image and adds a
pacman post-transaction hook. When the local Calamares package is installed,
that hook runs `setup-live.sh` inside the live rootfs to generate the profile,
create the locked live account and configure LightDM and NetworkManager.
Arch's live account alone joins `autologin`, as required by the official
LightDM PAM policy; target accounts keep password-based login.
It does not run a target installation. The console installer remains available.

Both `arch-iso` and `arch-iso-arm` offer a manual **installer** checkbox, enabled
by default for manual runs. Push-triggered builds keep the console profile.
Graphical runs additionally check `TOTALJS-CALAMARES-READY`; this establishes
module loading only. Full installation, medium removal, login, network and
services must still be checked separately in disposable VMs.

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-arch-calamares.py
```
