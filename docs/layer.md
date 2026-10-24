# The Total.js layer as packages

Today the Total.js layer (Node.js, Docker, the developer services, the console, the DNS) is installed by the scripts `provision/*.sh` of each recipe while an image for TotalVM is built. An installable ISO cannot run those scripts at install time, and two copies of the same layer would drift apart. The layer has to be a set of **packages** that the ISO installs and that the image builder installs too.

This page is the design. Nothing in it is built yet; it was written by reading the recipes of the server edition (`tools/image-builder/images/developer-ubuntu-server`).

## What the server layer is today

| Step | What it does | Needs TotalVM? |
|---|---|---|
| `00-base.sh` | Tools (git, curl, jq, tmux, build-essential...), SSH with its own host keys, `ufw`, `fail2ban`, removes snap and Ubuntu Pro | The tools and SSH: no. The rest: **yes** (see below) |
| `10-node-totaljs.sh` | Pinned Node.js LTS tarball (checked with a SHA-256), `total5` and `total.js` as global npm packages | No, but the tarball is **arm64 only** |
| `20-services.sh` | Docker CE and the Compose plugin, from the repository of Docker | No |
| `25-code-docker.sh` | The stacks in `/www` (proxy, Code, Flow, PostgreSQL, pgAdmin) as Compose files, with their systemd units and `totaljs-*-open` helpers; pulls the images | No |
| `28-dns.sh` | `dnsmasq` with the wildcard domain `totaljs.developer` and a network guard | No |
| `35-totalcenter.sh`, `40-totalfetch.sh` | Total.js Center (a Node.js app and its service) and the `totalfetch` summary of the terminal | No |
| `45-console-wizard.sh` | First boot: asks for the user, locks the build user `totaljs` | The idea is shared; the way is not (the installer already asks for a user) |
| `30-branding.sh` | Plymouth theme, GRUB settings | No (desktop and server share it) |
| `22-rosetta.sh` | Rosetta for Intel binaries | **Yes, TotalVM only** |
| `27-package-repository.sh` | The repository of these packages | No |
| `90-cleanup.sh` | Netplan for the server, power settings, empties the image | Mostly image build |

What is **TotalVM only** and must not reach an ISO: the kernel of the HWE bootstrap, the workarounds of the NAT of Apple (no IPv6, no pipelining, MTU), `discard` removed from `fstab`, the virtiofs mount of `/www` with its first-boot seed, `totalvm-growroot`, Rosetta, and the netplan of the image.

## The packages

```text
totaljs-developer-server      meta-package: depends on everything below
  totaljs-developer-release   the key and the source of APT / Pacman (exists)
  totaljs-node                Node.js LTS, total5 and total.js
  totaljs-docker-stack        Docker Engine, /www with the Compose stacks and their units (done)
  totaljs-docker-source       the repository of Docker (done)
  totaljs-dns                 the local domain: totaljs.developer and everything under it is this computer (done)
  totaljs-center              Total.js Center, a Total.js 5 application on :8010 (done)
  totaljs-fetch               the terminal summary
  totaljs-brand               Plymouth theme and GRUB settings (done)

totaljs-developer-desktop     meta-package: the server layer plus
  totaljs-desktop             Openbox integration (exists), the menu, Total Center in the desktop, the browser, the clipboard...
  totaljs-wallpapers          the twelve wallpapers (done)

totalvm-guest                 only for TotalVM: Rosetta, the virtiofs /www and its seed, growroot, the workarounds of the NAT of Apple
```

An ISO installs `totaljs-developer-server` or `totaljs-developer-desktop`. The image builder installs the same one, plus `totalvm-guest`. The meta-packages carry only `Depends`: each piece is a package of its own so it can be updated alone.

`totaljs-developer-release` has Rosetta inside today. It moves to `totalvm-guest` in a version that replaces it, because systems already installed have it.

## The first person of the system

With an ISO the installer does not create the person in the system it installs: it hands the request to cloud-init, which creates them the first time the new system boots. At install time there is nobody to put in the group yet. `totaljs-developer-server` therefore ships `/usr/lib/totaljs-developer/add-first-user` and the unit `totaljs-developer-first-user.service`, which runs after `cloud-final.service`; the script adds the first regular person to `totaljs-developer` once, and the marker `/var/lib/totaljs-developer/first-user` stops it from running again (a person taken out of the group on purpose stays out). The package also runs it when it is installed, for systems that already have people.

## Which Ubuntu

The repository serves **Ubuntu 26.04 LTS** (`resolute`) only. The images of TotalVM that exist (24.04, arm64) keep using their own repository at totalvm.totaljs.es and are not affected by this one: the packages here are new, and they reach TotalVM when its images are rebuilt on them. The builder can serve more series (`SUITES`), and the packages do not depend on the series.

## Things a package must not do

- **Assume a user called `totaljs`.** In an image that user is made by `cloud-init`; with an ISO the installer creates the real one. The packages own a **group** (`totaljs-developer`) and `/www` belongs to it; the postinst adds the first regular user to it and to `docker`.
- **Download anything big in the postinst, or pull Docker images.** Images are pulled when the services start for the first time, so installing is quick and does not depend on Docker Hub.
- **Hardcode an architecture.** The Node.js tarball is the case today (`linux-arm64`).
- **Touch what the person owns:** projects, Compose files that were edited, home-directory configuration.

## Decisions taken

1. **Docker:** Docker CE from the repository of Docker, as the recipes do. `totaljs-developer-release` configures that source (key and `docker.list`), so the Docker packages come from apt like the rest.
2. **Node.js:** the pinned tarball of nodejs.org with its SHA-256, one for each architecture, downloaded by the `totaljs-node` package. The repository stays small and the runtime is the same on every system. The version and the checksums live in the package, not in a script of an image.
3. **The developer user:** the group `totaljs-developer`, not a fixed user. `/www` belongs to the group, and the postinst adds the first regular user (UID 1000 or higher) to it and to `docker`.

## Versions

The versions are in `packages/totaljs-node/files/usr/share/totaljs-node/versions` and nowhere else. Node.js is the newest 24.x LTS (24.22.1, published on 2026-10-20) and not the 24.18.0 of the images of July, which is older than the security releases of October; `total5` is the one that npm publishes as latest (0.0.19) and `total.js` stays at 3.4.13. Changing them is a new version of the package.

## Order of work

1. **Started:** `packages/totaljs-node` (Node.js 24 LTS, pinned for amd64 and arm64, with `total5` and `total.js`) and the meta-package `totaljs-developer-server` (the group, the tools, SSH, the firewall). `tools/package-repo/build.sh` builds them and the CI installs them in a clean Ubuntu 26.04 and removes them. `totaljs-brand` (the boot splash of `shared/plymouth` and the quiet-boot setting of GRUB) is in `totaljs-developer-server`, and `totaljs-wallpapers` (the twelve wallpapers, 17 MB) is a package of its own for the desktop. `totaljs-docker-stack` (Docker Engine and the services of `/www`: the proxy, Code, Flow, PostgreSQL and pgAdmin, as Compose files that are copied to `/www` only when missing, with a systemd service each) and `totaljs-docker-source` (the key and the source of the repository of Docker, written for the series of the system) are done. Because Docker comes from its own repository, the installer does the install in two steps: first `totaljs-developer-release` and `totaljs-docker-source`, then `apt-get update`, then the layer. `totaljs-dns` (dnsmasq on its own loopback address 127.0.0.100, answering only `totaljs.developer`, and a drop-in that makes systemd-resolved send that domain, and nothing else, to it) is done too: unlike the TotalVM images it needs no refresh script, because the name always points to `127.0.0.1` and the machine's own address is not involved; what TotalVM needs to reach the guest from the Mac goes in its own package later. `totaljs-center` (the front door at `http://totaljs.developer`) is a Total.js 5 application with a new design: tools with their state, the projects of `/www` with their addresses, how to connect to PostgreSQL and the state of the computer. It runs as its own user, in no group, with a hardened unit; it reads the services through systemd, so it needs no access to Docker. Still to come: the terminal summary (`totaljs-fetch`).
2. The seed of the ISO installs it (menu entry *Server*), and the CI boots the result and checks the services.
3. The image builder installs it too, and `totalvm-guest` takes what is only for TotalVM.
4. The desktop edition on the same base.
