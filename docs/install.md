# Install Total.js Developer

Total.js Developer installs on top of **Ubuntu Server 26.04 LTS**. You start the machine with the official ISO of Ubuntu and, next to it, a small
**seed** that says what to install. The installer of Ubuntu does the rest and asks you the usual questions.

It is made to run in a **virtual machine**, which is the easiest way to have it, and it also installs on a real computer in the same way.

## What you need

- An **amd64** machine (Intel or AMD): a virtual machine of that type, or a computer. On a Mac with Apple Silicon, use the images of
  [TotalVM](https://totalvm.totaljs.es).
- 4 GB of memory (8 GB or more is better with the desktop), 2 processor cores or more, and 30 GB of disk.
- **An internet connection during the installation, in a virtual machine as well as on a computer.** The installer downloads Total.js Developer
  while it installs. A virtual machine gets it from its host with the usual network of the program (NAT or bridge); a computer needs a cable or Wi-Fi that the
  installer of Ubuntu can use.

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

## 2. Prepare the machine

### In a virtual machine

Create a machine with these settings, in the program that you use (VirtualBox, VMware, Hyper-V, QEMU/KVM, Proxmox, Parallels...):

| Setting | Value |
| --- | --- |
| Type | Linux, Ubuntu 64-bit |
| Memory | 4 GB or more (8 GB with the desktop) |
| Processors | 2 or more |
| Disk | 30 GB or more |
| Firmware | UEFI, or BIOS: both work |
| Network | NAT or bridge, with internet |
| First optical drive | the **ISO of Ubuntu** |
| Second optical drive | the **seed** |

The two files are connected as two virtual CD drives (or, if the program prefers, the seed as a second small disk). With QEMU it is:

```bash
qemu-img create -f qcow2 totaljs.qcow2 30G
qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 -nic user,model=virtio-net-pci \
  -drive file=totaljs.qcow2,if=virtio \
  -drive file=ubuntu-26.04.1-live-server-amd64.iso,media=cdrom \
  -drive file=totaljs-developer-desktop-seed.iso,media=cdrom \
  -boot d
```

### On a computer

1. Write the ISO of Ubuntu to a USB stick, with [balenaEtcher](https://etcher.balena.io) or with `dd`.
2. Write the seed to **another** USB stick in the same way. The seed is a few kilobytes: any stick is enough.
3. Connect both and start the computer from the one with the ISO of Ubuntu. Most computers show a boot menu with a key at power on (`F12`, `F10`, `Esc` or
   `F2`; on a Mac, hold `Option`). Choose the stick, in UEFI mode.

The computer has to be one on which Ubuntu Server 26.04 runs: if Ubuntu does not see your disk, your network card or your keyboard, Total.js Developer will not either.

## 3. Install

1. Start the machine from the ISO of Ubuntu, with the seed connected.
2. In the menu of Ubuntu, choose **Try or Install Ubuntu Server**.
3. When the installer finds the seed, it asks whether to continue with the autoinstall. Type `yes` and press Enter.
4. Answer the questions: language, keyboard, network, disk and who you are (your name, the name of the machine, your user and your password).
5. Wait. The installer puts Ubuntu on the disk and then downloads and installs Total.js Developer. When it finishes it asks you to restart:
   disconnect the ISO and the seed (take out the sticks, or eject the virtual drives) and press Enter.

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
| The installer does not ask about the autoinstall | The seed was not found. Connect it before you start the machine, and check that it is a separate drive from the one with the ISO of Ubuntu. |
| It says that it cannot reach the repository | The installer needs internet from the start. Check the network of the virtual machine (NAT or bridge), or connect the cable or choose the Wi-Fi when the installer asks about the network, and start again. |
| It stops with an error | Press Enter to open a shell and read `/var/log/installer/`, or start again. |
| After restarting, the services do not answer | They download their images in the first minutes. Look at `systemctl status totaljs-proxy totaljs-code totaljs-flow totaljs-postgres`. |

## Remove the installation

Total.js Developer is a set of packages: `sudo apt remove totaljs-developer-desktop` (or `-server`) removes the layer and keeps your projects in `/www`.
