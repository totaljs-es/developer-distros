# Total.js Developer

<p align="center"><img src="shared/branding/mascot.png" alt="Tux hugging the Total.js logo" width="220"></p>

A complete environment for developing with [Total.js](https://www.totaljs.com), ready to use as soon as it is installed. It runs on **Ubuntu 26.04 LTS**
in a virtual machine (the usual way) or on a computer, with a desktop or only the command line.

## What you get

- **Node.js** (LTS) with **Total.js 5** and **Total.js 4**, and `npm`.
- **Code**, the editor of Total.js in the browser, and **Flow**, to program with diagrams.
- **PostgreSQL** with **pgAdmin**, and a reverse proxy so that every project has its own address: `my-project.totaljs.developer`.
- **Docker** with Compose, Git, SSH, `ufw` and `fail2ban`, and the usual tools of the command line.
- **Total.js Center**, the front door at `http://totaljs.developer`: the state of the services, your projects and how to connect to the database.
- In the **desktop edition**: an Openbox desktop with the look of Total.js, Firefox, a terminal, a file manager, a widget on the wallpaper (Conky) and twelve wallpapers.

## Install

Download **one ISO**, start a machine with it, choose the desktop or the server edition in the menu, and answer the usual questions of the installer. The rest
installs by itself. It needs an internet connection, in a virtual machine and on a computer, and how long it takes depends on it.

**[How to install](docs/install.md)** · **[How to use it](docs/using.md)**

The ISO is in the [releases](../../releases) of this repository: `totaljs-developer-amd64.iso`. If you prefer the official ISO of Ubuntu, unmodified, the same releases have a
small seed for each edition to put next to it; `docs/install.md` explains it.

## Already have Ubuntu 26.04?

Total.js Developer is a set of packages in a signed repository. On an installed Ubuntu 26.04 you can add it without a seed:

```bash
curl -fsSL https://totaljs-es.github.io/developer-distros/repo/totaljs-developer.gpg | sudo tee /usr/share/keyrings/totaljs-developer-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/totaljs-developer-archive-keyring.gpg] https://totaljs-es.github.io/developer-distros/repo/ubuntu resolute main" | sudo tee /etc/apt/sources.list.d/totaljs-developer.list
sudo apt update
sudo apt install totaljs-developer-release totaljs-docker-source   # add totaljs-mozilla-source for the desktop edition
sudo rm /etc/apt/sources.list.d/totaljs-developer.list              # the package has written the same source by itself
sudo apt update
sudo apt install totaljs-developer-server                          # or totaljs-developer-desktop
```

## In this repository

```text
packages/              the source of the packages (control, scripts, files)
tools/package-repo/    builds and signs the APT and Pacman repository, and tests it in a clean Ubuntu
iso/ubuntu/            the seed images, and the tests that install and boot the system in QEMU
shared/                the artwork: wallpapers, boot splash and logos
docs/                  the documentation
tools/image-builder/   the images for TotalVM (macOS with Apple Silicon)
scripts/check.js       the checks that run on every change
```

`docs/layer.md` explains how the packages are organised. `docs/legal.md` explains what is and is not published, and why.

## License

The code is under the [MIT License](LICENSE). The wallpapers and the images of the boot splash are under
[CC BY-SA 4.0](LICENSE-ARTWORK). The logo and the mascot of Total.js are not covered by either: they are marks. The software that the packages install
(Node.js, Docker, PostgreSQL, Firefox, Ubuntu...) keeps its own licenses.

## Trademarks

Total.js Developer is based on Ubuntu. It is not an official Ubuntu release and it is not endorsed by Canonical. Ubuntu is a trademark of Canonical Ltd.
Arch Linux and the Arch logo are trademarks of their owners.
