#!/usr/bin/env bash
# Arch Linux ARM disables CONFIG_SND_VIRTIO in linux-aarch64. Build the small
# upstream virtio-snd driver as DKMS so Apple Virtualization audio works now and
# is rebuilt automatically when Pacman installs a newer kernel.
set -euo pipefail

if modinfo virtio_snd >/dev/null 2>&1; then
    echo "[29-virtio-sound] kernel already provides virtio_snd"
    exit 0
fi

pac -S --noconfirm --needed dkms linux-aarch64-headers

KERNEL_RELEASE="$(uname -r)"
UPSTREAM_VERSION="${KERNEL_RELEASE%%-*}"
UPSTREAM_TAG="v${UPSTREAM_VERSION}"
if [[ "${UPSTREAM_VERSION}" == *.0 ]]; then
    UPSTREAM_TAG="v${UPSTREAM_VERSION%.0}"
fi
MODULE_NAME=virtio-snd-totaljs
SOURCE_DIR="/usr/src/${MODULE_NAME}-${UPSTREAM_VERSION}"
CLONE_DIR="$(mktemp -d /tmp/totaljs-virtio-snd.XXXXXX)"
trap 'rm -rf "${CLONE_DIR}"' EXIT

[ -d "/usr/lib/modules/${KERNEL_RELEASE}/build" ] || {
    echo "[29-virtio-sound] headers do not match running kernel ${KERNEL_RELEASE}" >&2
    exit 1
}

echo "[29-virtio-sound] fetching upstream Linux ${UPSTREAM_TAG} virtio driver"
git clone --quiet --depth 1 --filter=blob:none --sparse \
    --branch "${UPSTREAM_TAG}" \
    https://github.com/gregkh/linux.git "${CLONE_DIR}/linux"
git -C "${CLONE_DIR}/linux" sparse-checkout set sound/virtio

rm -rf "${SOURCE_DIR}"
install -d "${SOURCE_DIR}"
cp "${CLONE_DIR}"/linux/sound/virtio/virtio_*.[ch] "${SOURCE_DIR}/"

cat > "${SOURCE_DIR}/Makefile" <<'EOF'
KERNELRELEASE ?= $(shell uname -r)
obj-m += virtio_snd.o
virtio_snd-y := \
	virtio_card.o \
	virtio_chmap.o \
	virtio_ctl_msg.o \
	virtio_jack.o \
	virtio_kctl.o \
	virtio_pcm.o \
	virtio_pcm_msg.o \
	virtio_pcm_ops.o

all:
	$(MAKE) -C /usr/lib/modules/$(KERNELRELEASE)/build M=$(CURDIR) modules

clean:
	$(MAKE) -C /usr/lib/modules/$(KERNELRELEASE)/build M=$(CURDIR) clean
EOF

cat > "${SOURCE_DIR}/dkms.conf" <<EOF
PACKAGE_NAME="${MODULE_NAME}"
PACKAGE_VERSION="${UPSTREAM_VERSION}"
BUILT_MODULE_NAME[0]="virtio_snd"
DEST_MODULE_LOCATION[0]="/updates"
AUTOINSTALL="yes"
MAKE[0]="make KERNELRELEASE=\${kernelver}"
CLEAN="make clean"
EOF

dkms remove "${MODULE_NAME}/${UPSTREAM_VERSION}" --all >/dev/null 2>&1 || true
dkms add "${MODULE_NAME}/${UPSTREAM_VERSION}"
dkms build "${MODULE_NAME}/${UPSTREAM_VERSION}" -k "${KERNEL_RELEASE}"
dkms install "${MODULE_NAME}/${UPSTREAM_VERSION}" -k "${KERNEL_RELEASE}"
depmod -a "${KERNEL_RELEASE}"

modinfo virtio_snd >/dev/null
echo virtio_snd > /etc/modules-load.d/totaljs-audio.conf
modprobe virtio_snd
echo "[29-virtio-sound] virtio_snd ready for ${KERNEL_RELEASE}"
