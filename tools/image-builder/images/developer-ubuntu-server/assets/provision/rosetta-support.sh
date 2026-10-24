#!/usr/bin/env bash
# Shared Apple Rosetta support for TotalVM Linux guests.
set -euo pipefail

configure_ubuntu_amd64_sources() {
    [ "$(dpkg --print-architecture)" = "arm64" ] || return 0

    # Ubuntu ARM cloud images use ports.ubuntu.com. Once amd64 is added as a
    # foreign architecture, APT also asks that ARM mirror for amd64 indexes and
    # receives 404s. Scope those existing sources to arm64, then add regular
    # Ubuntu amd64 archives as separate architecture-filtered deb822 sources.
    for source_file in /etc/apt/sources.list.d/*.sources; do
        [ -f "${source_file}" ] || continue
        grep -q 'ports.ubuntu.com/ubuntu-ports' "${source_file}" || continue

        python3 - "${source_file}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
blocks = text.split("\n\n")
updated = []
for block in blocks:
    if "ports.ubuntu.com/ubuntu-ports" not in block:
        updated.append(block)
        continue

    lines = block.splitlines()
    replaced = False
    out = []
    for line in lines:
        if line.startswith("Architectures:"):
            out.append("Architectures: arm64")
            replaced = True
        else:
            out.append(line)
            if not replaced and line.startswith("URIs:"):
                out.append("Architectures: arm64")
                replaced = True
    if not replaced:
        out.append("Architectures: arm64")
    updated.append("\n".join(out))
path.write_text("\n\n".join(updated).rstrip() + "\n")
PY
    done

    if [ -f /etc/apt/sources.list ] && grep -q 'ports.ubuntu.com/ubuntu-ports' /etc/apt/sources.list; then
        sed -Ei '/ports\.ubuntu\.com\/ubuntu-ports/ {
            /^[[:space:]]*deb[[:space:]]+\[/! s#^[[:space:]]*deb[[:space:]]+#deb [arch=arm64] #
            /^[[:space:]]*deb[[:space:]]+\[/ s#^([[:space:]]*deb[[:space:]]+\[)([^]]*)\]#\1arch=arm64 \2]#
        }' /etc/apt/sources.list
    fi

    cat > /etc/apt/sources.list.d/ubuntu-amd64.sources <<'EOF'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: noble noble-updates noble-backports
Components: main universe restricted multiverse
Architectures: amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://security.ubuntu.com/ubuntu
Suites: noble-security
Components: main universe restricted multiverse
Architectures: amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
}

if command -v dpkg >/dev/null 2>&1; then
    if ! dpkg --print-foreign-architectures | grep -qx amd64; then
        dpkg --add-architecture amd64
    fi
    configure_ubuntu_amd64_sources
    apt-get update

    # Rosetta translates the CPU instructions, but dynamically linked Intel
    # binaries still need the x86_64 loader and common runtime libraries.
    apt-get install -y --no-install-recommends \
        libc6:amd64 \
        libgcc-s1:amd64 \
        libstdc++6:amd64 \
        zlib1g:amd64 \
        libzstd1:amd64 \
        liblzma5:amd64 \
        libtinfo6:amd64 \
        libncurses6:amd64 \
        libx11-6:amd64 \
        libxext6:amd64 \
        libxcb1:amd64 \
        libxau6:amd64 \
        libxdmcp6:amd64 \
        libbsd0:amd64 \
        libmd0:amd64
fi

install -d /media/rosetta /etc/systemd/system

cat > /usr/local/sbin/totalvm-rosetta-setup <<'EOF'
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

# Match 64-bit little-endian Linux x86_64 ELF files. Register both executable
# and PIE/shared-object forms explicitly; some games and launchers ship PIE
# binaries and otherwise fall through to "Exec format error".
elf_prefix='\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00'
elf_mask='\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff'
register_rosetta rosetta-x86_64 "${elf_prefix}"'\x02\x00\x3e\x00' "${elf_mask}"
register_rosetta rosetta-x86_64-pie "${elf_prefix}"'\x03\x00\x3e\x00' "${elf_mask}"
EOF
chmod +x /usr/local/sbin/totalvm-rosetta-setup

cat > /etc/systemd/system/totalvm-rosetta.service <<'EOF'
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

systemctl daemon-reload >/dev/null 2>&1 || true
systemctl enable totalvm-rosetta.service >/dev/null 2>&1 || true

echo "[rosetta] Apple Rosetta Linux support enabled"
