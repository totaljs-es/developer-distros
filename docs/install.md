# Install Total.js Developer

Total.js Developer is **an Ubuntu remix**: Ubuntu Server 26.04 LTS with a development environment for Total.js that is installed together with it. You download **one ISO**, start a
machine with it, choose the desktop or the server edition, and the installer asks you the usual questions.

It is made to run in a **virtual machine**, which is the easiest way to have it, and it also installs on a real computer in the same way.

## What you need

- An **amd64** machine (Intel or AMD) or an **arm64** one (ARM), virtual or a computer. On a Mac with Apple Silicon, use the arm64 ISO in UTM, Parallels or VMware Fusion, or the
  ready-made images of [TotalVM](https://totalvm.totaljs.es).
- 4 GB of memory (8 GB or more is better with the desktop), 2 processor cores or more, and 30 GB of disk.
- **An internet connection during the installation, in a virtual machine as well as on a computer.** The installer downloads Total.js Developer
  while it installs. A virtual machine gets it from its host with the usual network of the program (NAT or bridge); a computer needs a cable or Wi-Fi that the
  installer can use.

## 1. Download

From the [releases](../../../releases) of this repository: the ISO for your processor, `totaljs-developer-amd64.iso` (Intel and AMD) or `totaljs-developer-arm64.iso` (ARM), and
`SHA256SUMS` to check it:

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

The ISO also carries a signed attestation of where it was built. If you use the GitHub CLI:

```bash
gh attestation verify totaljs-developer-amd64.iso --repo totaljs-es/developer-distros   # or the arm64 one
```

## 2. Prepare the machine

### In a virtual machine

Create a machine with these settings, in the program that you use (VirtualBox, VMware, Hyper-V, QEMU/KVM, Proxmox, Parallels...):

| Setting | Value |
| --- | --- |
| Type | Linux, Ubuntu 64-bit (arm64 on an ARM host) |
| Memory | 4 GB or more (8 GB with the desktop) |
| Processors | 2 or more |
| Disk | 30 GB or more |
| Firmware | UEFI (BIOS also works on amd64; arm64 always uses UEFI) |
| Network | NAT or bridge, with internet |
| Optical drive | the ISO |

With QEMU it is:

```bash
qemu-img create -f qcow2 totaljs.qcow2 30G
qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 -nic user,model=virtio-net-pci \
  -drive file=totaljs.qcow2,if=virtio \
  -drive file=totaljs-developer-amd64.iso,media=cdrom \
  -boot d
```

### On a computer

1. Write the ISO to a USB stick, with [balenaEtcher](https://etcher.balena.io) or with `dd`.
2. Connect it and start the computer from it. Most computers show a boot menu with a key at power on (`F12`, `F10`, `Esc` or `F2`; on a Mac, hold `Option`).
   Choose the stick, in UEFI mode.

The computer has to be one on which Ubuntu Server 26.04 runs: if Ubuntu does not see your disk, your network card or your keyboard, Total.js Developer will not either.

## 3. Install

1. Start the machine from the ISO. The menu has two entries: **Install Total.js Developer, desktop edition** (the first one) and **server edition** (command line only).
2. Choose one. The installer starts. It is the installer of Ubuntu Server, in text mode: simple, and the same one that millions of servers use. You move with the arrow keys, `Tab` and `Enter`. When it
   finishes and the system restarts, the desktop edition starts with the desktop of Total.js.
3. Answer the questions: language, keyboard, network, disk and who you are (your name, the name of the machine, your user and your password).
4. Wait. The installer puts the system on the disk and then downloads and installs Total.js Developer. When it finishes it asks you to restart:
   disconnect the ISO (take out the stick, or eject the virtual drive) and press Enter.

## After the first start

- **Server edition:** log in on the console or with SSH (`ssh your-user@address`). Open `http://totaljs.developer` from any computer that can
  reach this one (see *Use it from another computer* in [How to use it](using.md)).
- **Desktop edition:** the login screen appears. Log in and the desktop opens. Total.js Center is the first button of the panel, and `Super + B`
  opens it in Firefox.
- The first time the services start, they download their images (Code, Flow, PostgreSQL and pgAdmin). Give them a few minutes and a connection:
  Total.js Center shows when each one is ready.

## If something does not work

| What you see | What to do |
| --- | --- |
| It says that it cannot reach the repository | The installer needs internet from the start. Check the network of the virtual machine (NAT or bridge), or connect the cable or choose the Wi-Fi when the installer asks about the network, and start again. |
| It stops with an error | Press Enter to open a shell and read `/var/log/installer/`, or start again. |
| After restarting, the services do not answer | They download their images in the first minutes. Look at `systemctl status totaljs-proxy totaljs-code totaljs-flow totaljs-postgres`. |

## Another way: the official ISO of Ubuntu and a seed

If you prefer to start from the official ISO of Ubuntu Server 26.04 LTS, unmodified (<https://releases.ubuntu.com/26.04/> for amd64, <https://cdimage.ubuntu.com/ubuntu/releases/26.04/release/> for arm64), add a **seed** next to it: a small image with the
volume label `CIDATA` that tells the installer of Ubuntu to install Total.js Developer. It is in the same release as the ISO:

| Edition | File |
| --- | --- |
| Desktop | `totaljs-developer-desktop-seed.iso` |
| Server | `totaljs-developer-server-seed.iso` |

Connect the ISO of Ubuntu as the first optical drive and the seed as a second one (on a computer, two USB sticks), start from the ISO of Ubuntu, choose **Try or Install Ubuntu Server** and
when the installer asks whether to continue with the autoinstall, type `yes`. The rest is the same.

## Remove the installation

Total.js Developer is a set of packages: `sudo apt remove totaljs-developer-desktop` (or `-server`) removes the layer and keeps your projects in `/www`.
