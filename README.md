<p align="center"><img src="shared/branding/mascot.png" alt="Tux hugging the Total.js logo" width="180"></p>

<h1 align="center">Total.js Developer</h1>

<p align="center"><b>A complete development environment for <a href="https://www.totaljs.com">Total.js</a>, installed in minutes.</b><br>Built on Ubuntu 26.04 LTS, for virtual machines and computers, with a desktop or only the command line.</p>

<p align="center">
  <a href="https://github.com/totaljs-es/developer-distros/actions/workflows/check.yml"><img src="https://github.com/totaljs-es/developer-distros/actions/workflows/check.yml/badge.svg" alt="check"></a>
  <a href="https://github.com/totaljs-es/developer-distros/actions/workflows/package-repo.yml"><img src="https://github.com/totaljs-es/developer-distros/actions/workflows/package-repo.yml/badge.svg" alt="package-repo"></a>
  <a href="https://github.com/totaljs-es/developer-distros/actions/workflows/iso-ubuntu.yml"><img src="https://github.com/totaljs-es/developer-distros/actions/workflows/iso-ubuntu.yml/badge.svg" alt="iso-ubuntu"></a>
  <a href="https://github.com/totaljs-es/developer-distros/actions/workflows/arch-iso.yml"><img src="https://github.com/totaljs-es/developer-distros/actions/workflows/arch-iso.yml/badge.svg" alt="arch-iso"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
</p>

<p align="center"><img src="docs/images/launcher.jpg" alt="The desktop of Total.js Developer: the widget, a terminal and the launcher" width="860"></p>

## What you get

- **Node.js** (LTS) with **Total.js 5** and **Total.js 4**, `npm`, `pnpm` and `yarn`, and **fnm** to change the version of Node.js per project.
- **Code**, the Total.js editor in the browser, and **Flow**, to program with diagrams.
- **PostgreSQL** with **pgAdmin**, and a reverse proxy: every project has its own address, `my-project.totaljs.developer`.
- **Docker** with Compose, Git, SSH, `ufw` and `fail2ban`, and the usual tools of the command line.
- **Total.js Center**, the front door at `https://totaljs.developer`: the state of the services, your projects and how to connect to the database.
- In the **desktop edition**: an Openbox desktop with the look of Total.js, Firefox, Google Chrome, a terminal, a file manager, a widget on the wallpaper and thirteen wallpapers.

## Install

Start a machine with the **official ISO of Ubuntu Server 26.04 LTS** and one **seed** (a small image, a few hundred kilobytes) next to it, answer the usual questions of the installer, and the rest
installs by itself. It needs an internet connection, in a virtual machine and on a computer.

1. Download the [official ISO of Ubuntu Server](https://releases.ubuntu.com/26.04/) (amd64, Intel and AMD) or the [one for arm64](https://cdimage.ubuntu.com/ubuntu/releases/26.04/release/) (ARM, such as UTM or Parallels on a Mac with Apple Silicon).
2. Download a seed from the [releases](../../releases): `totaljs-developer-desktop-seed.iso` (with a desktop) or `totaljs-developer-server-seed.iso` (command line only).
3. Attach both to a virtual machine (4 GB of memory, 30 GB of disk) as two drives, or write them to two USB sticks, start from the one of Ubuntu, choose **Try or Install Ubuntu Server** and type `yes` when it asks about the autoinstall.

**[Installation guide](docs/install.md)**, with the settings of the virtual machine and the steps.

## Your first minutes

| Open | What it is |
| --- | --- |
| `https://totaljs.developer` | Total.js Center |
| `https://code.totaljs.developer` | Code |
| `https://flow.totaljs.developer` | Flow |
| `https://pgadmin.totaljs.developer` | pgAdmin |

The names are answered by the machine itself: there is nothing to configure. The first time, the services download their images, and Total.js Center shows when each one is ready.
**[How to use it](docs/using.md)**.

<p align="center"><img src="docs/images/terminal.jpg" alt="A terminal with the summary of Total.js Developer" width="420"> <img src="docs/images/desktop.jpg" alt="The widget on the wallpaper" width="420"></p>

## How it is built

Total.js Developer does not fork or patch Ubuntu. It is a **set of packages** in a signed APT repository, installed on top of Ubuntu Server 26.04 LTS, and
everything else comes from the archive of Ubuntu.

- **Packages:** `totaljs-developer-server` and `totaljs-developer-desktop` are meta-packages; each piece (Node.js, the services, the DNS, Center, the desktop, the widget...) is a package of its own.
  The repository is built and signed from this repository and served at <https://totaljs-es.github.io/developer-distros/>.
- **The installer:** the unmodified official Ubuntu Server ISO reads our separate autoinstall seed image. Ubuntu packages come from Ubuntu, and the Total.js layer comes from the repository above. The remastered installer is tested separately; see [its publication status](docs/legal.md).
- **Tested:** each change installs the packages in a clean Ubuntu 26.04, starts the desktop session in a virtual screen, and the installer is run in QEMU and the installed system booted.
- **Already have Ubuntu 26.04?** Add the repository and install the packages: the commands are on its [front page](https://totaljs-es.github.io/developer-distros/), and [`docs/layer.md`](docs/layer.md) explains them.

## Documentation

| | |
| --- | --- |
| [Installation guide](docs/install.md) | Download, prepare a virtual machine or a computer, install |
| [How to use it](docs/using.md) | Addresses, projects, database, services, desktop shortcuts |
| [The packages](docs/layer.md) | What each package does and the rules they follow |
| [Legal notes](docs/legal.md) | Licenses, marks, and what is and is not distributed |
| [The installer](iso/ubuntu/README.md) | The ISO, the seed images and how they are tested |

## In this repository

```text
packages/              the source of the packages
tools/package-repo/    builds and signs the repository, and tests it in a clean Ubuntu
iso/ubuntu/            the ISO and the seed images, and the tests that install and boot the system
iso/own/               experimental live-image prototype (manual builds only)
shared/                the artwork: wallpapers, boot splash and logos
docs/                  the documentation
tools/image-builder/   the images for TotalVM (macOS with Apple Silicon)
```

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md). To report a vulnerability, follow [SECURITY.md](SECURITY.md).

## License

Toto, the European red fox mascot of [Spanish Total.js](https://totaljs.es/), accompanies the welcome screen and first steps. His official artwork is kept in [`shared/branding/toto`](shared/branding/toto/README.md).

The code is under the [MIT License](LICENSE). The wallpapers and the images of the boot splash are under [CC BY-SA 4.0](LICENSE-ARTWORK). Toto and his appearance in wallpapers are covered by the [proprietary Toto license](shared/branding/toto/LICENSE.md). The Total.js logo and the legacy Tux artwork are not covered by either code or wallpaper license. The software that the packages install (Node.js, Docker, PostgreSQL, Firefox, Chrome, Ubuntu...) keeps its own licenses.

## Trademarks

Total.js Developer is based on Ubuntu. It is not an official Ubuntu release and it is not endorsed by Canonical. Ubuntu is a trademark of Canonical Ltd.
Arch Linux and the Arch logo are trademarks of their owners.
