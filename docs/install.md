# Install Total.js Developer

Total.js Developer installs on top of **Ubuntu Server 26.04 LTS**. You start the computer with the official ISO of Ubuntu and, next to it, a small
**seed** that says what to install. The installer of Ubuntu does the rest and asks you the usual questions.

## What you need

- An **amd64** computer (Intel or AMD) or a virtual machine of that type. On a Mac with Apple Silicon, use the images of
  [TotalVM](https://totalvm.totaljs.es).
- 4 GB of memory (8 GB or more is better with the desktop) and 30 GB of disk.
- A **network connection** during the installation (cable or Wi-Fi): the installer downloads Total.js Developer while it installs.
- Two USB sticks, or one stick and a second one for the seed; or, in a virtual machine, two virtual drives.

## 1. Download

1. The **official ISO of Ubuntu Server 26.04 LTS**, unmodified, from <https://releases.ubuntu.com/26.04/>
   (`ubuntu-26.04.1-live-server-amd64.iso` or the newest 26.04.x). Check it with the checksum in the file `SHA256SUMS` of that page:

   ```bash
   sha256sum ubuntu-26.04.1-live-server-amd64.iso
   ```

2. The **seed** of the edition that you want, from the [releases](../../../releases) of this repository:

   | Edition | File |
   | --- | --- |
   | Desktop (Openbox, Firefox, terminal, files) | `totaljs-developer-desktop-seed.iso` |
   | Server (command line only) | `totaljs-developer-server-seed.iso` |

   Check it with `SHA256SUMS`, which is in the same release:

   ```bash
   sha256sum -c SHA256SUMS --ignore-missing
   ```

   The seeds also carry a signed attestation of where they were built. If you use the GitHub CLI:

   ```bash
   gh attestation verify totaljs-developer-desktop-seed.iso --repo totaljs-es/developer-distros
   ```

## 2. Prepare the devices

**On a computer**

1. Write the ISO of Ubuntu to a USB stick, with [balenaEtcher](https://etcher.balena.io) or with `dd`.
2. Write the seed to **another** USB stick in the same way. The seed is a few kilobytes: any stick is enough.

**In a virtual machine** (VirtualBox, VMware, QEMU, Proxmox...)

1. Create a machine with UEFI, 4 GB of memory or more and a 30 GB disk.
2. Connect the ISO of Ubuntu as the first optical drive and the seed as a **second** optical drive (or a second disk).

## 3. Install

1. Connect both devices and start the computer from the one with the ISO of Ubuntu (usually with `F12`, `Esc` or `F2` at power on).
2. In the menu of Ubuntu, choose **Try or Install Ubuntu Server**.
3. When the installer finds the seed, it asks whether to continue with the autoinstall. Type `yes` and press Enter.
4. Answer the questions: language, keyboard, network, disk and who you are (your name, the name of the computer, your user and your password).
5. Wait. The installer puts Ubuntu on the disk and then downloads and installs Total.js Developer. When it finishes it asks you to restart:
   take out both devices and press Enter.

## After the first start

- **Server edition:** log in on the console or with SSH (`ssh your-user@address`). Open `http://totaljs.developer` from any computer that can
  reach this one (see *Use it from another computer* in [How to use it](using.md)).
- **Desktop edition:** the login screen appears. Log in and the desktop opens. Total.js Center is the second button of the panel, and `Super + B`
  opens it in Firefox.
- The first time the services start, they download their images (Code, Flow, PostgreSQL and pgAdmin). Give them a few minutes and a connection:
  Total.js Center shows when each one is ready.

## If something does not work

| What you see | What to do |
| --- | --- |
| The installer does not ask about the autoinstall | The seed was not found. Connect it before you start the computer, and check that it is a separate device from the one with the ISO of Ubuntu. |
| It says that it cannot reach the repository | The installer needs the network from the start. Connect the cable or choose the Wi-Fi when it asks about the network, and start again. |
| It stops with an error | Press Enter to open a shell and read `/var/log/installer/`, or start again. |
| After restarting, the services do not answer | They download their images in the first minutes. Look at `systemctl status totaljs-proxy totaljs-code totaljs-flow totaljs-postgres`. |

## Remove the installation

Total.js Developer is a set of packages: `sudo apt remove totaljs-developer-desktop` (or `-server`) removes the layer and keeps your projects in `/www`.
