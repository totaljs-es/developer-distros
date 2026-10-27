# Total.js Developer for Arch Linux

The same packages as the Ubuntu edition, built for Arch from the same source: `packages/` (the layout of Debian) is converted by `mkpkg.py`.

| File | What it does |
| --- | --- |
| `mkpkg.py` | Makes a `PKGBUILD` and an `.install` from each package of `packages/` (the scripts `postinst`, `prerm` and `postrm` become the functions of pacman as they are). |
| `depends.map` | The name of each dependency in Arch. A dependency that is not here stops the build. |
| `skip` | The packages that are not built (the sources of apt, the plymouth of Ubuntu, the desktop for now). |
| `overlay/<package>/` | What Arch needs and Ubuntu does not: `files/` is added to the package and `postinst` runs after the one of Debian. |
| `extra/` | The packages that are only of Arch (the key and the repository of pacman). |
| `build.sh` | Builds the packages with `makepkg` and the repository with `repo-add` (on Arch, as a normal user). |
| `test-install.sh` | Installs the server edition from that repository in a container of Arch and looks at what it promises. |
| `stage-repo.sh` | Signs the repository that the CI built, with the key of Total.js, and puts it where `publish-pages.sh` publishes it. |
| `install-arm.sh` | The installer for ARM (Arch Linux ARM has no ISO): it runs from the Archboot AArch64 ISO and installs the system and the server edition on an empty disk. |
| `archinstall/` | The configuration for `archinstall`, the installer of Arch: the seed of the Arch edition. |

## How it is published

The workflow `arch-repo` builds and tests, in a container of Arch (x86_64), and keeps the repository as an artifact. The key of Total.js is not in GitHub, so the signature is made
on the computer of the maintainers:

```bash
tools/package-repo/build.sh                       # the repository of Ubuntu (and the old one of TotalVM)
arch/stage-repo.sh ~/Downloads/arch-repo-x86_64.zip   # the artifact of the workflow arch-repo: signs it and replaces build/site/repo/arch/x86_64
tools/package-repo/publish-pages.sh               # prepares the branch pages
```

How to install it: [docs/install-arch.md](../docs/install-arch.md).

## What is not done yet

The end-to-end test of installation to disk on both architectures. The desktop and Plymouth packages are already present; the ISO boot checks only establish that the live environment starts.

The x86_64 workflow builds an ISO and `bash arch/iso/test-boot.sh image.iso` boots its kernel/initramfs against that ISO. This bypasses the firmware menus: BIOS/UEFI boot and installation to disk still need separate validation. Serial, extraction and volume-label logs are retained even when the test fails. The ARM workflow boots through UEFI and also retains its serial log.
