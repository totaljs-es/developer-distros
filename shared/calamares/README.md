# Shared Calamares installer

Shared branding, a non-installing UI preview and experimental online
installation jobs. The own Ubuntu live-image builder can include the installer
on native amd64 and arm64 builds. Ubuntu arm64 live startup, Server and Desktop installation, disk-only boot, restart and
HTTPS services were validated locally; see [the evidence](../../docs/validation-2026-11-03.md).
Ubuntu amd64 and Arch validation remain pending. Public release workflows are unchanged.

The installer is Total.js Developer on both Ubuntu and Arch, with the same
pages, colors, official logo and unmodified Toto artwork. Installation will
require internet and download packages, rather than copy the live desktop
into the target. See [the installation design](../../docs/installer.md).

## Preview on Linux

Install Calamares and its welcome, locale and keyboard modules using the
distribution's packages. Generate a fresh preview directory:

```bash
python3 shared/calamares/render.py --base ubuntu --arch amd64 --output /tmp/totaljs-calamares-preview
calamares -c /tmp/totaljs-calamares-preview
```

Use `--base arch`, `--arch arm64` and/or `--edition server` for other build
identities. Every combination uses the same visual sources. The output is
self-contained for branding and configuration. Its `qml` symlink reuses the
installed runtime at `/usr/share/calamares/qml`; pass `--calamares-data PATH`
if your Linux package uses another data directory. Generation can run on macOS,
but launching requires Linux with that runtime installed.

The preview includes welcome, location and keyboard pages only. It has no
partition module, execution phase, user creation, completion page or reboot.
Location does not change the live system timezone. Keyboard testing may change
the current graphical session's keyboard layout; use a disposable live session
and run the preview as a regular user. It does not simulate a successful
installation. The slideshow is supplied for the future execution phase and
is not displayed by this preview. Native Qt rendering was reviewed on Ubuntu arm64; other combinations still
need graphical review. Generation tests do not validate the interface.

The renderer refuses an existing destination. It never installs packages or
edits system configuration. No root privileges are needed for generation.
JSON-formatted configuration is valid YAML, which Calamares reads natively.

## Experimental online installation

Use disposable VMs for this stage. The configuration contains real partition
and installation jobs, and can erase the disk selected in the summary.

```bash
sudo python3 shared/calamares/render.py --mode installer --base ubuntu --arch amd64 --output /usr/share/totaljs-installer
sudo calamares -c /usr/share/totaljs-installer
```

The native Linux live system needs Calamares and its standard modules, Python
job support, `gpg`, `gpgv`, `chroot`, filesystem tools and `debootstrap` (Ubuntu)
or `pacstrap` (Arch). `setup-live.sh` configures the graphical live session
inside a build rootfs; it requires `TOTALJS_LIVE_BUILD=1` and must never run
on an installed system. See [the Ubuntu builder](../../iso/own/README.md).

The shared pages select Desktop or Server. The custom jobs verify signed
repository metadata before partitioning, bootstrap a fresh target using the
base's package manager, install the Total.js packages, and finalize services.
Calamares handles partitioning, locale, keyboard, account creation and the
standard bootloader path. Ubuntu delegates through a small adapter to its
installed native bootloader module: a missing `/dev/disk/by-id` skips only
optional GRUB debconf device preseeding, just as an unmatched by-id alias does.
GRUB installation and other errors still use the native implementation. NetworkManager provides the live and installed
network connection in both editions (console tools only in Server). Arch ARM has a separate UEFI fallback loader job
for its `Image` kernel and requires the ESP mounted at `/boot`.

The first profile supports an unencrypted ext4 root without LVM. ARM requires
UEFI. Repository signatures and Secure Boot are checked before partitioning;
the actual root filesystem is checked after mounting. Automatic encryption is
disabled pending implementation and tests. The target root
must be formatted/empty. No live account, live autologin, live network policy
or installer is copied into the target. The root account is locked and the
new user has password-protected sudo; graphical autologin is disabled.

`--repository` may select another HTTPS location signed by the same pinned
Total.js key. It cannot disable signatures, change the trusted fingerprint,
use credentials in a URL or use HTTP. The generated installer profile records
`validatedInVM: false`; generating it is not proof of an installation.

The Arch profile and bootstrap code are present. Both Arch live recipes now
have optional Calamares integration and pinned package recipes; their console
installer remains the default. Native ARM live startup was validated locally;
Arch installation to disk and x86 live startup remain pending. See [Arch packaging](../../arch/calamares/README.md).
Source integration does not establish successful Arch installation.

```bash
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-calamares.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-calamares-install.py
```

These tests check profiles, trust/target guards, package transaction order,
failure propagation and QEMU command construction with doubles. They do not
run a package manager, Calamares or a VM.

## Artwork and translations

Logo and Toto files are copied from `shared/branding` during generation, not
redrawn or duplicated in the source tree. The official logo SVG is kept byte
for byte. For Qt 6.7+, the renderer also emits `logo-totaljs-qt.svg`: its
unsupported clip paths become equivalent SVG masks, and image references are
inlined without changing their pixel data or the logo geometry. Calamares uses
this compatible SVG for its sidebar and window icon. Qt support is documented
in [the Qt SVG feature list](https://doc.qt.io/qt-6/svgextensions.html). Toto's license and attribution are
included in each output. The artwork retains its existing licenses. The mascot
image remains in the welcome/slideshow; the visible attribution footer is
omitted so installation text focuses on the distribution.

Calamares owns translations of its standard pages. Custom QML strings use
`qsTr()` with English as the source language; translation catalogs must be
added before those slides are included in a release.

Upstream configuration references:
[settings](https://github.com/calamares/calamares/blob/calamares/settings.conf),
[branding](https://github.com/calamares/calamares/blob/calamares/src/branding/default/branding.desc),
[welcome](https://github.com/calamares/calamares/blob/calamares/src/modules/welcome/welcome.conf).
