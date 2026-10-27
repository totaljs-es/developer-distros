# Install Total.js Developer on Arch

Choose **Desktop** for the graphical environment, or **Server** for the command line. Both include the Total.js development tools and services.

## Download

[Arch preview — 27 October 2026](https://github.com/totaljs-es/developer-distros/releases/tag/arch-2026.10.27)

| Computer or virtual machine | ISO |
| --- | --- |
| Intel or AMD | [x86_64](https://github.com/totaljs-es/developer-distros/releases/download/arch-2026.10.27/totaljs-developer-arch-2026.10.27-x86_64.iso) |
| ARM64, including Apple Silicon Macs | [aarch64](https://github.com/totaljs-es/developer-distros/releases/download/arch-2026.10.27/totaljs-developer-arch-2026.10.27-aarch64.iso) |

You need **4 GB RAM**, a **30 GB disk** and an **internet connection** throughout installation.

## Prepare the machine

**Virtual machine:** create a Linux VM with the matching architecture, attach the ISO as its boot drive and allocate the memory and disk above. Use UEFI, particularly for ARM64.

**UTM on Apple Silicon:** choose **Virtualize → Linux**, select the **aarch64** ISO and use a new virtual disk.

**Intel/AMD computer:** write the **x86_64** ISO to a USB drive with your usual image-writing tool, then boot from that USB drive.

## Install

1. Start from the ISO and choose **Desktop** or **Server**.
2. Press **Enter** when the installer offers to begin.
3. Enter the disk, keyboard layout, time zone, computer name, username and password when prompted. **Installation erases the selected disk.**
4. Let the installer finish downloading and installing the system.
5. Remove the ISO or USB drive and restart from the installed disk.

## First login

Log in with the account you created. On the desktop, open **Total.js Center** or visit `https://totaljs.developer` in the browser.

The services may take a few minutes to become ready on their first start. Center shows their status and links to Code, Flow and pgAdmin.

[How to use Total.js Developer](using.md)

If you prefer upstream installation media, see [the alternative installation instructions](install-arch-upstream.md).
