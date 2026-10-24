#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GNUPGHOME="${TOTALJS_REPO_GNUPGHOME:-${HOME}/.config/totaljs/repository-signing}"
KEY_FPR="${TOTALJS_REPO_KEY:-95454694523B8D18A376F7D5D722BA35C8427B40}"
VERSION="${VERSION:-1.0.9}"
RELEASE=1
PACKAGE=totaljs-developer-release
DESKTOP_VERSION="${DESKTOP_VERSION:-1.0.5}"
DESKTOP_RELEASE=1
DESKTOP_PACKAGE=totaljs-desktop
# Where the repository will be served from. It is written into the packages, so it is the address that every installed
# system will update from: set it to the final address before a release (the default is the one of GitHub Pages).
BASE_URL="${BASE_URL:-https://totaljs-es.github.io/developer-distros/repo}"
# Where the repository is written: a folder of this repository (build/ is not committed). WEBSITE_ROOT keeps the old way
# of writing into the public folder of a website.
if [ -n "${WEBSITE_ROOT:-}" ]; then OUT="${WEBSITE_ROOT}/public/repo"; else OUT="${REPO_OUT:-${ROOT}/build/site/repo}"; fi
# The Ubuntu series and the architectures of the repository. Packages are Architecture: all, so the same files serve every one
SUITES="${SUITES:-noble resolute}"
DEB_ARCHES="${DEB_ARCHES:-arm64 amd64}"
ARCH_DIRS="${ARCH_DIRS:-aarch64 x86_64}"
ASSETS="${ROOT}/tools/image-builder/images/developer-ubuntu/assets/repository"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

for command in ar bsdtar gzip shasum zstd gpg; do
  command -v "${command}" >/dev/null || { echo "Missing command: ${command}" >&2; exit 1; }
done
[ -d "${GNUPGHOME}" ] || { echo "Signing key home not found: ${GNUPGHOME}" >&2; exit 1; }

export GNUPGHOME

# macOS (BSD) and Linux (GNU) differ in these
filesize() { if stat -c%s "$1" 2>/dev/null; then :; else stat -f%z "$1"; fi; }
# bsdtar only knows --no-mac-metadata on some builds
TAR_OPTS="--no-xattrs"
if bsdtar --help 2>&1 | grep -q -- '--no-mac-metadata'; then TAR_OPTS="${TAR_OPTS} --no-mac-metadata"; fi
# Never serialize Finder/provenance xattrs into Linux packages. dpkg rejects
# libarchive's PAX xattr records even though bsdtar can read them on macOS.
export COPYFILE_DISABLE=1
ARCH_PRIMARY="${ARCH_DIRS%% *}"
mkdir -p "${OUT}/ubuntu/pool/main/t/${PACKAGE}" \
  "${OUT}/ubuntu/pool/main/t/${DESKTOP_PACKAGE}" \
  "${OUT}/arch/${ARCH_PRIMARY}" "${ASSETS}"
gpg --batch --yes --export "${KEY_FPR}" > "${OUT}/totaljs-developer.gpg"
gpg --batch --yes --armor --export "${KEY_FPR}" > "${OUT}/totaljs-developer.asc"

echo "[repo] building Debian bootstrap package"
DEBROOT="${WORK}/deb-root"
mkdir -p "${DEBROOT}/usr/share/keyrings" "${DEBROOT}/usr/share/totaljs-developer" "${DEBROOT}/etc/apt/sources.list.d" \
  "${DEBROOT}/usr/local/sbin" "${DEBROOT}/etc/systemd/system"
cp "${OUT}/totaljs-developer.gpg" "${DEBROOT}/usr/share/keyrings/totaljs-developer-archive-keyring.gpg"
printf '%s\n' "${VERSION}" > "${DEBROOT}/usr/share/totaljs-developer/release"
# The series (noble, resolute...) is the one of the system: the postinst writes the source from this template
cat > "${DEBROOT}/usr/share/totaljs-developer/totaljs-developer.sources.in" <<EOF
Types: deb
URIs: ${BASE_URL}/ubuntu
Suites: @SUITE@
Components: main
Signed-By: /usr/share/keyrings/totaljs-developer-archive-keyring.gpg
EOF
cat > "${DEBROOT}/usr/local/sbin/totalvm-rosetta-setup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mountpoint -q /proc/sys/fs/binfmt_misc \
    || mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null \
    || true

install -d /media/rosetta /run/rosettad
mountpoint -q /media/rosetta \
    || mount -t virtiofs -o ro,nofail rosetta /media/rosetta 2>/dev/null \
    || exit 0

[ -x /media/rosetta/rosetta ] || exit 0
[ -w /proc/sys/fs/binfmt_misc/register ] || exit 0

register_rosetta() {
    name="$1"
    magic="$2"
    mask="$3"

    if [ -e "/proc/sys/fs/binfmt_misc/${name}" ]; then
        echo -1 > "/proc/sys/fs/binfmt_misc/${name}" 2>/dev/null || true
    fi

    printf '%s\n' ":${name}:M::${magic}:${mask}:/media/rosetta/rosetta:PCF" \
        > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
}

elf_prefix='\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'
elf_mask='\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff'
register_rosetta rosetta-x86_64 "${elf_prefix}"'\x02\x00\x3e\x00' "${elf_mask}"
register_rosetta rosetta-x86_64-pie "${elf_prefix}"'\x03\x00\x3e\x00' "${elf_mask}"
EOF
chmod 0755 "${DEBROOT}/usr/local/sbin/totalvm-rosetta-setup"
cat > "${DEBROOT}/etc/systemd/system/totalvm-rosetta.service" <<'EOF'
[Unit]
Description=Apple Rosetta support for Intel Linux binaries
After=local-fs.target
ConditionVirtualization=!container

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/totalvm-rosetta-setup
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

DEBBUILD="${WORK}/deb-build"
mkdir -p "${DEBBUILD}"
cat > "${DEBBUILD}/control" <<EOF
Package: ${PACKAGE}
Version: ${VERSION}-${RELEASE}
Architecture: all
Maintainer: Total.js <repository@totaljs.com>
Section: utils
Priority: optional
Installed-Size: 20
Homepage: https://totalvm.totaljs.es
Description: Official Total.js Developer repository configuration
 Installs the signing key and package source used to update the Total.js
 Developer layer independently from the base Linux distribution.
EOF
cat > "${DEBBUILD}/postinst" <<'EOF'
#!/bin/sh
set -e
codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
if [ -n "${codename}" ]; then
  sed "s/@SUITE@/${codename}/" /usr/share/totaljs-developer/totaljs-developer.sources.in \
    > /etc/apt/sources.list.d/totaljs-developer.sources
fi
systemctl daemon-reload >/dev/null 2>&1 || true
systemctl enable totalvm-rosetta.service >/dev/null 2>&1 || true
/usr/local/sbin/totalvm-rosetta-setup >/dev/null 2>&1 || true
exit 0
EOF
chmod 0755 "${DEBBUILD}/postinst"
cat > "${DEBBUILD}/postrm" <<'EOF'
#!/bin/sh
set -e
case "$1" in
  remove|purge) rm -f /etc/apt/sources.list.d/totaljs-developer.sources ;;
esac
exit 0
EOF
chmod 0755 "${DEBBUILD}/postrm"
printf '2.0\n' > "${DEBBUILD}/debian-binary"
(cd "${DEBBUILD}" && bsdtar ${TAR_OPTS} --uid 0 --gid 0 --uname root --gname root -czf control.tar.gz control postinst postrm)
(cd "${DEBROOT}" && bsdtar ${TAR_OPTS} --uid 0 --gid 0 --uname root --gname root -czf "${DEBBUILD}/data.tar.gz" .)
DEBFILE="${PACKAGE}_${VERSION}-${RELEASE}_all.deb"
(cd "${DEBBUILD}" && bsdtar ${TAR_OPTS} --format=ar -cf "${OUT}/ubuntu/pool/main/t/${PACKAGE}/${DEBFILE}" debian-binary control.tar.gz data.tar.gz)
cp "${OUT}/ubuntu/pool/main/t/${PACKAGE}/${DEBFILE}" "${ASSETS}/${DEBFILE}"
cp "${OUT}/ubuntu/pool/main/t/${PACKAGE}/${DEBFILE}" "${ROOT}/tools/image-builder/images/developer-ubuntu/assets/totaljs-release.deb"
cp "${OUT}/totaljs-developer.gpg" "${ROOT}/tools/image-builder/images/developer-ubuntu/assets/totaljs-repository.gpg"

echo "[repo] building Debian desktop package"
DESKTOP_DEBROOT="${WORK}/desktop-deb-root"
mkdir -p "${DESKTOP_DEBROOT}/usr/lib/totaljs-developer" \
  "${DESKTOP_DEBROOT}/usr/share/totaljs-developer/icons" \
  "${DESKTOP_DEBROOT}/usr/local/bin"
install -m 0755 "${ROOT}/tools/package-repo/apply-menu-icons" \
  "${DESKTOP_DEBROOT}/usr/lib/totaljs-developer/apply-menu-icons"
install -m 0755 "${ROOT}/tools/image-builder/images/developer-ubuntu/assets/desktop/totaljs-pasystray" \
  "${DESKTOP_DEBROOT}/usr/local/bin/totaljs-pasystray"
install -m 0644 "${ROOT}"/tools/package-repo/icons/*.svg \
  "${DESKTOP_DEBROOT}/usr/share/totaljs-developer/icons/"

DESKTOP_DEBBUILD="${WORK}/desktop-deb-build"
mkdir -p "${DESKTOP_DEBBUILD}"
cat > "${DESKTOP_DEBBUILD}/control" <<EOF
Package: ${DESKTOP_PACKAGE}
Version: ${DESKTOP_VERSION}-${DESKTOP_RELEASE}
Architecture: all
Maintainer: Total.js <repository@totaljs.com>
Section: utils
Priority: optional
Depends: openbox
Installed-Size: 12
Homepage: https://totalvm.totaljs.es
Description: Total.js Developer desktop integration
 Applies compatible visual and desktop integration updates without replacing
 user projects or unrelated personal configuration.
EOF
cat > "${DESKTOP_DEBBUILD}/postinst" <<'EOF'
#!/bin/sh
set -e
/usr/lib/totaljs-developer/apply-menu-icons
exit 0
EOF
chmod 0755 "${DESKTOP_DEBBUILD}/postinst"
printf '2.0\n' > "${DESKTOP_DEBBUILD}/debian-binary"
(cd "${DESKTOP_DEBBUILD}" && bsdtar ${TAR_OPTS} --uid 0 --gid 0 --uname root --gname root -czf control.tar.gz control postinst)
(cd "${DESKTOP_DEBROOT}" && bsdtar ${TAR_OPTS} --uid 0 --gid 0 --uname root --gname root -czf "${DESKTOP_DEBBUILD}/data.tar.gz" .)
DESKTOP_DEBFILE="${DESKTOP_PACKAGE}_${DESKTOP_VERSION}-${DESKTOP_RELEASE}_all.deb"
(cd "${DESKTOP_DEBBUILD}" && bsdtar ${TAR_OPTS} --format=ar -cf "${OUT}/ubuntu/pool/main/t/${DESKTOP_PACKAGE}/${DESKTOP_DEBFILE}" debian-binary control.tar.gz data.tar.gz)
cp "${OUT}/ubuntu/pool/main/t/${DESKTOP_PACKAGE}/${DESKTOP_DEBFILE}" "${ASSETS}/${DESKTOP_DEBFILE}"

DESKTOP_DEBSIZE="$(filesize "${OUT}/ubuntu/pool/main/t/${DESKTOP_PACKAGE}/${DESKTOP_DEBFILE}")"
DESKTOP_DEBSHA="$(shasum -a 256 "${OUT}/ubuntu/pool/main/t/${DESKTOP_PACKAGE}/${DESKTOP_DEBFILE}" | awk '{print $1}')"

DEBSIZE="$(filesize "${OUT}/ubuntu/pool/main/t/${PACKAGE}/${DEBFILE}")"
DEBSHA="$(shasum -a 256 "${OUT}/ubuntu/pool/main/t/${PACKAGE}/${DEBFILE}" | awk '{print $1}')"
cat > "${WORK}/Packages.stanzas" <<EOF
Package: ${PACKAGE}
Version: ${VERSION}-${RELEASE}
Architecture: all
Maintainer: Total.js <repository@totaljs.com>
Installed-Size: 20
Filename: pool/main/t/${PACKAGE}/${DEBFILE}
Size: ${DEBSIZE}
SHA256: ${DEBSHA}
Section: utils
Priority: optional
Homepage: https://totalvm.totaljs.es
Description: Official Total.js Developer repository configuration
 Installs the signing key and package source used to update the Total.js Developer layer.

Package: ${DESKTOP_PACKAGE}
Version: ${DESKTOP_VERSION}-${DESKTOP_RELEASE}
Architecture: all
Maintainer: Total.js <repository@totaljs.com>
Installed-Size: 12
Filename: pool/main/t/${DESKTOP_PACKAGE}/${DESKTOP_DEBFILE}
Size: ${DESKTOP_DEBSIZE}
SHA256: ${DESKTOP_DEBSHA}
Section: utils
Priority: optional
Depends: openbox
Homepage: https://totalvm.totaljs.es
Description: Total.js Developer desktop integration
 Applies compatible visual and desktop integration updates without replacing user projects.

EOF

# One index for every series and architecture: the packages are Architecture: all, so the files are the same
for SUITE in ${SUITES}; do
  RELEASE_DIR="${OUT}/ubuntu/dists/${SUITE}"
  for DEB_ARCH in ${DEB_ARCHES}; do
    mkdir -p "${RELEASE_DIR}/main/binary-${DEB_ARCH}"
    cp "${WORK}/Packages.stanzas" "${RELEASE_DIR}/main/binary-${DEB_ARCH}/Packages"
    gzip -9nc "${RELEASE_DIR}/main/binary-${DEB_ARCH}/Packages" > "${RELEASE_DIR}/main/binary-${DEB_ARCH}/Packages.gz"
  done

  (cd "${RELEASE_DIR}" && {
    {
      printf 'Origin: Total.js\nLabel: Total.js Developer\nSuite: %s\nCodename: %s\n' "${SUITE}" "${SUITE}"
      printf 'Date: %s\n' "$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S UTC')"
      printf 'Architectures: %s\nComponents: main\nDescription: Official Total.js Developer packages\nSHA256:\n' "${DEB_ARCHES}"
      for DEB_ARCH in ${DEB_ARCHES}; do
        for FILE in Packages Packages.gz; do
          printf ' %s %s main/binary-%s/%s\n' "$(shasum -a 256 "main/binary-${DEB_ARCH}/${FILE}" | awk '{print $1}')" "$(filesize "main/binary-${DEB_ARCH}/${FILE}")" "${DEB_ARCH}" "${FILE}"
        done
      done
    } > Release
    gpg --batch --yes --local-user "${KEY_FPR}" --armor --detach-sign --output Release.gpg Release
    gpg --batch --yes --local-user "${KEY_FPR}" --clearsign --output InRelease Release
  })
done

echo "[repo] building Pacman desktop package"
DESKTOP_ARCHROOT="${WORK}/desktop-arch-root"
mkdir -p "${DESKTOP_ARCHROOT}/usr/lib/totaljs-developer" \
  "${DESKTOP_ARCHROOT}/usr/share/totaljs-developer/icons" \
  "${DESKTOP_ARCHROOT}/usr/local/bin"
install -m 0755 "${ROOT}/tools/package-repo/apply-menu-icons" \
  "${DESKTOP_ARCHROOT}/usr/lib/totaljs-developer/apply-menu-icons"
install -m 0755 "${ROOT}/tools/image-builder/images/developer-ubuntu/assets/desktop/totaljs-pasystray" \
  "${DESKTOP_ARCHROOT}/usr/local/bin/totaljs-pasystray"
install -m 0644 "${ROOT}"/tools/package-repo/icons/*.svg \
  "${DESKTOP_ARCHROOT}/usr/share/totaljs-developer/icons/"
cat > "${DESKTOP_ARCHROOT}/.INSTALL" <<'EOF'
post_install() {
  /usr/lib/totaljs-developer/apply-menu-icons
}
post_upgrade() { post_install; }
EOF
DESKTOP_ARCHSIZE="$(du -sk "${DESKTOP_ARCHROOT}" | awk '{print $1 * 1024}')"
cat > "${DESKTOP_ARCHROOT}/.PKGINFO" <<EOF
pkgname = ${DESKTOP_PACKAGE}
pkgbase = ${DESKTOP_PACKAGE}
pkgver = ${DESKTOP_VERSION}-${DESKTOP_RELEASE}
pkgdesc = Total.js Developer desktop integration
url = https://totalvm.totaljs.es
builddate = $(date +%s)
packager = Total.js <repository@totaljs.com>
size = ${DESKTOP_ARCHSIZE}
arch = any
license = custom
depend = openbox
EOF
DESKTOP_ARCHFILE="${DESKTOP_PACKAGE}-${DESKTOP_VERSION}-${DESKTOP_RELEASE}-any.pkg.tar.zst"
bsdtar ${TAR_OPTS} --uid 0 --gid 0 --uname root --gname root \
  -C "${DESKTOP_ARCHROOT}" -cf - .PKGINFO .INSTALL usr \
  | zstd -19 -q -f -o "${OUT}/arch/${ARCH_PRIMARY}/${DESKTOP_ARCHFILE}"
gpg --batch --yes --local-user "${KEY_FPR}" --detach-sign --output "${OUT}/arch/${ARCH_PRIMARY}/${DESKTOP_ARCHFILE}.sig" "${OUT}/arch/${ARCH_PRIMARY}/${DESKTOP_ARCHFILE}"
cp "${OUT}/arch/${ARCH_PRIMARY}/${DESKTOP_ARCHFILE}" "${ASSETS}/${DESKTOP_ARCHFILE}"

echo "[repo] building Pacman bootstrap package"
ARCHROOT="${WORK}/arch-root"
mkdir -p "${ARCHROOT}/usr/share/totaljs-developer" "${ARCHROOT}/etc/pacman.d" \
  "${ARCHROOT}/usr/local/sbin" "${ARCHROOT}/etc/systemd/system"
cp "${OUT}/totaljs-developer.gpg" "${ARCHROOT}/usr/share/totaljs-developer/repository-key.gpg"
printf '%s\n' "${VERSION}" > "${ARCHROOT}/usr/share/totaljs-developer/release"
cat > "${ARCHROOT}/etc/pacman.d/totaljs-developer.conf" <<EOF
[totaljs-developer]
SigLevel = Required DatabaseRequired
Server = ${BASE_URL}/arch/\$arch
EOF
cat > "${ARCHROOT}/usr/local/sbin/totalvm-rosetta-setup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mountpoint -q /proc/sys/fs/binfmt_misc \
    || mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null \
    || true

install -d /media/rosetta /run/rosettad
mountpoint -q /media/rosetta \
    || mount -t virtiofs -o ro,nofail rosetta /media/rosetta 2>/dev/null \
    || exit 0

[ -x /media/rosetta/rosetta ] || exit 0
[ -w /proc/sys/fs/binfmt_misc/register ] || exit 0

register_rosetta() {
    name="$1"
    magic="$2"
    mask="$3"

    if [ -e "/proc/sys/fs/binfmt_misc/${name}" ]; then
        echo -1 > "/proc/sys/fs/binfmt_misc/${name}" 2>/dev/null || true
    fi

    printf '%s\n' ":${name}:M::${magic}:${mask}:/media/rosetta/rosetta:PCF" \
        > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
}

elf_prefix='\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'
elf_mask='\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff'
register_rosetta rosetta-x86_64 "${elf_prefix}"'\x02\x00\x3e\x00' "${elf_mask}"
register_rosetta rosetta-x86_64-pie "${elf_prefix}"'\x03\x00\x3e\x00' "${elf_mask}"
EOF
chmod 0755 "${ARCHROOT}/usr/local/sbin/totalvm-rosetta-setup"
cat > "${ARCHROOT}/etc/systemd/system/totalvm-rosetta.service" <<'EOF'
[Unit]
Description=Apple Rosetta support for Intel Linux binaries
After=local-fs.target
ConditionVirtualization=!container

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/totalvm-rosetta-setup
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
cat > "${ARCHROOT}/.INSTALL" <<EOF
post_install() {
  pacman-key --add /usr/share/totaljs-developer/repository-key.gpg
  pacman-key --lsign-key ${KEY_FPR}
  grep -qF 'Include = /etc/pacman.d/totaljs-developer.conf' /etc/pacman.conf || printf '\nInclude = /etc/pacman.d/totaljs-developer.conf\n' >> /etc/pacman.conf
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable totalvm-rosetta.service >/dev/null 2>&1 || true
  /usr/local/sbin/totalvm-rosetta-setup >/dev/null 2>&1 || true
}
post_upgrade() { post_install; }
EOF
ARCHSIZE="$(du -sk "${ARCHROOT}" | awk '{print $1 * 1024}')"
cat > "${ARCHROOT}/.PKGINFO" <<EOF
pkgname = ${PACKAGE}
pkgbase = ${PACKAGE}
pkgver = ${VERSION}-${RELEASE}
pkgdesc = Official Total.js Developer repository configuration
url = https://totalvm.totaljs.es
builddate = $(date +%s)
packager = Total.js <repository@totaljs.com>
size = ${ARCHSIZE}
arch = any
license = custom
EOF
ARCHFILE="${PACKAGE}-${VERSION}-${RELEASE}-any.pkg.tar.zst"
# Pacman 7 requires package metadata at the exact archive path `.PKGINFO`;
# archiving `.` with BSD tar prefixes it as `./.PKGINFO` and Pacman reports an
# otherwise valid package as "missing package metadata".
bsdtar ${TAR_OPTS} --uid 0 --gid 0 --uname root --gname root \
  -C "${ARCHROOT}" -cf - .PKGINFO .INSTALL etc usr \
  | zstd -19 -q -f -o "${OUT}/arch/${ARCH_PRIMARY}/${ARCHFILE}"
gpg --batch --yes --local-user "${KEY_FPR}" --detach-sign --output "${OUT}/arch/${ARCH_PRIMARY}/${ARCHFILE}.sig" "${OUT}/arch/${ARCH_PRIMARY}/${ARCHFILE}"
cp "${OUT}/arch/${ARCH_PRIMARY}/${ARCHFILE}" "${ASSETS}/${ARCHFILE}"
cp "${OUT}/arch/${ARCH_PRIMARY}/${ARCHFILE}" "${ROOT}/tools/image-builder/images/developer-ubuntu/assets/totaljs-release.pkg.tar.zst"

ARCHCSIZE="$(filesize "${OUT}/arch/${ARCH_PRIMARY}/${ARCHFILE}")"
ARCHSHA="$(shasum -a 256 "${OUT}/arch/${ARCH_PRIMARY}/${ARCHFILE}" | awk '{print $1}')"
DBROOT="${WORK}/db/${PACKAGE}-${VERSION}-${RELEASE}"
DESKTOP_DBROOT="${WORK}/db/${DESKTOP_PACKAGE}-${DESKTOP_VERSION}-${DESKTOP_RELEASE}"
mkdir -p "${DBROOT}" "${DESKTOP_DBROOT}"
cat > "${DBROOT}/desc" <<EOF
%FILENAME%
${ARCHFILE}

%NAME%
${PACKAGE}

%BASE%
${PACKAGE}

%VERSION%
${VERSION}-${RELEASE}

%DESC%
Official Total.js Developer repository configuration

%CSIZE%
${ARCHCSIZE}

%ISIZE%
${ARCHSIZE}

%SHA256SUM%
${ARCHSHA}

%URL%
https://totalvm.totaljs.es

%ARCH%
any

%BUILDDATE%
$(date +%s)

%PACKAGER%
Total.js <repository@totaljs.com>

%LICENSE%
custom

EOF
DESKTOP_ARCHCSIZE="$(filesize "${OUT}/arch/${ARCH_PRIMARY}/${DESKTOP_ARCHFILE}")"
DESKTOP_ARCHSHA="$(shasum -a 256 "${OUT}/arch/${ARCH_PRIMARY}/${DESKTOP_ARCHFILE}" | awk '{print $1}')"
cat > "${DESKTOP_DBROOT}/desc" <<EOF
%FILENAME%
${DESKTOP_ARCHFILE}

%NAME%
${DESKTOP_PACKAGE}

%BASE%
${DESKTOP_PACKAGE}

%VERSION%
${DESKTOP_VERSION}-${DESKTOP_RELEASE}

%DESC%
Total.js Developer desktop integration

%CSIZE%
${DESKTOP_ARCHCSIZE}

%ISIZE%
${DESKTOP_ARCHSIZE}

%SHA256SUM%
${DESKTOP_ARCHSHA}

%URL%
https://totalvm.totaljs.es

%ARCH%
any

%BUILDDATE%
$(date +%s)

%PACKAGER%
Total.js <repository@totaljs.com>

%LICENSE%
custom

%DEPENDS%
openbox

EOF
(cd "${WORK}/db" && tar -czf "${OUT}/arch/${ARCH_PRIMARY}/totaljs-developer.db.tar.gz" \
  "${PACKAGE}-${VERSION}-${RELEASE}" "${DESKTOP_PACKAGE}-${DESKTOP_VERSION}-${DESKTOP_RELEASE}")
cp "${OUT}/arch/${ARCH_PRIMARY}/totaljs-developer.db.tar.gz" "${OUT}/arch/${ARCH_PRIMARY}/totaljs-developer.db"
gpg --batch --yes --local-user "${KEY_FPR}" --detach-sign --output "${OUT}/arch/${ARCH_PRIMARY}/totaljs-developer.db.tar.gz.sig" "${OUT}/arch/${ARCH_PRIMARY}/totaljs-developer.db.tar.gz"
cp "${OUT}/arch/${ARCH_PRIMARY}/totaljs-developer.db.tar.gz.sig" "${OUT}/arch/${ARCH_PRIMARY}/totaljs-developer.db.sig"

# The packages and the database are Architecture: any: the other architectures get the same files, signatures included
for ARCH_DIR in ${ARCH_DIRS}; do
  [ "${ARCH_DIR}" = "${ARCH_PRIMARY}" ] && continue
  mkdir -p "${OUT}/arch/${ARCH_DIR}"
  cp -p "${OUT}/arch/${ARCH_PRIMARY}"/* "${OUT}/arch/${ARCH_DIR}/"
done

# Image provisioning must never choose an obsolete package left by an earlier
# repository build. Clean only after every new artifact has been built and
# signed, preserving the last usable assets if a build fails midway.
find "${ASSETS}" -maxdepth 1 -type f \
  \( -name "${PACKAGE}_*_all.deb" \
     -o -name "${DESKTOP_PACKAGE}_*_all.deb" \
     -o -name "${PACKAGE}-*-any.pkg.tar.zst" \
     -o -name "${DESKTOP_PACKAGE}-*-any.pkg.tar.zst" \) \
  ! -name "${DEBFILE}" \
  ! -name "${DESKTOP_DEBFILE}" \
  ! -name "${ARCHFILE}" \
  ! -name "${DESKTOP_ARCHFILE}" \
  -delete

echo "[repo] complete"
echo "  repository: ${OUT}"
echo "  address inside the packages: ${BASE_URL}"
echo "  image assets: ${ASSETS}"
