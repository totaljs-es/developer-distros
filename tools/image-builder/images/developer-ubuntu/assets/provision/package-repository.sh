#!/usr/bin/env bash
set -euo pipefail

ROOT="${TOTALVM_ASSETS:-/mnt/assets}"
ASSETS="${ROOT}/repository"
KEY="${ROOT}/totaljs-repository.gpg"
FINGERPRINT=95454694523B8D18A376F7D5D722BA35C8427B40
PROFILE="${TOTALVM_REPOSITORY_PROFILE:-desktop}"

missing() {
    echo "Total.js repository bootstrap assets are missing under ${ROOT}:" >&2
    find "${ROOT}" -maxdepth 2 -type f -print >&2 || true
    exit 1
}

install_apt_source() {
    install -d /usr/share/keyrings /etc/apt/sources.list.d
    install -m 0644 "${KEY}" /usr/share/keyrings/totaljs-developer-archive-keyring.gpg
    cat > /etc/apt/sources.list.d/totaljs-developer.sources <<'EOF'
Types: deb
URIs: https://totalvm.totaljs.es/repo/ubuntu
Suites: noble
Components: main
Architectures: arm64
Signed-By: /usr/share/keyrings/totaljs-developer-archive-keyring.gpg
EOF
}

install_pacman_source() {
    install -d /usr/share/totaljs-developer
    install -m 0644 "${KEY}" /usr/share/totaljs-developer/repository-key.gpg
    pacman-key --add /usr/share/totaljs-developer/repository-key.gpg
    pacman-key --lsign-key "${FINGERPRINT}"
    cat > /etc/pacman.d/totaljs-developer.conf <<'EOF'
[totaljs-developer]
SigLevel = Required DatabaseRequired
Server = https://totalvm.totaljs.es/repo/arch/$arch
EOF
    grep -qF 'Include = /etc/pacman.d/totaljs-developer.conf' /etc/pacman.conf \
        || printf '\nInclude = /etc/pacman.d/totaljs-developer.conf\n' >> /etc/pacman.conf
}

latest_asset() {
    [ -d "${ASSETS}" ] || return 0
    find "${ASSETS}" -maxdepth 1 -type f -name "$1" -print 2>/dev/null \
        | LC_ALL=C sort -V \
        | tail -n 1 \
        || true
}

pacman_install_local() {
    pacman -U --noconfirm \
        --overwrite usr/local/sbin/totalvm-rosetta-setup \
        --overwrite etc/systemd/system/totalvm-rosetta.service \
        "$@"
}

if command -v dpkg >/dev/null 2>&1; then
    package="${ROOT}/totaljs-release.deb"
    desktop_package="$(latest_asset 'totaljs-desktop_*_all.deb')"
    if [ ! -f "${package}" ]; then
        package="$(latest_asset 'totaljs-developer-release_*_all.deb')"
    fi
    if [ "${PROFILE}" = "server" ] && [ -f "${KEY}" ]; then
        install_apt_source
    elif [ -n "${package}" ] && [ -f "${package}" ]; then
        if [ -n "${desktop_package}" ] && [ -f "${desktop_package}" ]; then
            # apt-get resolves dependencies from Ubuntu while installing both
            # local packages in the same transaction. dpkg -i alone leaves a
            # fresh image unconfigured when desktop dependencies are absent.
            apt-get install -y --no-install-recommends "${desktop_package}" "${package}"
        else
            apt-get install -y --no-install-recommends "${package}"
        fi
    elif [ -f "${KEY}" ]; then
        install_apt_source
    else
        missing
    fi
elif command -v pacman >/dev/null 2>&1; then
    package="${ROOT}/totaljs-release.pkg.tar.zst"
    desktop_package="$(latest_asset 'totaljs-desktop-*-any.pkg.tar.zst')"
    if [ ! -f "${package}" ]; then
        package="$(latest_asset 'totaljs-developer-release-*-any.pkg.tar.zst')"
    fi
    if [ "${PROFILE}" = "server" ] && [ -f "${KEY}" ]; then
        install_pacman_source
    elif [ -n "${package}" ] && [ -f "${package}" ]; then
        if [ -n "${desktop_package}" ] && [ -f "${desktop_package}" ]; then
            pacman_install_local "${desktop_package}" "${package}"
        else
            pacman_install_local "${package}"
        fi
    elif [ -f "${KEY}" ]; then
        install_pacman_source
    else
        missing
    fi

    # Installing the bootstrap package adds the Total.js repository to
    # pacman.conf, but pacman has not downloaded that repository's database
    # yet. Sync it here so the next provisioning step does not fail once before
    # the global retry wrapper refreshes the databases.
    if declare -F pac >/dev/null 2>&1; then
        pac -Sy --noconfirm
    else
        pacman -Sy --noconfirm --disable-download-timeout
    fi
else
    echo "Unsupported package manager" >&2
    exit 1
fi

echo "[27-package-repository] Total.js Developer package source installed"
