# Install Total.js Developer on Arch Linux (testing)

The Arch edition is built from the same packages as the Ubuntu one, for **x86_64** and for **ARM**, in two editions:

- **Server:** the command line, with everything that Total.js needs: Node.js, Total.js, Docker, PostgreSQL, Code, Flow, Total.js Center and HTTPS for `totaljs.developer`.
- **Desktop:** the server plus an Openbox desktop with the look of Total.js, Firefox and Chromium (the ones of the repositories of Arch).

It uses the **official ISO of Arch Linux, unmodified**, and its own installer, `archinstall`, with a configuration of ours: nothing of Arch is remastered.

## What you need

- A machine (virtual or real) with an Intel or AMD processor, 4 GB of memory, 30 GB of disk and an internet connection.
- The official ISO: <https://archlinux.org/download/>. Check its signature or its checksum there.

## Install

1. Start the machine from the ISO of Arch. When the shell appears (`root@archiso`), make sure that there is internet: `ping -c1 archlinux.org`.
2. Tell pacman to trust the key of the repository of Total.js (the fingerprint is `95454694523B8D18A376F7D5D722BA35C8427B40`: check it):

   ```bash
   curl -fsSL https://totaljs-es.github.io/developer-distros/repo/totaljs-developer.gpg | pacman-key --add -
   pacman-key --lsign-key 95454694523B8D18A376F7D5D722BA35C8427B40
   ```

3. Start the installer with the configuration of the edition that you want (`desktop.json` or `server.json`):

   ```bash
   archinstall --config https://totaljs-es.github.io/developer-distros/repo/arch/desktop.json
   ```

4. Choose what is not decided by the configuration (the disk, the language and keyboard, the time zone, and the root password and your user with the permission of `sudo`) and select **Install**.
5. When it finishes, restart and take out the ISO. Log in and open `https://totaljs.developer` from a browser of the same machine, or from another computer that can reach it.

The first time, Docker downloads the images of Code, Flow, PostgreSQL and pgAdmin: give it a few minutes. How to use it: [How to use it](using.md).

## On ARM (UTM, Parallels or VMware on a Mac with Apple Silicon)

Arch Linux has no official ISO for ARM. The ARM edition uses **Arch Linux ARM** (a separate project) and the **Archboot AArch64 ISO**, a minimal Arch environment, to install it:

1. Download the ISO from <https://release.archboot.com/aarch64/latest/iso/> and start a UEFI machine with it (4 GB of memory, 30 GB of disk; in UTM, **Use Apple Virtualization** is the one that works best).
2. At its shell, with internet, run:

   ```bash
   curl -fsSL https://totaljs-es.github.io/developer-distros/repo/arch/install-arm.sh | bash
   ```

3. It asks for the edition (desktop or server), the keyboard layout and the time zone (type `list` to see them), the disk (**it erases it**), the name of the machine, your user and your password; it downloads and checks the root filesystem of Arch Linux ARM, trusts the key of the repository of Total.js (it checks the fingerprint) and installs the server edition.
4. Take out the ISO and restart. Log in with your user.

The root account is locked, the user `alarm` of Arch Linux ARM is removed, and your user can use `sudo`.

## Notes

- It is a **testing** edition: the packages are the same as in Ubuntu and pass their tests in a container of Arch, but the installation with `archinstall` is the least tested part.
- Based on Arch Linux. It is not an official Arch release. Arch Linux and the Arch logo are trademarks of their owners.
