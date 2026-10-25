# Install Total.js Developer on Arch Linux (testing)

The Arch edition is built from the same packages as the Ubuntu one. Today it is the **server edition** (command line, with everything that Total.js needs: Node.js, Total.js,
Docker, PostgreSQL, Code, Flow, Total.js Center, HTTPS for `totaljs.developer`), for **x86_64**. The desktop and ARM come later.

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

3. Start the installer with our configuration:

   ```bash
   archinstall --config https://totaljs-es.github.io/developer-distros/repo/arch/server.json
   ```

4. Choose what is not decided by the configuration (the disk, the language and keyboard, the time zone, and the root password and your user with the permission of `sudo`) and select **Install**.
5. When it finishes, restart and take out the ISO. Log in and open `https://totaljs.developer` from a browser of the same machine, or from another computer that can reach it.

The first time, Docker downloads the images of Code, Flow, PostgreSQL and pgAdmin: give it a few minutes. How to use it: [How to use it](using.md).

## Notes

- It is a **testing** edition: the packages are the same as in Ubuntu and pass their tests in a container of Arch, but the installation with `archinstall` is the least tested part.
- Based on Arch Linux. It is not an official Arch release. Arch Linux and the Arch logo are trademarks of their owners.
