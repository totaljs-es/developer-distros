# Calamares local validation — 2026-11-03

## Environment

- macOS on Apple Silicon; Homebrew QEMU 11.1.3.
- Docker client 29.9.2; Colima 0.10.3 with Docker Engine 29.5.2.
- Dedicated Colima profile/context `distros` / `colima-distros`, using Apple Virtualization, 4 vCPUs, 6 GiB RAM and a sparse 50 GiB data disk. The default Docker context was preserved; no login service was enabled.
- Native arm64 Ubuntu 26.04 build container. Repository mounted read-only; output in `build/own/local` on the Grey volume.
- QEMU ARM64 tests use HVF, UEFI, 2 vCPUs and 4 GiB RAM. Installation testing attaches only a new, disposable 40 GiB qcow2 disk, never a physical disk.

## Evidence and changes

The own live ISO built locally and booted with LightDM and Calamares. The first graphical startup check reached `TOTALJS-CALAMARES-READY` in 22 seconds. This marker proves module loading, not an installation.

Real UI inspection covered welcome, location, keyboard, edition selection, partitioning, account creation, summary and installation progress at 1280×800. The real repository metadata passed signature verification with the pinned Total.js key.

The native runs exposed and corrected:

- Ubuntu supplies `ckbcomp` through `console-setup`, not a package named `ckbcomp`.
- Ubuntu's vendor NetworkManager configuration leaves wired interfaces unmanaged without a renderer. The live session now explicitly manages them; guest DHCP and HTTPS access to the repository were verified.
- The partition layout must explicitly include the root filesystem. The reviewed plan contains a 1 GiB EFI partition and an ext4 root using the remaining space.
- The native partition job exports its partition list during execution. Repository checks remain before disk changes; the actual target filesystem is checked after mounting.
- Welcome wording no longer repeats "installer". Native Calamares scaling displays the unchanged official Toto PNG completely.
- The minimal target needs `gpgv` for APT signature verification. APT is given the system CA bundle explicitly, and index-update errors are fatal. TLS and package signature checks remain enabled.

A failed installation can leave target processes or mounts behind. Repeated installation tests must use a fresh boot and disposable disk until failure/retry cleanup is validated.

## Scope

This is local experimental evidence, not publication or hardware validation. These runs preceded the source commit; no push, release or production deployment was performed as part of local validation. Ubuntu amd64 and both Arch live integrations have not been validated by these runs. Target installation completion and boot evidence must be recorded separately below before claiming success.

## Successful ARM64 Server installation

The final clean run used the rebuilt ISO as-is. Only `xdotool` was added to the
live session to automate the native GUI; no installer or network configuration
was patched in that run. A new 40 GiB qcow2 disk was selected in the native
summary and confirmation dialog. Calamares completed the full job sequence
and displayed **All done**.

- Calamares / calamares-data: `3.3.14-0ubuntu25.26.04.1`.
- ISO size: 1,374,906,368 bytes (approximately 1.28 GiB).
- ISO SHA-256: `8c2a9d6669a427a760854da08ff8d1c83f84e1c695a70f0b45d7aad401a0016b`.
- The disk contains `totaljs-developer-server 1.0.0-1` and Node.js `v24.22.1`.
- The installer and live autologin configuration are absent from the target.
- The machine booted with the ISO removed. The synthetic `totalqa` account
  accessed it over SSH with a temporary QA key; membership includes sudo,
  Docker and the Total.js developer group. This verifies key authentication,
  not a separate test of console password authentication.
- NetworkManager, SSH, Docker and Center are active; no systemd unit failures
  were reported. The default is `multi-user.target`.
- Center `/health/`, Code `/`, Flow `/` and pgAdmin `/misc/ping` each returned
  HTTP 200 over HTTPS, using the installed CA trust with normal certificate
  verification (no insecure TLS option). PostgreSQL `pg_isready` succeeded.
- A normal Ctrl+Alt+Delete restart changed the boot ID. SSH, the same HTTPS
  endpoints and PostgreSQL were verified again afterward.

The temporary QA key was injected only after Calamares completed, to permit
post-boot verification. Its authorization was removed after the checks, and
its private key was deleted from the host. The test disk is a local QA
artifact, not a distributable image or the future TotalVM image.

Evidence remains locally under `build/own/local/validation/`: build log,
welcome/edition/summary/completion PNGs, first-boot SSH output, post-restart
checks and `SHA256SUMS`. The ISO is
`build/own/local/totaljs-developer-live-arm64-before-logo.iso` (retained installation-validation baseline).

Still required: Ubuntu Desktop installation, amd64 installation/BIOS/UEFI,
Arch live packaging/integration and installation on both architectures,
physical hardware, and failure/retry cleanup. Encryption, LVM root and Secure
Boot remain outside this experimental profile's supported scope.


## Logo rendering follow-up

The SVG supplied from the official Toto brand directory matches
`shared/branding/logo-totaljs.svg` byte for byte. The original remains unchanged.
Calamares now uses a generated Qt-compatible SVG with equivalent masks and
inlined embedded images. The logo geometry and embedded image bytes are
preserved. Offscreen Qt and full SVG reference renders were visually compared.

The ISO was rebuilt successfully and booted again in native ARM64 QEMU/HVF.
Calamares reached `TOTALJS-CALAMARES-READY`; visual inspection of the welcome
page confirmed the corrected logo and unchanged Toto artwork. Screenshot:
`build/own/local/validation/welcome-logo-fixed.png`.

- Current ISO: `build/own/local/totaljs-developer-live-arm64.iso`.
- Size: 1,374,910,464 bytes.
- SHA-256: `2ecb529664ba22e39b688d384028e62dd63fc6abe9bb364e2d645cfcaeecc437`.

This follow-up checked live startup and appearance; the complete Server
installation was not repeated for the branding-only rebuild. The installation
and restart results above belong to the retained baseline ISO and its hash.
