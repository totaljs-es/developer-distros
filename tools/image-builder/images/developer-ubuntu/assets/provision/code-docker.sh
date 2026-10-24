#!/usr/bin/env bash
# Total.js Developer — Code + nginx-proxy + Postgres/pgAdmin stacks (shared).
# a standalone nginx-proxy stack (like nginx-proxy-automation, minus the
# Let's Encrypt/SSL parts) on a shared EXTERNAL `proxy` network, with Code and
# the PostgreSQL/pgAdmin stack joining it. nginx-proxy routes by container
# VIRTUAL_HOST, which is exactly how Code auto-publishes each project it spins
# up over the docker socket — so projects, Code and pgAdmin all get a
# *.totaljs.developer URL with no per-service nginx editing. The root domain
# totaljs.developer is reserved for Total.js Center, the entry point for the VM.
#
# Reference (SSL stripped):
#   https://github.com/evertramos/nginx-proxy-automation
#   https://github.com/totaljs/code-cloud
#
# /www is the host-shared environment, so all these compose files are editable
# from the Mac.
set -euo pipefail

DOMAIN=totaljs.developer

install -d -o totaljs -g totaljs \
    /www/proxy/data/vhost.d /www/proxy/data/html \
    /www/proxy/totalcenter-gateway \
    /www/code /www/flow /www/node_modules /www/www \
    /www/services/postgres

if [ ! -f /etc/totalvm/domain ]; then
    echo "${DOMAIN}" > /etc/totalvm/domain
fi

# --- Courtesy shared node_modules in /www/node_modules ---------------------
# Always-needed Total.js packages, pre-installed into the shared FOLDER_NPM so
# the user starts with them ready. Non-fatal.
if command -v npm >/dev/null 2>&1; then
    ( cd /www && npm install --no-fund --no-audit total4 total5 querybuilderpg ) \
        || echo "[25-code-docker] WARNING: courtesy npm install failed; user can install later" >&2
    chown -R totaljs:totaljs /www/node_modules /www/package.json /www/package-lock.json 2>/dev/null || true
fi

# --- Reverse proxy: standalone nginx-proxy stack ---------------------------
# Own stack on the external `proxy` network, exactly like a real deployment.
# Per-domain nginx tweaks go in /www/proxy/data/vhost.d (see code-cloud docs).
# totalcenter-gateway publishes the host-side Total.js Center systemd service at
# the root domain so http://totaljs.developer becomes the main entry point.
cat > /www/proxy/totalcenter-gateway/default.conf <<'EOF'
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
EOF

cat > /www/proxy/docker-compose.yml <<'EOF'
services:
  nginx-proxy:
    container_name: totalvm-proxy
    image: nginxproxy/nginx-proxy:1.8.0
    restart: always
    ports:
      - "80:80"
    environment:
      - DISABLE_ACCESS_LOGS=true
      - DEFAULT_HOST=totaljs.developer
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
      - VIRTUAL_HOST=totaljs.developer
      - VIRTUAL_PORT=80
    extra_hosts:
      - "host.docker.internal:host-gateway"
    volumes:
      - ./totalcenter-gateway/default.conf:/etc/nginx/conf.d/default.conf:ro

networks:
  default:
    name: proxy
    external: true
EOF

# --- Total.js Flow ---------------------------------------------------------
cat > /www/flow/docker-compose.yml <<'EOF'
services:
  flow:
    container_name: flow
    image: totalplatform/flow:latest
    restart: always
    environment:
      - VIRTUAL_HOST=flow.totaljs.developer
      - VIRTUAL_PORT=8000
    volumes:
      - databases:/www/.src/databases/
      - flowstream:/www/.src/flowstream/

volumes:
  databases:
  flowstream:

networks:
  default:
    name: proxy
    external: true
EOF

# --- Total.js Code (the official code-cloud compose, minus SSL) ------------
cat > /www/code/docker-compose.yml <<'EOF'
services:
  code:
    container_name: code
    image: totalplatform/code:latest
    restart: always
    volumes:
      - codedata:/code/databases
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /www/www/:/www/www
      - /www/node_modules/:/www/node_modules
    environment:
      - UID=code
      - FOLDER_WWW=/www/www/
      - FOLDER_NPM=/www/node_modules/
      # The URL pattern Code publishes each project at — {0} is the project's
      # subdomain, so a new project goes live at http://<project>.totaljs.developer.
      # http (not https): this proxy terminates no TLS (Let's Encrypt stripped).
      - ORIGIN=http://{0}.totaljs.developer
      - VIRTUAL_HOST=code.totaljs.developer
      - VIRTUAL_PORT=8000
      - VIRTUAL_MAX_UPLOAD=100
      - DISABLE_ACCESS_LOGS=1

volumes:
  codedata:

networks:
  default:
    name: proxy
    external: true
EOF

# --- PostgreSQL + pgAdmin (own editable stack, joins the proxy network) ----
cat > /www/services/postgres/servers.json <<'EOF'
{
  "Servers": {
    "1": {
      "Name": "Total.js PostgreSQL",
      "Group": "Servers",
      "Host": "postgres",
      "Port": 5432,
      "Username": "totaljs",
      "MaintenanceDB": "postgres",
      "SSLMode": "prefer"
    }
  }
}
EOF

cat > /www/services/postgres/docker-compose.yml <<'EOF'
services:
  postgres:
    container_name: postgres
    image: postgres:17-alpine
    restart: always
    environment:
      POSTGRES_USER: totaljs
      POSTGRES_HOST_AUTH_METHOD: trust
    volumes:
      - data:/var/lib/postgresql/data
    networks:
      - default

  pgadmin:
    container_name: pgadmin
    image: dpage/pgadmin4:latest
    restart: always
    depends_on:
      - postgres
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@totaljs.developer
      PGADMIN_DEFAULT_PASSWORD: admin
      PGADMIN_CONFIG_SERVER_MODE: 'False'
      PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED: 'False'
      PGADMIN_DISABLE_POSTFIX: 'True'
      PGADMIN_CONFIG_PROXY_X_FOR_COUNT: '1'
      PGADMIN_CONFIG_PROXY_X_PROTO_COUNT: '1'
      PGADMIN_CONFIG_PROXY_X_HOST_COUNT: '1'
      PGADMIN_CONFIG_PROXY_X_PORT_COUNT: '1'
      PGADMIN_CONFIG_PROXY_X_PREFIX_COUNT: '1'
      # Force gunicorn onto IPv4 — by default it binds [::]:80 (IPv6), and
      # nginx-proxy reaches the container over the IPv4 docker network, so an
      # IPv6-only backend gives a 502.
      PGADMIN_LISTEN_ADDRESS: '0.0.0.0'
      VIRTUAL_HOST: pgadmin.totaljs.developer
      VIRTUAL_PORT: '80'
    volumes:
      - pgadmindata:/var/lib/pgadmin
      - ./servers.json:/pgadmin4/servers.json:ro
    networks:
      - default

volumes:
  data:
  pgadmindata:

networks:
  default:
    name: proxy
    external: true
EOF

chown -R totaljs:totaljs /www/proxy /www/code /www/flow /www/services

# --- Pre-pull every image at build time so first boot is instant/offline ---
# These services define the product experience. A build without them is broken,
# so transient registry failures are retried and then abort provisioning.
systemctl start docker
for _ in $(seq 1 30); do
    docker info >/dev/null 2>&1 && break
    sleep 1
done
docker info >/dev/null 2>&1 || { echo "[25-code-docker] Docker daemon did not become ready" >&2; exit 1; }
docker network create proxy >/dev/null 2>&1 || true

pull_with_retry() {
    local description="$1"; shift
    local attempt available_mb
    for attempt in 1 2 3; do
        if ! docker info >/dev/null 2>&1; then
            echo "[25-code-docker] recovering Docker before ${description} (attempt ${attempt})" >&2
            systemctl reset-failed containerd docker >/dev/null 2>&1 || true
            systemctl restart containerd docker >/dev/null 2>&1 || true
            for _ in $(seq 1 30); do
                docker info >/dev/null 2>&1 && break
                sleep 1
            done
            docker info >/dev/null 2>&1 || continue
        fi

        available_mb="$(df --output=avail -m / | tail -n 1 | tr -d ' ')"
        if [ "${available_mb}" -lt 3072 ]; then
            echo "[25-code-docker] only ${available_mb} MiB free before ${description}; refusing to risk filesystem corruption" >&2
            docker system df >&2 || true
            df -h / >&2
            return 1
        fi

        if "$@"; then
            available_mb="$(df --output=avail -m / | tail -n 1 | tr -d ' ')"
            echo "[25-code-docker] ${description} ready (${available_mb} MiB free)"
            return 0
        fi
        echo "[25-code-docker] ${description} pull failed (${attempt}/3)" >&2
        sleep $((attempt * 5))
    done
    echo "[25-code-docker] ${description} is required; aborting the image build" >&2
    return 1
}

for stack in /www/proxy /www/code /www/flow; do
    pull_with_retry "${stack}" docker compose -f "${stack}/docker-compose.yml" pull
done
# Pull the database tools sequentially. Concurrent extraction of both large
# images can exhaust the small build VM and take the daemon down mid-layer.
pull_with_retry "PostgreSQL" docker pull postgres:17-alpine
pull_with_retry "pgAdmin" docker pull dpage/pgadmin4:latest
# totalplatform/run:npm is the per-project runtime image Code spins up.
pull_with_retry "Total.js project runtime" docker pull totalplatform/run:npm

docker image inspect \
    nginxproxy/nginx-proxy:1.8.0 \
    nginx:1.27-alpine \
    totalplatform/code:latest \
    totalplatform/flow:latest \
    postgres:17-alpine \
    dpage/pgadmin4:latest \
    totalplatform/run:npm >/dev/null

# A full filesystem can make ordinary binaries fail with misleading SIGSEGV or
# SIGILL errors. Keep a clear safety margin for systemd, logs and final cleanup.
AVAILABLE_MB="$(df --output=avail -m / | tail -n 1 | tr -d ' ')"
if [ "${AVAILABLE_MB}" -lt 1024 ]; then
    echo "[25-code-docker] less than 1 GiB remains after pulling images; increase disk_gb" >&2
    df -h / >&2
    exit 1
fi

# --- systemd units: proxy → code → postgres --------------------------------
cat > /etc/systemd/system/totalvm-proxy.service <<'EOF'
[Unit]
Description=Total.js Developer reverse proxy (nginx-proxy)
Requires=docker.service www.mount totalvm-www-seed.service
After=docker.service www.mount totalvm-www-seed.service totalcenter.service network-online.target
Wants=network-online.target totalcenter.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/www/proxy
# The shared external network every stack joins so nginx-proxy can route them.
ExecStartPre=-/usr/bin/docker network create proxy
ExecStart=/usr/bin/docker compose -f docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml down --timeout 10
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
install -d /etc/systemd/system/multi-user.target.wants
ln -sfn ../totalvm-proxy.service \
    /etc/systemd/system/multi-user.target.wants/totalvm-proxy.service

cat > /etc/systemd/system/totalvm-code.service <<'EOF'
[Unit]
Description=Total.js Code
Requires=docker.service www.mount totalvm-www-seed.service totalvm-proxy.service
After=docker.service www.mount totalvm-www-seed.service totalvm-proxy.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/www/code
ExecStart=/usr/bin/docker compose -f docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml down --timeout 10
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
ln -sfn ../totalvm-code.service \
    /etc/systemd/system/multi-user.target.wants/totalvm-code.service

for app in flow; do
    cat > "/etc/systemd/system/totalvm-${app}.service" <<EOF
[Unit]
Description=Total.js ${app}
Requires=docker.service www.mount totalvm-www-seed.service totalvm-proxy.service
After=docker.service www.mount totalvm-www-seed.service totalvm-proxy.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/www/${app}
ExecStart=/usr/bin/docker compose -f docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml down --timeout 10
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
    ln -sfn "../totalvm-${app}.service" \
        "/etc/systemd/system/multi-user.target.wants/totalvm-${app}.service"
done

cat > /etc/systemd/system/totaljs-postgres.service <<'EOF'
[Unit]
Description=Total.js Developer PostgreSQL + pgAdmin
Requires=docker.service totalvm-proxy.service
After=docker.service totalvm-proxy.service totalvm-code.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/www/services/postgres
ExecStart=/usr/bin/docker compose -f docker-compose.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose.yml down --timeout 10
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
ln -sfn ../totaljs-postgres.service \
    /etc/systemd/system/multi-user.target.wants/totaljs-postgres.service

# --- Desktop launchers -----------------------------------------------------
cat > /usr/local/bin/totaljs-code-open <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DOMAIN="$(cat /etc/totalvm/domain 2>/dev/null || echo totaljs.developer)"
totaljs-open "http://code.${DOMAIN}"
EOF
chmod +x /usr/local/bin/totaljs-code-open

for app in flow; do
    cat > "/usr/local/bin/totaljs-${app}-open" <<EOF
#!/usr/bin/env bash
set -euo pipefail
DOMAIN="\$(cat /etc/totalvm/domain 2>/dev/null || echo totaljs.developer)"
totaljs-open "http://${app}.\${DOMAIN}"
EOF
    chmod +x "/usr/local/bin/totaljs-${app}-open"
done

cat > /usr/local/bin/totaljs-pgadmin-open <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DOMAIN="$(cat /etc/totalvm/domain 2>/dev/null || echo totaljs.developer)"
totaljs-open "http://pgadmin.${DOMAIN}"
EOF
chmod +x /usr/local/bin/totaljs-pgadmin-open

echo "[25-code-docker] done"
