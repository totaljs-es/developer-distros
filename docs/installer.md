# Common graphical installer

## Scope and current state

Total.js Developer will use Calamares with a shared interface for Ubuntu and
Arch, amd64 and arm64, in virtual machines and on supported hardware. Public
installation media come first. A separate, non-public TotalVM ISO and its app
integration are a later phase.

Installation requires internet and downloads packages. A graphical live
session hosts Calamares even when the selected target is Server; the target
must not inherit the live desktop, live account or installer.

Implemented in source: shared branding and preview, edition selection,
online bootstrap/finalization jobs, and an opt-in own Ubuntu graphical live
build on native amd64/arm64. The manual `iso-own` workflow builds both and
checks live boot and graphical module loading; it does not automate a target
installation. Ubuntu arm64 was built locally and both Server and Desktop installations, disk-only boot, restart and HTTPS services were verified; see [the evidence](validation-2026-11-03.md).

Pending: validate Ubuntu amd64 installation and the same outcomes on Arch.
Optional Calamares integration and pinned framework package recipes are now
present for both Arch live builders; native ARM live startup was validated locally; x86 startup and target
installation on both architectures remain pending. See [the Arch build instructions](../arch/calamares/README.md).
The current Ubuntu seeds and Arch console installer remain the usable paths.

## Shared interaction

1. Welcome and language; check connectivity, memory, power and disk space.
2. Location and time zone.
3. Keyboard layout with a typing test.
4. Desktop or Server, explaining installed components and internet use.
5. Disk and partitions, naming the device and any destructive changes.
6. Account, hostname and password; no automatic login by default.
7. Summary and explicit confirmation before changing a disk.
8. Installation with progress, useful failure details and Total.js slides.
9. Completion with an optional restart and reminder to remove the medium.

Use Calamares' native partition, locale, keyboard, users, summary and bootloader
modules. Share the page sequence and branding; isolate base-specific work in
profiles and narrowly scoped jobs. Never pass account passwords in command
arguments, log them, or store them in the build configuration.

## Target installation contract

| Step | Ubuntu | Arch / Arch Linux ARM |
| --- | --- | --- |
| Bootstrap an empty target | debootstrap, explicit suite and architecture | Native pacstrap with the correct architecture's repository and keyring |
| Package trust | Ubuntu archive keyring and pinned Total.js signing-key fingerprint | Correct Arch keyring and pinned Total.js signing-key fingerprint |
| Total.js layer | APT sources, refresh, chosen metapackage | Pacman repository, full transaction, chosen metapackage |
| Kernel and initramfs | Supported Ubuntu kernel, initramfs-tools | Architecture-specific kernel, mkinitcpio |
| Boot | GRUB BIOS/UEFI as supported | GRUB BIOS/UEFI on x86_64; systemd-boot UEFI fallback on supported ARM systems |
| Finalization | User groups, network, services, unique machine/SSH identity | Same outcomes with Arch-specific commands |

Do not unpack the running live filesystem into the target: it contains live
accounts, autologin and installer-only configuration. Bootstrap jobs must
take the target mount point from Calamares global storage, validate it and
stop on failure. Account for Calamares' mount/module ordering: the bootstrap
must preserve target mount points and populate a usable package manager before
package, locale, user and bootloader jobs run. No arbitrary disk paths from
shell interpolation and no automatic retry of partitioning after a failure.

Pin a supported Calamares release and build dependencies per base before
enabling installation. Verify availability/buildability on both architectures;
do not assume Arch Linux ARM carries every package that Arch x86_64 provides.
ARM hardware coverage means supported UEFI systems, not every ARM board or a
native installation on Apple Silicon. Secure Boot support is a separate item
requiring an explicit boot-chain design and tests.

The experimental profile currently requires an unencrypted ext4 root, a fresh
target filesystem and native execution. It checks signed repositories and Secure Boot before partitioning; the actual
mounted target must be ext4 without LVM/encryption. Automatic encryption is
disabled in this first profile. These are explicit current implementation limits.

## Implementation and acceptance

1. Review the shared interface in a Linux session, including small screens,
   HiDPI, keyboard navigation and light/dark palette interaction.
2. Execute the new opt-in Ubuntu graphical live builds and add the Arch ones. Preserve console recovery
   and current installers. Keep Calamares and live autologin off target disks.
3. Validate target bootstrap and edition selection in real VMs. Require working
   repositories and enough space before exposing installation confirmation.
4. Prove all eight base/architecture/edition combinations in disposable VMs:
   installation, medium removal, first login, reboot, network and actual
   Code/Flow/PostgreSQL readiness. Test BIOS and UEFI on amd64; UEFI on arm64.
5. Test cancellation, repository outage and download failure, explicit erase
   confirmation, manual partition preservation and installer-log redaction.
6. Validate representative physical hardware separately. VM success does not
   prove drivers, Wi-Fi, suspend or hardware-specific boot support.

## Publication

Calamares changes the installer interface; it does not settle redistribution
rights. The recorded Canonical approval state in [legal.md](legal.md) remains
applicable. The own-image prototype is not cleared for public distribution.
Do not remove that restriction or enable a public release as part of the UI
integration. Keep the TotalVM variant separate from public release assets.
