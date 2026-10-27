# Install Total.js Developer

Total.js Developer is **Ubuntu Server 26.04 LTS with a development environment for Total.js** that is installed together with it. You start a machine with the **official ISO of Ubuntu Server**
and one **seed**: a small image (a few hundred kilobytes) that tells the installer of Ubuntu to install Total.js Developer, with the desktop or only the command line. The installer asks you the usual questions.

It is made to run in a **virtual machine**, which is the easiest way to have it, and it also installs on a real computer in the same way.

## What you need

- An **amd64** machine (Intel or AMD) or an **arm64** one (ARM), virtual or a computer. On a Mac with Apple Silicon, use the arm64 ISO of Ubuntu in UTM, Parallels or VMware Fusion, or the
  ready-made images of [TotalVM](https://totalvm.totaljs.es).
- 4 GB of memory (8 GB or more is better with the desktop), 2 processor cores or more, and 30 GB of disk.
- **An internet connection during the installation, in a virtual machine as well as on a computer.** The installer downloads Total.js Developer
  while it installs. A virtual machine gets it from its host with the usual network of the program (NAT or bridge); a computer needs a cable or Wi-Fi that the
  installer can use.

## 1. Download

1. **The official ISO of Ubuntu Server 26.04 LTS**, unmodified, from Ubuntu: <https://releases.ubuntu.com/26.04/> for amd64 (Intel and AMD) or <https://cdimage.ubuntu.com/ubuntu/releases/26.04/release/> for arm64 (ARM).
   Its checksum is on the same page (`SHA256SUMS`).
2. **One seed**, from the [releases](../../../releases) of this repository (the one called *seeds*), the same for both processors:

| Edition | File |
| --- | --- |
| Desktop (Openbox, Firefox and Chrome) | `totaljs-developer-desktop-seed.iso` |
| Server (command line only) | `totaljs-developer-server-seed.iso` |

Check what you downloaded:

```bash
sha256sum -c SHA256SUMS --ignore-missing
gh attestation verify totaljs-developer-desktop-seed.iso --repo totaljs-es/developer-distros   # the signed attestation of where the seed was built (GitHub CLI)
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
| First optical drive | the ISO of Ubuntu |
| Second optical drive (or a second removable drive) | the seed |

**UTM on a Mac with Apple Silicon:** when you create the machine (*Virtualize → Linux*), turn on **Use Apple Virtualization** in the advanced options. With it the boot shows the animation of
Total.js. With the default engine of UTM (QEMU) the system installs and works the same, but the screen of the virtual machine stays off until the login appears, and the animation is not seen.

With the engine QEMU, three more things (they come from QEMU, not from the system, and Apple Virtualization does not have them):
- **A restart can hang** when the machine has several processors; turning it off and on works, and with 1 processor the restart works too.
- The boot is seen (with its animation) by choosing the display card `virtio-ramfb` in the settings of the machine.
- The keys of the Mac that close a window are caught by the window: `Cmd + W` closes the machine. Use `Alt + W` to change the wallpaper.
The ISO of Intel (x86_64) in UTM can only run with QEMU, because Apple Virtualization does not emulate Intel.

With QEMU it is:

```bash
qemu-img create -f qcow2 totaljs.qcow2 30G
qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 -nic user,model=virtio-net-pci \
  -drive file=totaljs.qcow2,if=virtio \
  -drive file=ubuntu-26.04-live-server-amd64.iso,media=cdrom \
  -drive file=totaljs-developer-desktop-seed.iso,media=cdrom \
  -boot d
```

### On a computer

1. Write the ISO of Ubuntu to a USB stick, and the seed to another one, with [balenaEtcher](https://etcher.balena.io) or with `dd`.
2. Connect both and start the computer from the one of Ubuntu. Most computers show a boot menu with a key at power on (`F12`, `F10`, `Esc` or `F2`; on a Mac, hold `Option`).
   Choose the stick, in UEFI mode.

The computer has to be one on which Ubuntu Server 26.04 runs: if Ubuntu does not see your disk, your network card or your keyboard, Total.js Developer will not either.

## 3. Install

1. Start the machine from the ISO of Ubuntu and choose **Try or Install Ubuntu Server**.
2. The installer finds the seed and asks whether to continue with the autoinstall: type `yes`. It is the installer of Ubuntu Server, in text mode: simple, and the same one that millions of servers use. You move with the arrow keys, `Tab` and `Enter`.
3. Answer the questions: language, keyboard, network, disk and who you are (your name, the name of the machine, your user and your password).
   The guided disk layout with LVM leaves half of the disk free; the seed gives it to the system at the end. On a system that is already installed, you can do it yourself: `sudo lvextend -r -l +100%FREE /dev/mapper/ubuntu--vg-ubuntu--lv`.
4. Wait. The installer puts the system on the disk and then downloads and installs Total.js Developer. When it finishes it asks you to restart:
   disconnect the drives (take out the sticks, or eject the virtual drives) and press Enter. The desktop edition starts with the desktop of Total.js.

## After the first start

- **Server edition:** log in on the console or with SSH (`ssh your-user@address`). Open `https://totaljs.developer` from any computer that can
  reach this one (see *Use it from another computer* in [How to use it](using.md)).
- **Desktop edition:** the login screen appears. Log in and the desktop opens. The panel on the top has the menu (the mark of Total.js, first), the launcher of applications (the rocket), the terminal, the files and the
  browser. `Super + B` opens Total.js Center in Firefox.
- The first time the services start, they download their images (Code, Flow, PostgreSQL and pgAdmin). Give them a few minutes and a connection:
  Total.js Center shows when each one is ready.

## If something does not work

| What you see | What to do |
| --- | --- |
| It says that it cannot reach the repository | The installer needs internet from the start. Check the network of the virtual machine (NAT or bridge), or connect the cable or choose the Wi-Fi when the installer asks about the network, and start again. |
| It stops with an error | Press Enter to open a shell and read `/var/log/installer/`, or start again. |
| After restarting, the services do not answer | They download their images in the first minutes. Look at `systemctl status totaljs-proxy totaljs-code totaljs-flow totaljs-postgres`. |

## Remove the installation

Total.js Developer is a set of packages: `sudo apt remove totaljs-developer-desktop` (or `-server`) removes the layer and keeps your projects in `/www`.
