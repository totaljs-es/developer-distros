# The packages of Total.js Developer

Total.js Developer is not a distribution that patches Ubuntu: it is a **set of packages** in a signed repository, installed on top of Ubuntu Server 26.04 LTS.
The installer and any Ubuntu that you already have install the same packages, and they are updated with `apt`.

## The packages

```text
totaljs-developer-server      meta-package: the server edition
  totaljs-developer-release   the key and the source of apt (and of Pacman) of this repository
  totaljs-node                Node.js LTS, total4 and total5
  totaljs-fnm                 fnm, the manager of versions of Node.js (the one of the system stays the default)
  totaljs-docker-source       the repository of Docker, where Docker Engine and Compose come from
  totaljs-docker-stack        /www with the Compose files and the units of the services: proxy, Code, Flow, PostgreSQL and pgAdmin
  totaljs-https               the authority of this machine and the certificate of *.totaljs.developer, trusted by the system, Node.js and Firefox
  totaljs-services            the optional services (Redis, Mailpit, MongoDB), off until `totaljs-service enable`
  totaljs-dns                 the local domain: totaljs.developer and everything under it is this computer
  totaljs-center              Total.js Center, a Total.js 5 application on the port 8010
  totaljs-fetch               the summary of the system in the terminal
  totaljs-brand               the boot splash of Plymouth and the quiet boot of GRUB

totaljs-developer-desktop     meta-package: the server edition plus
  totaljs-openbox             Openbox with the theme of Total.js, Tint2, Rofi, Alacritty, PCManFM, LightDM, the menu and the shortcuts
  totaljs-conky               the widget on the wallpaper, with four profiles (system, services, compact and clock)
  totaljs-wallpapers          the twelve wallpapers
  totaljs-mozilla-source      the repository of Mozilla, where Firefox comes from (Ubuntu offers only a snap)
  totaljs-chrome-source       the repository of Google, where Google Chrome comes from
```

The meta-packages have only `Depends`: each piece is a package of its own and can be updated alone. To install, add the sources first and then the layer:

```bash
sudo apt install totaljs-developer-release totaljs-docker-source   # and totaljs-mozilla-source and totaljs-chrome-source for the desktop edition
sudo apt update
sudo apt install totaljs-developer-server                          # or totaljs-developer-desktop
```

Docker and Firefox come from their own repositories, which `apt` has to know before it resolves the layer: that is why there are two steps.

## What each one does

- **totaljs-node.** The Node.js tarball is pinned in `packages/totaljs-node/files/usr/share/totaljs-node/versions` with its SHA-256 for amd64 and arm64, and is downloaded and
  checked when the package is installed. `total4` and `total5` are installed as global npm packages. The versions are in that file and nowhere else.
- **totaljs-fnm.** The pinned release of fnm (with its SHA-256, for amd64 and arm64) is downloaded when the package is installed, and `fnm env` goes in `/etc/bash.bashrc` between two marks.
  The Node.js of `totaljs-node` is still the default: the person installs the others with `fnm install`.
- **totaljs-https.** An authority is made on the first install (its key stays in `/var/lib/totaljs-developer/ca`, readable only by root, and never leaves the machine) and signs a certificate for `totaljs.developer` and `*.totaljs.developer` that nginx-proxy uses from `/www/proxy/data/certs`. The authority goes to the trust of the system, to `NODE_EXTRA_CA_CERTS` (`/etc/environment`) and to the policies of Firefox.
- **totaljs-services.** A catalog of Compose files in `/usr/share/totaljs-developer/catalog` and the template unit `totaljs-service@.service`. `totaljs-service enable NAME` copies the file to `/www/services/NAME` (never overwriting) and starts it; nothing is published on the host.
- **totaljs-docker-stack.** Puts the Compose files in `/www` only when they are missing, and never overwrites what the person edited. Each stack has its own unit
  (`totaljs-proxy`, `totaljs-code`, `totaljs-flow`, `totaljs-postgres`). The images are pulled when the services start for the first time, not when the package is installed.
  PostgreSQL is not published: only the containers of the network `proxy` reach it. The password of pgAdmin is made at install time, different on each system.
- **totaljs-dns.** `dnsmasq` listens on its own address of the loopback (`127.0.0.100`) and answers only `totaljs.developer`, and a drop-in of `systemd-resolved` sends that
  domain, and nothing else, to it. The rest of the DNS of the system is not touched.
- **totaljs-center.** A Total.js 5 application that runs as its own user, in no group, with a hardened unit. It reads the state of the services through systemd, so it needs
  no access to Docker.
- **totaljs-conky.** The profiles are in `/etc/skel/.config/conky` (copied to each person, who can edit them) and say where the window is and how big; what is drawn (rings, bars, cards)
  is the Lua and Cairo script `/usr/share/totaljs-conky/totaljs.lua`. The network interface is the one of the default route, and the state of the services comes from systemd, so it needs no access to Docker.
- **totaljs-openbox.** The configuration of each person is copied from `/etc/skel` when the person is created, and to the people that already exist only if they have none.
  The compositor is `picom`: GLX on a real computer and xrender in a virtual machine.
  On a first install it also writes `/etc/netplan/90-totaljs-desktop.yaml` so that NetworkManager (the icon of the network of the panel) manages the network, as in the desktop of Ubuntu; it takes effect at the next start, and is removed with the package.

## The group of the system

The installer does not create the person in the system it installs: it hands the request to cloud-init, which creates them the first time the new system starts.
`totaljs-developer-server` therefore has a unit, `totaljs-developer-first-user.service`, that adds the first regular person to the group `totaljs-developer` (and to `docker`) once
the person exists. The marker `/var/lib/totaljs-developer/first-user` stops it from running again, so a person taken out of the group on purpose stays out. `/www` belongs to the group.

## Which Ubuntu

The repository serves **Ubuntu 26.04 LTS** (`resolute`) for `amd64` and `arm64`, and the packages do not depend on the series.

## Rules of the packages

- They never assume a user called `totaljs`: they own a group, not a person.
- They download nothing big in the `postinst` and pull no Docker images.
- They never hardcode an architecture.
- They never touch what the person owns: the projects, the Compose files that were edited, the configuration of the home directory.
- A file that another package of Ubuntu owns is never shipped: the configuration goes in a drop-in (`conf.d`) or in `/etc/skel`.

## Tests

`tools/package-repo/test-install.sh` installs the server edition in a clean Ubuntu 26.04, checks what it promises and removes it, checking that nothing stays. `test-desktop.sh` installs the
desktop edition, starts its session in a virtual screen and takes screenshots. `iso/ubuntu/test-install.sh` installs the system with the installer in QEMU and boots it.

## Versions

apt updates a package only when its version goes up. So **a package whose files change after a release gets a new version**: the revision after the dash for a fix (`1.0.0-1` → `1.0.0-2`), the number before it for a new feature (`1.0.0` → `1.1.0-1`).
Packages that depend on another one ask for `>=`, never `=`, so that one can be updated alone. `tools/package-repo/check-versions.sh` compares each package with the last release (the tag `v*`) and fails if one changed with the same version; the CI runs it.
Before the first release nothing is compared, and the packages can be rebuilt with the same number.
