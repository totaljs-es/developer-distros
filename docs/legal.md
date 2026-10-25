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
| The official ISO of Ubuntu Server | **Not ours and not modified.** People download it from Ubuntu; we only link to it and give its checksum. |
| An ISO that is the official one modified with our seed (`iso/ubuntu/build-iso.sh`) | **Not published.** It is a modified installer image with the marks of Ubuntu. It is built in the CI to test the install, and anyone may build it for themselves. |

## How the installation works without modifying the ISO

The installer of Ubuntu reads an autoinstall configuration from a second device whose volume label is `CIDATA`. The seed image is that
device: a USB stick or a second virtual drive, next to the official ISO. When the installer finds it, it asks for confirmation before it uses it
(without the parameter `autoinstall` on the kernel command line, it asks for a "yes"). The seed has the questions that the installer keeps for
the person, and downloads the Total.js layer from the repository of packages.

## Names

- The product is **Total.js Developer**. Ubuntu is mentioned only to say what it is made for ("for Ubuntu 26.04 LTS"), never as part of a title.
- The same care for Arch Linux: its logo is a mark, and its name may be used to say that something is made for it.
- Before a release, read again the policy and the guidelines of the marks, and ask Canonical in writing if something is not clear.
