#!/usr/bin/env bash
# Step 00 (Arch Server) — core CLI tooling, locale, network, shared /www
# environment, and Total.js metadata. Headless; no X/Openbox/browser.
set -euo pipefail

# `pac` is a resilient pacman wrapper exported by run.sh (retries on the flaky
# Arch Linux ARM mirror). Keep the keyring fresh, then install the core tooling.
# --needed
# skips anything already present from the base install.
pacman-key --init >/dev/null 2>&1 || true
pacman-key --populate archlinuxarm >/dev/null 2>&1 || true
pac -Sy --noconfirm archlinuxarm-keyring 2>/dev/null || pac -Sy --noconfirm || true

# Pacman deserves a little personality. Keep colored output enabled and use
# its built-in Pac-Man progress animation for interactive updates.
sed -i 's/^#Color$/Color/' /etc/pacman.conf
grep -qxF 'ILoveCandy' /etc/pacman.conf \
    || sed -i '/^Color$/a ILoveCandy' /etc/pacman.conf

# This image always boots the same Apple Virtualization display. Load its
# virtio DRM driver explicitly and skip hooks intended for x86 microcode and
# probing arbitrary physical GPUs. mkinitcpio includes module dependencies for
# MODULES entries automatically, so this is both quieter and more deterministic.
if [ -f /etc/mkinitcpio.conf ]; then
    if grep -q '^MODULES=' /etc/mkinitcpio.conf; then
        grep -q 'virtio_gpu' /etc/mkinitcpio.conf \
            || sed -i 's/^MODULES=(/MODULES=(virtio_gpu virtio_pci /' /etc/mkinitcpio.conf
    else
        echo 'MODULES=(virtio_gpu virtio_pci)' >> /etc/mkinitcpio.conf
    fi
    sed -Ei '/^HOOKS=/ {
        s/[[:space:]]+microcode([[:space:]])/\1/
        s/[[:space:]]+kms([[:space:]])/\1/
    }' /etc/mkinitcpio.conf
fi

pac -Su --noconfirm --needed \
    base-devel sudo curl wget git rsync unzip \
    vim nano less htop tmux jq zip zstd xz tar kbd \
    python \
    ca-certificates openssh man-db bash-completion \
    networkmanager \
    inetutils which cloud-guest-utils e2fsprogs

# --- Locale + hostname -----------------------------------------------------
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "totaljs-server" > /etc/hostname

# Arch applies /etc/vconsole.conf early, but the Apple virtualization console
# can come back on hvc0 with the default US keymap after reboot. Reapply the
# persisted KEYMAP on every boot so the first-run choice survives generically
# for every console layout.
install -d /usr/local/sbin
cat > /usr/local/sbin/totalvm-apply-keymap <<'EOF'
#!/usr/bin/env bash
set -u

conf=/etc/vconsole.conf
[ -f "${conf}" ] || exit 0
command -v loadkeys >/dev/null 2>&1 || exit 0

keymap="$(awk -F= '/^KEYMAP=/ {gsub(/"/, "", $2); print $2; exit}' "${conf}")"
[ -n "${keymap}" ] || exit 0

apply_keymap() {
    local console="${1:-}"
    if [ -n "${console}" ]; then
        loadkeys -C "${console}" "${keymap}" >/dev/null 2>&1 \
            || loadkeys -C "${console}" "${keymap%%-*}" >/dev/null 2>&1 \
            || true
    else
        loadkeys "${keymap}" >/dev/null 2>&1 \
            || loadkeys "${keymap%%-*}" >/dev/null 2>&1 \
            || true
    fi
}

apply_keymap
[ -e /dev/tty1 ] && apply_keymap /dev/tty1
[ -e /dev/hvc0 ] && apply_keymap /dev/hvc0
exit 0
EOF
chmod +x /usr/local/sbin/totalvm-apply-keymap

cat > /etc/systemd/system/totalvm-keymap.service <<'EOF'
[Unit]
Description=Apply TotalVM console keyboard layout
After=local-fs.target systemd-vconsole-setup.service
Wants=systemd-vconsole-setup.service
ConditionPathExists=/etc/vconsole.conf

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/totalvm-apply-keymap

[Install]
WantedBy=multi-user.target
EOF
systemctl enable totalvm-keymap.service >/dev/null 2>&1 || true

# --- Network: NetworkManager (matches the Ubuntu image) --------------------
systemctl enable NetworkManager.service >/dev/null 2>&1 || true
systemctl enable systemd-timesyncd.service >/dev/null 2>&1 || true
systemctl enable sshd.service >/dev/null 2>&1 || true
install -d -m 0700 /etc/NetworkManager/system-connections
cat > /etc/NetworkManager/system-connections/totaljs-wired.nmconnection <<'EOF'
[connection]
id=Total.js Wired
type=ethernet
autoconnect=true
autoconnect-priority=100

[ethernet]

[ipv4]
method=auto

[ipv6]
method=disabled
EOF
chmod 600 /etc/NetworkManager/system-connections/totaljs-wired.nmconnection

# --- sudo for the wheel group ----------------------------------------------
install -d -m 0750 /etc/sudoers.d
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

# --- Bootstrap "totaljs" account (the wizard later creates the real user) ---
# Mirrors the Ubuntu image's temporary account. The interactive Archboot install
# normally creates it already; this guard keeps provisioning self-contained.
if ! id totaljs >/dev/null 2>&1; then
    useradd -m -G wheel -s /bin/bash totaljs
    echo "totaljs:totaljs" | chpasswd
fi

# --- Shared environment root (/www), identical pattern to the Ubuntu image -
# The macOS app shares a host folder as virtiofs tag "www"; mount the whole
# environment root (/www) from it so the developer sees and edits the Docker
# Compose files, shared node_modules and projects straight from the Mac. The
# image's baked /www is moved to a seed template in 90-cleanup; totalvm-www-seed
# copies it into the share on first boot when the share is empty.
mkdir -p /www/www /www/code

cat > /etc/systemd/system/www.mount <<'EOF'
[Unit]
Description=Total.js Developer shared environment (/www, virtiofs)

[Mount]
What=www
Where=/www
Type=virtiofs
Options=rw,nofail

[Install]
WantedBy=multi-user.target
EOF
systemctl enable www.mount >/dev/null 2>&1 || true

cat > /usr/local/sbin/totalvm-www-seed <<'EOF'
#!/usr/bin/env bash
SEED=/var/lib/totalvm/www-seed
if [ -d "${SEED}" ] && [ ! -e /www/code ]; then
    cp -a "${SEED}/." /www/ 2>/dev/null || cp -r "${SEED}/." /www/ 2>/dev/null || true
    chown -R totaljs:totaljs /www 2>/dev/null || true
fi
for relative in proxy/docker-compose.yml code/docker-compose.yml \
    flow/docker-compose.yml \
    services/postgres/docker-compose.yml services/postgres/servers.json; do
    if [ ! -e "/www/${relative}" ] && [ -e "${SEED}/${relative}" ]; then
        mkdir -p "$(dirname "/www/${relative}")"
        cp "${SEED}/${relative}" "/www/${relative}" 2>/dev/null || true
    fi
done
DOMAIN="$(cat /etc/totalvm/domain 2>/dev/null || echo totaljs.developer)"
mkdir -p /www/proxy/data/vhost.d /www/proxy/data/html /www/proxy/totalcenter-gateway
cat > /www/proxy/totalcenter-gateway/default.conf <<'CENTER_NGINX'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://host.docker.internal:8010;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
CENTER_NGINX
cat > /www/proxy/docker-compose.yml <<CENTER_COMPOSE
services:
  nginx-proxy:
    container_name: totalvm-proxy
    image: nginxproxy/nginx-proxy:1.8.0
    restart: always
    ports:
      - "80:80"
    environment:
      - DISABLE_ACCESS_LOGS=true
      - DEFAULT_HOST=${DOMAIN}
    volumes:
      - ./data/vhost.d:/etc/nginx/vhost.d
      - ./data/html:/usr/share/nginx/html
      - /var/run/docker.sock:/tmp/docker.sock:ro

  totalcenter-gateway:
    container_name: totalcenter-gateway
    image: nginx:1.27-alpine
    restart: always
    expose:
      - "80"
    environment:
      - VIRTUAL_HOST=${DOMAIN}
      - VIRTUAL_PORT=80
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./totalcenter-gateway/default.conf:/etc/nginx/conf.d/default.conf:ro

networks:
  default:
    name: proxy
    external: true
CENTER_COMPOSE
for compose in /www/proxy/docker-compose.yml /www/code/docker-compose.yml \
    /www/flow/docker-compose.yml \
    /www/services/postgres/docker-compose.yml; do
    [ -f "${compose}" ] || continue
    sed -i \
        -e 's#nginxproxy/nginx-proxy:1.8.0@sha256:485d13410d4bdec689076066bbaca4bf3ba31e120bf9185e742fdd8b84135964#nginxproxy/nginx-proxy:1.8.0#' \
        -e 's#totalplatform/code:latest@sha256:d295812a041f50441534191e9c8efa00d48340c11dd06770d75ece55ed4cbeb9#totalplatform/code:latest#' \
        -e 's#postgres:17-alpine@sha256:f6d4c02e92bcfa6a4181a0c0fc7f74c6b5c935cec1bbb16a34e61761012f673e#postgres:17-alpine#' \
        "${compose}" 2>/dev/null || true
done
exit 0
EOF
chmod +x /usr/local/sbin/totalvm-www-seed

cat > /etc/systemd/system/totalvm-www-seed.service <<'EOF'
[Unit]
Description=Total.js Developer seed shared environment on first boot
After=www.mount
Wants=www.mount
Before=docker.service totalvm-proxy.service totalvm-code.service totalvm-flow.service totaljs-postgres.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/totalvm-www-seed

[Install]
WantedBy=multi-user.target
EOF
systemctl enable totalvm-www-seed.service >/dev/null 2>&1 || true

# --- Total.js metadata (read by TotalFetch / Total.js Center) -----------------
mkdir -p /etc/totalvm
cat > /etc/totalvm/release <<'EOF'
TOTALVM_NAME="Total.js Developer Distro (Server Edition)"
TOTALVM_ID="developer-arch-server"
EOF

# Expand the root partition/filesystem when TotalVM raises the sparse RAW's
# virtual limit. Idempotent, and a no-op once the filesystem fills the disk.
cat > /usr/local/sbin/totalvm-growroot <<'EOF'
#!/usr/bin/env bash
set -u
src="$(findmnt -no SOURCE / 2>/dev/null)" || exit 0
[ -b "${src}" ] || exit 0
name="$(basename "${src}")"
pkname="$(lsblk -no PKNAME "${src}" 2>/dev/null | head -1)"
partn="$(cat "/sys/class/block/${name}/partition" 2>/dev/null)"
[ -n "${pkname}" ] && [ -n "${partn}" ] || exit 0
growpart "/dev/${pkname}" "${partn}" >/dev/null 2>&1 || true
resize2fs "${src}" >/dev/null 2>&1 || true
EOF
chmod +x /usr/local/sbin/totalvm-growroot
cat > /etc/systemd/system/totalvm-growroot.service <<'EOF'
[Unit]
Description=Grow the root filesystem to fill the disk
After=local-fs.target
Before=docker.service totalvm-www-seed.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/totalvm-growroot

[Install]
WantedBy=multi-user.target
EOF
systemctl enable totalvm-growroot.service >/dev/null 2>&1 || true

# Default local domain (matches the Ubuntu image; project subdomains resolve
# via dnsmasq — see 28-dns).
if [ ! -f /etc/totalvm/domain ]; then
    echo "totaljs.developer" > /etc/totalvm/domain
fi

echo "[00-base] done"
