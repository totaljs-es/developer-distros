# shared

The Total.js layer that every distro has in common: the desktop and its configuration, wallpapers, the Plymouth boot theme, themes, scripts and branding. It is the only place where the experience is customized, so Ubuntu and Arch stay the same for the user.

`shared/branding/toto/` contains official Toto artwork and its proprietary license. Toto is the European red fox mascot of Spanish Total.js and accompanies Center and first-run setup. Use these assets, with attribution, and keep the Total.js logo for system icons and the boot splash. `branding/mascot.png` is retained as legacy Tux artwork.

`wallpapers/` has the wallpapers of the desktop (4K, drawn with code, with the official logo): see its README.

`plymouth/` has the boot splash, an animation of the logo coming together with a ring of light that follows the progress of the boot: see its README.

The rest is empty on purpose. The files are still inside the recipes (`tools/image-builder/images/developer-ubuntu/assets/`) and move here one piece at a time, each with a build that proves nothing changed.
