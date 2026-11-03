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

Desktop validation is recorded below. Still required: amd64 installation/BIOS/UEFI,
Arch x86 live startup and Arch installation on both architectures,
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


## Successful ARM64 Desktop installation

A fresh 50 GiB qcow2 disk was installed through the native Calamares UI using
the logo-corrected ISO (`2ecb529664ba22e39b688d384028e62dd63fc6abe9bb364e2d645cfcaeecc437`).
Only the temporary UI automation tool was added to the live session. The
installer reached **All done**, and the installed disk booted with no ISO
attached.

- The account logged in through LightDM with the randomly generated password
  entered in Calamares; Openbox, tint2 and Conky appeared correctly.
- The default target is `graphical.target`. LightDM, NetworkManager, Docker
  and Center were active, with no failed systemd units.
- Installed packages include `totaljs-developer-desktop 1.0.0-1`, Firefox
  `159.0~build1`, Chrome `156.0.8078.79-1`, and Node.js `v24.22.1`.
- The installer and live autologin configuration are absent from the target.
- Center, Code, Flow and pgAdmin returned HTTP 200 over HTTPS with normal
  certificate verification. `docker exec postgres pg_isready` succeeded.
- A normal `systemctl reboot`, authorized with the account's password via
  sudo, changed the boot ID. LightDM and all the same services passed again.

A temporary QA key and password file were added only after installation for
verification, removed afterward, and deleted from the host. The VM was shut
down. Screenshots and service results are retained locally under
`build/own/local/validation/desktop-arm64/`. Ubuntu amd64 and Arch target
installation remain separate pending checks.


## Reported CI and VirtualBox bootloader failures

The supplied CI log identifies amd64 UEFI, despite the initial ARM label.
The 4 MiB split OVMF code image was passed as a PC `-bios` ROM. This exact
failure was reproduced with Homebrew QEMU and its 3.5 MiB code component.
With `q35` and separate pflash code/variables drives, QEMU remained running
and displayed TianoCore. Each test gets a private copy of the variable store;
the firmware template stays read-only. Full amd64 ISO boot is a separate check.

The VirtualBox screenshot shows Ubuntu's native Calamares bootloader raising
inside `get_disk_id()` while listing `/dev/disk/by-id`. The exact installed
Ubuntu module was extracted and the missing-directory exception reproduced.
The shared Ubuntu adapter delegates to that module and treats only that
specific `FileNotFoundError` like its existing no-alias result. Both BIOS
and EFI debconf paths were exercised with the real module; unrelated errors
remain fatal. A fresh complete VirtualBox installation is still required.

The user's visual correction keeps Toto's image and removes only its visible
slideshow attribution text. A fresh ARM64 ISO was built with these changes and its native module-loading
marker passed. Previous ISO validation results continue to identify their own hashes.


## Arch ARM graphical live build

The optional Arch ARM build completed natively in a case-sensitive Linux
container root. The local ISO is
`build/arch-iso-arm/out/totaljs-developer-arch-2026.11.03-aarch64.iso`, SHA-256
`8e0713eade33151738e107c67035d84596f85e9005621013a5e0201c402e36b7`.
It booted with QEMU/HVF and displayed the shared Calamares welcome page;
LightDM and NetworkManager were active and `TOTALJS-CALAMARES-READY` was
observed. The live user belongs to `autologin`; the upstream `alarm` account
and SSH were removed during the build. Evidence is retained under
`build/arch-iso-arm/validation/`.

This establishes native framework packaging and graphical live startup,
not installation to disk. This artifact preceded the request to remove the
visible attribution footer; subsequent builds use the updated shared QML.
The local x86_64 framework and Ubuntu amd64 builds were interrupted when
Colima stopped. Their unfinished containers were retained for diagnosis;
no local amd64 ISO or installation result is claimed.


## End-to-end regression: Ubuntu without by-id aliases

The rebuilt ISO `build/own/local/totaljs-developer-live-arm64-fixed.iso` has
SHA-256 `7c2eb1576afcb0e0f05412cc10c33a20d62d5ad29269e6582f4fd42723cc1c66`.
A fresh 40 GiB disk was installed with the Server edition. QMP keyboard/mouse
events drove the unmodified UI; no automation package was installed in the
live environment. The slideshow retained the mascot image and omitted its
attribution text, as requested.

For this regression only, a live-session watcher removed by-id symlinks that
udev recreated during partitioning. `/dev/disk/by-id` remained absent through
completion. This QA instrumentation is not part of the distro or target.
Calamares reached **All done**; its log confirms execution of the shared
bootloader adapter, native `grub-install --target=arm64-efi` and
`grub-mkconfig`. The installed disk then booted without the ISO.

SSH password authentication with the password created in Calamares succeeded;
no QA key or password file was added to the target. NetworkManager, Docker
and Center were active, no systemd failures were reported, and all four
HTTPS endpoints returned 200 once first-boot containers were ready. PostgreSQL
accepted connections. The password/askpass files were removed from the host
and the VM was shut down. Local evidence is in
`build/own/local/validation/boot-fixes/`.

This covers the reported missing-directory condition in QEMU. It does not
claim a new complete VirtualBox run or a full amd64 ISO boot. Those remain
explicit follow-up checks after uploading the source commit.


## Follow-up review: Arch build and boot checks

The x86_64 kernel boot check selected KVM when available but always passed
`-cpu max`. It now uses `host` for KVM and `max` for TCG, with an optional
`QEMU_ACCEL` override. The ARM workflow now calls the shared boot helper,
which already makes this distinction, retains diagnostics and cleans up QEMU.
Its banner check was exercised against the existing Arch ARM ISO on macOS/HVF:
the live medium reached its banner in 21 seconds. Logs and timing are in
`build/arch-iso-arm/review-boot/`. KVM CPU arguments were checked with command
doubles; this review does not claim execution on a native KVM host.

The ARM builder registered its exit cleanup before refusing an existing mounted
build. A refused second invocation could therefore unmount the earlier build.
Cleanup is now registered only after that refusal guard. A temporary-tree
regression confirms that no cleanup command runs against the previous tree;
the same regression fails against the previous source.

The affected installer, ISO-plumbing, build-guard and publication-policy suites
passed (36 test methods). Workflow YAML, repository checks and whitespace checks
also passed. No ISO recipe contents or installed-target behavior changed in
this follow-up, and no new complete target installation is claimed.


## VirtualBox ARM desktop repaint freeze

Reproduced the reported blank Firefox page, missing launcher/tray icons and
apparently stuck terminal on a disposable copy of the locally installed Ubuntu
ARM Desktop disk. VirtualBox 7.2.22, one CPU, 4 GiB RAM, VMSVGA, 3D disabled.
The user's VM was not changed. The same disk worked under QEMU/HVF.

Inside VirtualBox, `systemd-detect-virt` returned `none`, although the `vboxguest`
module and PCI vendor `0x80ee` were present. Openbox therefore selected picom's
GLX backend. Switching only picom to XRender restored window repainting,
launcher/tray icons, the Center page and terminal input.

The shared `totaljs-openbox` package is now 1.0.1-1. Its backend helper checks
systemd detection, the VirtualBox guest module and the VirtualBox PCI vendor.
Physical machines retain GLX. Its upgrade changes only the previous managed
backend predicate, preserving other session settings and skipping symlinks.
Arch's generated package includes the same helper and upgrade script.

Seven fixture tests passed on Linux, including both VirtualBox detection paths,
physical hardware and idempotent migration with mode/ownership preservation.
The built Debian package was installed onto the disposable disk (adding the
previously missing spice-vdagent dependency from Ubuntu), and a fresh VirtualBox
boot selected XRender automatically despite systemd still returning `none`.
The repository check and shell syntax checks passed. A new container desktop
check types a command into Alacritty and verifies its result; the full container
desktop suite has not been rerun in this follow-up.

The signed APT repository was rebuilt locally and its InRelease signature
verified with the committed public key. Publishing the prepared `pages` branch
is required before online installers can download this update; rebuilding an
ISO alone does not update that package source. No push or publication was made.
The Arch source conversion was checked; a new native Arch package build and
VirtualBox Arch session have not been exercised in this follow-up.

After that boot, Firefox displayed the Center, the tray icons were visible and
an actual command typed into Alacritty created the expected marker file.
Screenshots are retained locally in `build/own/local/validation/virtualbox-desktop/`.
The prepared package branch preserves the previously published signed Arch
repository; its updated native Arch layer package still needs rebuilding/staging.

For a running affected session, `Super+Enter` opens Alacritty; typing
`pkill picom` and pressing Enter stops the frozen compositor even if the input
has not repainted yet. Once the package repository is published, Ubuntu users
can run `sudo apt update && sudo apt install --only-upgrade totaljs-openbox`
and log out/in. A newly installed online target downloads the fixed package
without needing a replacement live ISO.
