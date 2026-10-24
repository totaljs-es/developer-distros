# shared

The Total.js layer that every distro has in common: the desktop and its configuration, wallpapers, the Plymouth boot theme, themes, scripts and branding. It is the only place where the experience is customized, so Ubuntu and Arch stay the same for the user.

`branding/mascot.png` is the official mascot: Tux hugging the Total.js logo (1024 x 1024, transparent). It is the identity of the distros, of TotalVM, of the boot screen and of the documentation; use this file and not a copy.

The rest is empty on purpose. The files are still inside the recipes (`tools/image-builder/images/developer-ubuntu/assets/`) and move here one piece at a time, each with a build that proves nothing changed.
