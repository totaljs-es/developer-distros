<p align="center"><img src="shared/branding/mascot.png" alt="Tux hugging the Total.js logo" width="180"></p>

<h1 align="center">Total.js Developer</h1>

<p align="center"><b>A complete development environment for <a href="https://www.totaljs.com">Total.js</a>, installed in minutes.</b><br>Available on Arch Linux and Ubuntu 26.04 LTS, for computers and virtual machines, with a desktop or only the command line.</p>

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
- In the **desktop edition**: an Openbox desktop with the look of Total.js, Firefox, Chrome on Ubuntu or Chromium on Arch, a terminal, a file manager, a widget on the wallpaper and twelve wallpapers.

## Install

### Arch Linux

**[Arch preview — 27 October 2026](https://github.com/totaljs-es/developer-distros/releases/tag/arch-2026.10.27)**

| Your computer or virtual machine | Download |
| --- | --- |
| Intel or AMD (x86_64) | [Download ISO](https://github.com/totaljs-es/developer-distros/releases/download/arch-2026.10.27/totaljs-developer-arch-2026.10.27-x86_64.iso) |
| ARM64, including Apple Silicon Macs (aarch64) | [Download ISO](https://github.com/totaljs-es/developer-distros/releases/download/arch-2026.10.27/totaljs-developer-arch-2026.10.27-aarch64.iso) |

1. Start your computer or virtual machine from the ISO. Use at least **4 GB of memory**, a **30 GB disk** and an **internet connection**.
2. Choose **Desktop** or **Server** and follow the installer. It asks for your disk, keyboard, time zone and account. **The selected disk will be erased.**
3. When installation finishes, remove the ISO and restart from the disk.

**[Arch installation guide](docs/install-arch.md)**, including UTM on a Mac with Apple Silicon.

### Ubuntu

Install with the **official Ubuntu Server 26.04 LTS ISO** and a small seed image that sets up Total.js Developer. An internet connection is required.

1. Download the official Ubuntu Server ISO for [Intel/AMD](https://releases.ubuntu.com/26.04/) or [ARM64](https://cdimage.ubuntu.com/ubuntu/releases/26.04/release/).
2. Download the **Desktop** or **Server** seed from the [Ubuntu seeds release](https://github.com/totaljs-es/developer-distros/releases/tag/seeds-0.1.0).
3. Start the machine with both images attached, boot from the Ubuntu ISO and follow the installer.

**[Ubuntu installation guide](docs/install.md)**, with the virtual machine settings and steps.

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

The Total.js layer is installed as packages on top of Arch Linux, Arch Linux ARM or Ubuntu. Packages can be updated through the system's package manager.

For package details and development instructions, see [the package guide](docs/layer.md) and [Contributing](CONTRIBUTING.md).

## Documentation

| | |
| --- | --- |
| [Arch installation](docs/install-arch.md) | Download an ISO and install Arch on a computer or virtual machine |
| [Ubuntu installation](docs/install.md) | Install with the official Ubuntu ISO and a seed |
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

The Ubuntu edition of Total.js Developer is based on Ubuntu. It is not an official Ubuntu release and it is not endorsed by Canonical. Ubuntu is a trademark of Canonical Ltd.
The Arch editions are based on Arch Linux or Arch Linux ARM and are not official releases of those projects. Arch Linux and the Arch logo are trademarks of their owners.
