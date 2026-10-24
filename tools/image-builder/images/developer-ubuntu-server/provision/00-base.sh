#!/usr/bin/env bash
# Step 00 — headless Ubuntu server base with the shared /www environment.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# The Ubuntu ports mirror intermittently drops or times out plain HTTP through
# Apple Virtualization NAT. Its HTTPS endpoint is reliable on the same route;
# normalize the inherited cloud-image sources before the first apt operation.
sed -i 's#http://ports\.ubuntu\.com/ubuntu-ports#https://ports.ubuntu.com/ubuntu-ports#g' \
    /etc/apt/sources.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true

# Ubuntu cloud images mount ext4 with continuous `discard`, an optimization for
# cloud block devices. On a sparse RAW attached through Virtualization.framework
# it can race sustained Docker/apt writes and make ext4 abort its journal, after
# which Linux remounts `/` read-only. Keep the sparse image, but use ordinary
# writes; the packaging stage handles image compaction explicitly.
# `discard` is the first option in Ubuntu's fstab (after whitespace), not
# necessarily comma-delimited on its left. Match either position; the previous
# comma-only expression silently left it active in every published image.
sed -i -E 's/(^|[[:space:],])discard,?/\1/g; s/,,+/,/g' /etc/fstab
mount -o remount,nodiscard / || true

# The original Noble kernel is not reliable enough for the sustained package
# workload in Apple Virtualization. The Mac builder places the current HWE
# packages on the seed, letting us switch kernels without running apt or any of
# its helper methods on this first boot.
LATEST_KERNEL="$(basename "$(readlink -f /boot/vmlinuz)" | sed 's/^vmlinuz-//')"
if [ "$(uname -r)" != "${LATEST_KERNEL}" ] || [ ! -e /var/lib/totalvm-hwe-bootstrapped ]; then
    shopt -s nullglob
    KERNEL_DEBS=(
        /mnt/totalvm-seed/kernel/linux-image-[0-9]*.deb
        /mnt/totalvm-seed/kernel/linux-modules-[0-9]*.deb
    )
    shopt -u nullglob
    [ "${#KERNEL_DEBS[@]}" -gt 0 ] || { echo "[00-base] offline HWE packages are missing" >&2; exit 1; }
    echo "[00-base] installing HWE kernel offline before apt"
    dpkg -i "${KERNEL_DEBS[@]}"
    touch /var/lib/totalvm-hwe-bootstrapped
    LATEST_KERNEL="$(basename "$(readlink -f /boot/vmlinuz)" | sed 's/^vmlinuz-//')"
    if [ "$(uname -r)" != "${LATEST_KERNEL}" ]; then
        echo "[00-base] rebooting from $(uname -r) into stable HWE kernel ${LATEST_KERNEL}"
        sync
        systemctl reboot --no-block
        trap 'exit 1' TERM INT
        while :; do sleep 5; done
    fi
fi

# Cloud-init masks apt-daily and unattended-upgrades before this script starts.
# Do not repeat `systemctl mask` here: on a first cloud-image boot systemd can
# block indefinitely while reloading those generated units. Waiting for any
# lock already acquired before the mask is sufficient and deterministic.
for _ in $(seq 1 90); do
    if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
        || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
        echo "[00-base] waiting for the apt/dpkg lock to be released..."
        sleep 2
    else
        break
    fi
done

# Belt-and-suspenders for the large-download stall (cloud-init sets this via
# systemd, but force it again right before the first apt fetch in case the
# network config didn't apply in time). `ip` is always present; ethtool is
# best-effort.
for _nic in $(ls /sys/class/net 2>/dev/null | grep -E '^(en|eth)'); do
    ip link set dev "${_nic}" mtu 1400 2>/dev/null || true
    if command -v ethtool >/dev/null 2>&1; then
        ethtool -K "${_nic}" tso off gso off gro off lro off 2>/dev/null || true
    fi
done

# THE fix (proven by the diagnostic): a verbose curl of the same 15MB index
# downloads fine, but apt hangs. The mirror (Cloudflare) advertises IPv6 + IPv4;
# curl uses Happy Eyeballs and instantly picks IPv4, but apt tries IPv6 first
# and the VM's NAT doesn't route IPv6, so apt waits on a dead connection
# forever. Disabling IPv6 entirely leaves nothing to stall on. (This is a
# NAT'd dev VM — Apple's NAT is IPv4-only anyway, so IPv6 never worked here.)
cat > /etc/sysctl.d/99-totalvm-noipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl -p /etc/sysctl.d/99-totalvm-noipv6.conf >/dev/null 2>&1 || true

cat > /etc/apt/apt.conf.d/80totalvm-retries <<'EOF'
Acquire::Retries "5";
Acquire::http::Timeout "30";
Acquire::https::Timeout "30";
DPkg::Lock::Timeout "300";
Acquire::ForceIPv4 "true";
# THE fix for the deterministic hang: apt-get update lists every index then
# freezes while fetching them. apt pipelines multiple HTTP requests on one
# keep-alive connection; the NAT in Apple's Virtualization framework desyncs
# the pipelined responses and apt waits forever for a reply that never comes.
# Pipeline-Depth 0 = one request per response, no desync. Also avoid reusing
# a possibly-wedged keep-alive connection.
Acquire::http::Pipeline-Depth "0";
Acquire::http::No-Cache "true";
# The mirror is Cloudflare-fronted. A single curl works, but apt reuses
# keep-alive connections across its 54 index fetches and wedges. Force a fresh
# connection per request (like curl) so there's no reused connection to wedge.
Acquire::http::Keep-Alive "false";
EOF

# Cloud images ship PackageKit, command-not-found and update-notifier hooks
# that run unrelated D-Bus/Python programs after APT. They are useless in a
# headless image build and were the processes actually dying with SIGILL while
# apt itself had already fetched every index successfully.
cat > /etc/apt/apt.conf.d/99totalvm-no-post-hooks <<'EOF'
#clear APT::Update::Post-Invoke;
#clear APT::Update::Post-Invoke-Success;
#clear DPkg::Post-Invoke;
#clear DPkg::Post-Invoke-Success;
EOF

# Kill needrestart for the whole build: its post-apt "Scanning processes /
# outdated hypervisor (qemu)" check hangs in this VM (confirmed by a manual apt
# upgrade freezing exactly there). Remove its apt hook so it never runs after
# any apt operation, plus a neutering config in case it's reinstalled. It is
# also purged below once apt works.
rm -f /etc/apt/apt.conf.d/99needrestart
mkdir -p /etc/needrestart/conf.d
cat > /etc/needrestart/conf.d/00-totalvm-disable.conf <<'EOF'
$nrconf{restart} = 'a';
$nrconf{kernelhints} = -1;
$nrconf{ucodehints} = 0;
$nrconf{hook_d} = [];
EOF

# Remove the post-update apt hooks that phone Canonical (Ubuntu Pro/ESM,
# apt-news, appstream) — cloud-init already does this, but repeat it here in
# case the package set differs. They hang apt-get update after all indices
# download (confirmed via the HTTP debug trace).
# `|| true`: cloud-init already removed these, so grep here finds nothing and
# exits 1, which under `set -e`+pipefail would abort the whole step.
{ grep -rlE 'esm|ubuntu-advantage|ubuntu.pro|apt.news|apt_news|appstream|packagekit' \
    /etc/apt/apt.conf.d/ 2>/dev/null || true; } | xargs -r rm -f || true
rm -f /etc/apt/apt.conf.d/20packagekit 2>/dev/null || true

dpkg --configure -a

apt-get update

apt-get install -y --no-install-recommends linux-image-virtual-hwe-24.04

# The cloud image also carries the GA `linux-generic` metapackage. Keeping both
# tracks makes every ordinary upgrade download a second 6.8 kernel and can move
# /boot/vmlinuz away from the HWE kernel TotalVM actually validates. Remove only
# the GA metapackages; the already-installed versioned 6.8 kernel remains as a
# recovery option alongside the active HWE line.
apt-get purge -y \
    linux-generic linux-image-generic linux-headers-generic linux-tools-generic \
    linux-virtual linux-image-virtual linux-headers-virtual linux-tools-virtual \
    2>/dev/null || true

apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release \
    git unzip zip zstd xz-utils \
    build-essential pkg-config \
    python3-minimal \
    htop nano vim less tree jq \
    openssh-server \
    sudo tmux ufw fail2ban \
    locales keyboard-configuration console-setup \
    software-properties-common

systemctl enable ssh

# The publishable image deliberately removes inherited SSH host keys. Generate
# fresh keys before ssh.service validates its configuration on first boot; this
# avoids the repeated red "Failed to start ssh.service" messages while keeping
# every installed VM cryptographically unique.
cat > /etc/systemd/system/totaljs-ssh-hostkeys.service <<'EOF'
[Unit]
Description=Generate Total.js Developer SSH host keys
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
EOF
mkdir -p /etc/systemd/system/ssh.service.d
cat > /etc/systemd/system/ssh.service.d/10-totaljs-hostkeys.conf <<'EOF'
[Unit]
Requires=totaljs-ssh-hostkeys.service
After=totaljs-ssh-hostkeys.service
EOF
systemctl enable totaljs-ssh-hostkeys.service

# Keep the image focused: no snap store, firmware updater, Ubuntu Pro prompts,
# needrestart (its hypervisor scan hangs), or Ubuntu's inherited Byobu terminal.
# `ubuntu-server` is only a dependency metapackage; removing it with Byobu does
# not remove the server or anything explicitly installed above.
apt-get purge -y \
    snapd fwupd ubuntu-pro-client ubuntu-advantage-tools needrestart \
    byobu ubuntu-server \
    || true
rm -rf /snap /var/snap /var/lib/snapd /var/cache/snapd

# Shared environment root. See the www.mount unit below — the host folder is
# attached at /www. "nofail" keeps boot from blocking if the host ever omits
# the share (e.g. a fresh distro with no shared folder configured yet); the
# seed then populates the local /www instead.
mkdir -p /www/www /www/code
chown -R totaljs:totaljs /www
# The macOS app shares a host folder as virtiofs tag "www". Mount the WHOLE
# environment root (/www) from it, so the developer sees and edits the Docker
# Compose files (/www/code, /www/services), the shared node_modules and their
# projects (/www/www) straight from the Mac. The image's baked /www is moved to
# a seed template in 90-cleanup; totalvm-www-seed (below) copies it into the
# share on first boot when the share is empty — so a fresh VM still has a
# working environment and nothing the build produced is lost.
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
systemctl enable www.mount

# First-boot seed. Best-effort and always exits 0 so it can never block the
# services ordered after it (Code/PostgreSQL). chown is guarded because virtiofs
# may map ownership to the host and reject it.
cat > /usr/local/sbin/totalvm-www-seed <<'EOF'
#!/usr/bin/env bash
SEED=/var/lib/totalvm/www-seed
if [ -d "${SEED}" ] && [ ! -e /www/code ]; then
    cp -a "${SEED}/." /www/ 2>/dev/null || cp -r "${SEED}/." /www/ 2>/dev/null || true
    chown -R totaljs:totaljs /www 2>/dev/null || true
fi
# Complete an existing shared environment without overwriting user edits.
for relative in proxy/docker-compose.yml code/docker-compose.yml \
    flow/docker-compose.yml \
    services/postgres/docker-compose.yml services/postgres/servers.json; do
    if [ ! -e "/www/${relative}" ] && [ -e "${SEED}/${relative}" ]; then
        mkdir -p "$(dirname "/www/${relative}")"
        cp "${SEED}/${relative}" "/www/${relative}" 2>/dev/null || true
    fi
done
# Keep the root domain pinned to Total.js Center even when /www already comes
# from an older VM. This intentionally repairs only the proxy stack.
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
# Migrate only the digests generated by TotalVM 1.0; user-selected image tags
# and every other Compose edit remain untouched.
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
systemctl enable totalvm-www-seed.service

# --- Grow the root filesystem to fill the whole disk -----------------------
# The image is BUILT small (~14 GB) but the macOS app provisions a much larger
# (sparse) disk per VM — costing nothing on the Mac until used. This expands the
# root partition + ext4 to fill whatever size the app handed us, so the VM has
# the full "grows as you use it" headroom. Idempotent + best-effort, runs every
# boot (a no-op once the fs already fills the disk). growpart/resize2fs do this
# online, with the root mounted.
apt-get install -y --no-install-recommends cloud-guest-utils e2fsprogs >/dev/null 2>&1 || true
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
exit 0
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

# Persisted TotalVM metadata used by TotalFetch / Total.js Center.
mkdir -p /etc/totalvm
cat > /etc/totalvm/release <<'EOF'
TOTALVM_NAME="Total.js Developer Distro (Server Edition)"
TOTALVM_ID="developer-ubuntu-server"
EOF

echo "[00-base] done"
