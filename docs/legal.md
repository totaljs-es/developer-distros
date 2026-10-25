# Legal notes: what we may distribute

Notes of the project, not legal advice. They come from the public policy of Canonical
(<https://canonical.com/legal/intellectual-property-policy>, read on 2026-10-25), which says that its permission "can be revoked at any time":
read it again before each release.

## What the policy says

- Unmodified Ubuntu, with the installer images and the packages that Canonical publishes, **may be redistributed**.
- **Modified** versions may be redistributed with the Ubuntu marks only if Canonical approves, certifies or provides them. Otherwise the
  marks have to be removed and replaced, and the binaries rebuilt from source.
- Modifying Ubuntu for personal or internal use is allowed.
- The name Ubuntu needs written permission and may not be part of the title of a piece of software. A project built for Ubuntu may say so, as long
  as it does not suggest that Canonical endorses it.

## What that means here

| What we publish | Status |
| --- | --- |
| The APT and Pacman repository, the `.deb` packages, the scripts, the wallpapers and the boot splash | **Ours**, with no material of Canonical. They may say that they are made for Ubuntu 26.04 LTS. |
| The seed images (`totaljs-developer-desktop-seed.iso` and `totaljs-developer-server-seed.iso`) | **Ours**: a few kilobytes with an autoinstall configuration. Nothing of Canonical is inside. |
| The official ISO of Ubuntu Server | **Not ours and not modified.** People may download it from Ubuntu together with a seed. |
| **The ISO of Total.js Developer** (`totaljs-developer-amd64.iso`): the installer of Ubuntu Server with our seed and a boot menu added | **Distributed as an Ubuntu remix**, called "Total.js Developer, an Ubuntu remix" and not "Ubuntu". It is a modified installer image that carries the marks of Ubuntu: **Canonical was asked for approval on 2026-10-25** (the form of <https://ubuntu.com/legal/terms-and-policies/contact-us>). If it asks for a licence agreement, conditions or another form, this page and `iso/own/README.md` say what was decided. |

If Canonical does not approve it, the ways out are the seeds with the official ISO (already published), or our own image without its marks (`iso/own`).

## How the installation works without modifying the ISO

The installer of Ubuntu reads an autoinstall configuration from a second device whose volume label is `CIDATA`. The seed image is that
device: a USB stick or a second virtual drive, next to the official ISO. When the installer finds it, it asks for confirmation before it uses it
(without the parameter `autoinstall` on the kernel command line, it asks for a "yes"). The seed has the questions that the installer keeps for
the person, and downloads the Total.js layer from the repository of packages.

## Licenses

The code is MIT (`LICENSE`) and the artwork of `shared/wallpapers` and `shared/plymouth` is CC BY-SA 4.0 (`LICENSE-ARTWORK`), like the artwork of Ubuntu. The logo and the mascot of
Total.js are marks and are not licensed. The icons of the menu in `tools/package-repo/icons` are the icons of Total.js, published with jComponent, and follow the license of the code (MIT).

## Names

- The product is **Total.js Developer**. Ubuntu is mentioned only to say what it is made for ("for Ubuntu 26.04 LTS"), never as part of a title.
- The same care for Arch Linux: its logo is a mark, and its name may be used to say that something is made for it.
- Before a release, read again the policy and the guidelines of the marks, and ask Canonical in writing if something is not clear.
