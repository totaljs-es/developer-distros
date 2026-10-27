# ISO fixes and Toto integration — 2026-10-27

## Changes

- Arch x86_64: remove the formatting quotes from xorriso's volume label before passing it to `archisolabel`; consume the entire serial-log pipeline so `pipefail` cannot turn a successful match into a SIGPIPE failure. The boot check is now a reusable script, with cleanup and retained diagnostics.
- Arch ARM: apply the same serial-log matching correction and retain serial/mkinitcpio logs on failure.
- Ubuntu: update the installer's `md5sum.txt` for the changed GRUB menu, added seed files and removed directories in every slimming mode, including `SLIM=0`. Verification of the downloaded base ISO remains separate.
- Toto: official, unmodified artwork in the shared layer, Center welcome/empty-project help, the TotalVM first-run wizard for both distributions, and an optional wallpaper. Center and wallpaper packages receive new revisions. The proprietary artwork license and attribution travel with the packages.

## Local evidence

- `node scripts/check.js`: passed (JSON, catalog/recipes, shell syntax, generated SVGs and repository pointers).
- `python3 scripts/test-iso.py`: five passing regression tests. Ubuntu media hashes/removals; Arch label parsing, large logs, coloured systemd output, partial boot rejection and missing-medium rejection. QEMU and xorriso are test doubles here.
- `python3 arch/mkpkg.py --all OUT`: generated 14 Arch package recipes; checked that Center artwork and the 4K wallpaper are included. This does not build or install the packages with makepkg/pacman.
- Chrome: Center with fictitious service/machine data, light/dark themes, 390 px layout without horizontal overflow, successful image loading, empty-project help replaced by a real project, no JavaScript errors.
- Python syntax checked for the changed wizard, wallpaper generator and media-hash helper. The GTK wizard itself has not been launched.
- Wallpaper rendered from its generated SVG with Chromium and visually inspected. Local Inkscape could not decode its PNG; normal exports still use `shared/wallpapers/export.sh` with a working Inkscape installation.
- Browser evidence is local under `build/review-toto/`; it is not release evidence.

## Still required

Build and boot the ISO workflows against this revision. No Docker daemon or QEMU installation was available locally, and these changes have not been pushed or run in GitHub Actions. The x86_64 Arch check boots the extracted kernel/initramfs against the ISO; it does not test the BIOS/UEFI menus or an installation to disk. ARM checks UEFI live boot. Verify real installation and first login on both architectures separately.

The baseline before these changes was commit `00570c1fa210356a64ac16e8fcf06ce1c4eaf71c`: [Ubuntu passed](https://github.com/totaljs-es/developer-distros/actions/runs/40300781384), [Arch ARM passed](https://github.com/totaljs-es/developer-distros/actions/runs/40302564101), and [Arch x86_64 built but failed its QEMU boot step](https://github.com/totaljs-es/developer-distros/actions/runs/40305607526). Those results do not validate this revision.

Publication of the remastered Ubuntu installer remains governed by the existing state in `docs/legal.md`. No release tag or ISO has been published by this work.
