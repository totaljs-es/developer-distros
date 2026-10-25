#!/bin/bash
# chroot-setup.sh - runs inside the system of the image (see build.sh): the packages of Ubuntu that make it boot as a live system, and our identity.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive HOME=/root LC_ALL=C

cat > /etc/apt/sources.list.d/ubuntu.sources <<EOF
Types: deb
URIs: ${MIRROR}
Suites: ${SUITE} ${SUITE}-updates
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
rm -f /etc/apt/sources.list

apt-get update -qq
# the kernel, what starts a system from a CD (live-boot) and the base of a system that boots and has a network
apt-get install -y --no-install-recommends linux-image-generic initramfs-tools live-boot systemd-sysv udev dbus iproute2 systemd-resolved kmod >/dev/null

# the identity: the system is Total.js Developer. It is based on Ubuntu and says so (ID_LIKE), and has no mark of Ubuntu as its name.
cat > /etc/os-release <<'EOF'
PRETTY_NAME="Total.js Developer"
NAME="Total.js Developer"
VERSION_ID="0.1"
VERSION="0.1"
ID=totaljs-developer
ID_LIKE="ubuntu debian"
HOME_URL="https://www.totaljs.com"
EOF
echo 'Total.js Developer \n \l' > /etc/issue
echo 'Total.js Developer' > /etc/issue.net
echo totaljs > /etc/hostname

# the network, with DHCP on every wired interface
cat > /etc/systemd/network/20-wired.network <<'EOF'
[Match]
Name=en* eth*
[Network]
DHCP=yes
EOF
systemctl enable systemd-networkd systemd-resolved totaljs-live-test.service >/dev/null 2>&1 || true

# a free root account with no password for the live session
passwd -d root >/dev/null

update-initramfs -u >/dev/null
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
: > /etc/machine-id
