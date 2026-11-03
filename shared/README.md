# shared

The Total.js layer that every distro has in common: the desktop and its configuration, wallpapers, the Plymouth boot theme, themes, scripts and branding. It is the only place where the experience is customized, so Ubuntu and Arch stay the same for the user.

`shared/branding/toto/` contains official Toto artwork and its proprietary license. Toto is the European red fox mascot of Spanish Total.js and accompanies Center and first-run setup. Use these assets, with attribution, and keep the Total.js logo for system icons and the boot splash. `branding/mascot.png` is retained as legacy Tux artwork.

`wallpapers/` has the wallpapers of the desktop (4K, drawn with code, with the official logo): see its README.

`plymouth/` has the boot splash, an animation of the logo coming together with a ring of light that follows the progress of the boot: see its README.

`calamares/` contains shared graphical-installer branding, a non-installing preview and experimental online installation jobs. The own Ubuntu live builder includes it optionally; arm64 live startup and both Server and Desktop installations have been validated locally. Ubuntu amd64 remains pending. Both Arch live builders now offer optional integration; native Arch ARM live startup is validated; Arch target installation and x86 startup remain pending. See [the design](../docs/installer.md).

The remaining common files are still inside the recipes (`tools/image-builder/images/developer-ubuntu/assets/`) and move here one piece at a time, each with a build that proves nothing changed.
