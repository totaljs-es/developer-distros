#!/bin/sh
# install-layer.sh - installs the Total.js layer into the system that the Ubuntu installer has just put in place.
#
#   sh /cdrom/nocloud/install-layer.sh <target> <repository-address> [package]
#
# It runs in the installer, from the late-commands of the autoinstall seed: <target> is the new system (/target). The ISO
# is small on purpose, so the packages are downloaded now and this needs a network connection.
set -eu

TARGET="${1:?usage: install-layer.sh <target> <repository-address> [package]}"
REPO="${2:?usage: install-layer.sh <target> <repository-address> [package]}"
PACKAGE="${3:-totaljs-developer-server}"
# "auto": the edition that the person chose in the boot menu, which the installer kept in its command line (the server one without it)
if [ "${PACKAGE}" = auto ]; then
    case " $(cat /proc/cmdline) " in
        *' totaljs.edition=desktop '*) PACKAGE=totaljs-developer-desktop ;;
        *) PACKAGE=totaljs-developer-server ;;
    esac
fi
KEY=/tmp/totaljs-developer.gpg

# The guided layout of the Ubuntu installer with LVM gives the system only half of the disk and leaves the rest free. Docker, the images
# and the projects need that space, so the root volume takes it all (online, nothing is lost; if it is not LVM or there is no space left, nothing happens).
ROOT_SOURCE="$(findmnt -no SOURCE "${TARGET}" 2>/dev/null || true)"
case "${ROOT_SOURCE}" in
    /dev/mapper/*|/dev/*/*)
        if command -v lvextend >/dev/null 2>&1 && lvextend -r -l +100%FREE "${ROOT_SOURCE}" >/dev/null 2>&1; then
            echo "Total.js: the root volume now uses the whole disk"
        fi
        ;;
esac

fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fsS --retry 5 --retry-delay 3 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then wget -q -t 5 -O "$2" "$1"
    else python3 -c 'import sys, urllib.request; urllib.request.urlretrieve(sys.argv[1], sys.argv[2])' "$1" "$2"
    fi
}

echo "Total.js: downloading from ${REPO}"
if ! fetch "${REPO}/totaljs-developer.gpg" "${KEY}"; then
    echo "Total.js: cannot reach ${REPO}." >&2
    echo "Total.js: this installer downloads the Total.js layer, so it needs a network connection (cable or Wi-Fi). Connect and install again." >&2
    exit 1
fi

# The key and the source, as the package totaljs-developer-release writes them later
install -D -m 0644 "${KEY}" "${TARGET}/usr/share/keyrings/totaljs-developer-archive-keyring.gpg"
CODENAME="$(. "${TARGET}/etc/os-release" && echo "${VERSION_CODENAME}")"
mkdir -p "${TARGET}/etc/apt/sources.list.d"
cat > "${TARGET}/etc/apt/sources.list.d/totaljs-developer.sources" <<EOF
Types: deb
URIs: ${REPO}/ubuntu
Suites: ${CODENAME}
Components: main
Signed-By: /usr/share/keyrings/totaljs-developer-archive-keyring.gpg
EOF

# In two steps: Docker Engine comes from the repository of Docker, so its source (a package of ours) has to be there, and the lists
# updated, before apt resolves the layer
curtin in-target --target="${TARGET}" -- apt-get update
SOURCES="totaljs-developer-release totaljs-docker-source"
# the desktop edition also takes Firefox from the repository of Mozilla (Ubuntu offers it only as a snap), and Chrome from the one of Google
case "${PACKAGE}" in totaljs-developer-desktop) SOURCES="${SOURCES} totaljs-mozilla-source totaljs-chrome-source" ;; esac
curtin in-target --target="${TARGET}" -- env DEBIAN_FRONTEND=noninteractive apt-get install -y ${SOURCES}
curtin in-target --target="${TARGET}" -- apt-get update
curtin in-target --target="${TARGET}" -- env DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGE}"

echo "Total.js: ${PACKAGE} installed"
