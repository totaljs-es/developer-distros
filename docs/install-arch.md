# Install Total.js Developer on Arch

Choose **Desktop** for the graphical environment, or **Server** for the command line. Both include the Total.js development tools and services.

## Download

[Arch Linux Edition 1.0.0](https://github.com/totaljs-es/developer-distros/releases/tag/v1.0.0-arch)

| Computer or virtual machine | ISO |
| --- | --- |
| Intel or AMD | [x86_64](https://github.com/totaljs-es/developer-distros/releases/download/v1.0.0-arch/totaljs-arch-amd64.iso) |
| ARM64, including Apple Silicon Macs | [aarch64](https://github.com/totaljs-es/developer-distros/releases/download/v1.0.0-arch/totaljs-arch-arm64.iso) |

Download `SHA256SUMS` from the same release and run `sha256sum -c SHA256SUMS --ignore-missing` in the directory containing the ISO. Check that the command reports `OK` for the file you downloaded. On macOS, run `shasum -a 256` followed by the ISO filename and compare the result with the matching entry in `SHA256SUMS`.

You need **4 GB RAM**, a **30 GB disk** and an **internet connection** throughout installation.

## Prepare the machine

**Virtual machine:** create a Linux VM with the matching architecture, attach the ISO as its boot drive and allocate the memory and disk above. Use UEFI and disable Secure Boot. ARM64 requires UEFI.

**UTM on Apple Silicon:** choose **Virtualize → Linux**, select the **aarch64** ISO and use a new virtual disk.

**Intel/AMD computer:** write the **x86_64** ISO to a USB drive with your usual image-writing tool, then boot from that USB drive with Secure Boot disabled.

## Install

1. Boot the ISO and select the installer entry. On ARM64, the boot entry sets the initial edition. Calamares opens automatically.
2. In **Welcome**, choose the installer language. Set your time zone in **Location** and your layout in **Keyboard**.
3. In **Edition**, choose **Desktop** or **Server**.
4. In **Partitions**, select the target disk. For a clean install, choose **Erase disk**. **This deletes all data on the selected disk.**
5. In **Users**, set your username, computer name and password. Review the selected disk and planned changes in **Summary**, then choose **Install** and confirm with **Install Now**.
6. After installation finishes, remove the ISO or USB drive and restart from the installed disk.

## First login

Log in with the account you created. On the desktop, open **Total.js Center** or visit `https://totaljs.developer` in the browser.

The services may take a few minutes to become ready on their first start. Center shows their status and links to Code, Flow and pgAdmin.

[How to use Total.js Developer](using.md)

If you prefer upstream installation media, see [the alternative installation instructions](install-arch-upstream.md).
