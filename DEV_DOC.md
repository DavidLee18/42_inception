# Developer Documentation

This document is for developers setting up, building, running, and maintaining the Inception stack.

## Prerequisites

| Tool                  | Minimum version | Check                      |
| --------------------- | --------------- | -------------------------- |
| Docker Engine         | 24.0            | `docker --version`         |
| Docker Compose plugin | 2.20            | `docker compose version`   |
| `make`                | any             | `make --version`           |
| `git`                 | any             | `git --version`            |
| A VM or Linux host    | —               | subject mandates a VM      |

The Docker daemon must be running (`sudo systemctl start docker` on Linux, or open Docker Desktop on macOS/Windows).

---

## Setting up the environment from scratch

### 1. Clone the repository

```zsh
git clone https://github.com/DavidLee18/42_inception.git
cd 42_inception
```

### 2. Enable Docker daemon metrics on the host

The `monitoring` container scrapes the Docker daemon's built-in Prometheus metrics endpoint. This must be enabled on the host **before** starting the stack.

Add or merge the following into `/etc/docker/daemon.json`:

```json
{
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
```

Then restart Docker and verify:

```zsh
sudo systemctl restart docker
curl -s http://localhost:9323/metrics | head -5
```

### 3. Create the thirteen secret files

The stack requires thirteen secret files in `secrets/` at the repository root. Create them manually — never commit them.

```zsh
mkdir -p secrets
echo "strongrootpassword"   > secrets/db_root_password.txt
echo "wordpress"            > secrets/db_name.txt
echo "wpuser"               > secrets/db_user.txt
echo "strongwppassword"     > secrets/db_password.txt
echo "strongredispassword"  > secrets/redis_password.txt
echo "jaehylee"             > secrets/wp_admin_user.txt   # must NOT contain "admin" (any case)
echo "strongadminpassword"  > secrets/wp_admin_password.txt
echo "jaehylee@42seoul.kr"  > secrets/wp_admin_email.txt
echo "subscriber1"          > secrets/wp_user.txt
echo "stronguserpassword"   > secrets/wp_user_password.txt
echo "user@42seoul.kr"      > secrets/wp_user_email.txt
echo "ftpuser"              > secrets/ftp_user.txt
echo "strongftppassword"    > secrets/ftp_password.txt
```

> **Constraint:** the WordPress administrator username must not contain `admin` (case-insensitive). `srcs/wordpress/entrypoint.sh` enforces this at startup and exits with an error if violated.

Verify `secrets/` is gitignored:

```zsh
grep -E '^secrets/?$' .gitignore   # must return "secrets/" or "secrets"
```

### 4. Add the domain to your hosts file (local development only)

```zsh
echo "127.0.0.1  jaehylee.42.fr" | sudo tee -a /etc/hosts
```

### 5. Verify the project layout

The subject mandates a `srcs/` folder for configuration files. Expected layout:

```
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── LICENSE
├── secrets/                         # 13 files as created above (gitignored)
└── srcs/
    ├── docker-compose.yml
    ├── .env                         # non-sensitive env vars only (e.g. DOMAIN_NAME)
    ├── nginx/
    │   ├── Dockerfile               # Alpine 3.22.3 + nginx + openssl
    │   └── nginx.conf               # ssl_protocols TLSv1.3; FastCGI → wordpress:9000
    ├── mariadb/
    │   ├── Dockerfile               # Alpine 3.22.3 + mariadb (custom-built)
    │   ├── my.cnf                   # bind-address 0.0.0.0, utf8mb4
    │   └── entrypoint.sh            # reads 4 secrets, runs mysql_install_db once
    ├── wordpress/
    │   ├── Dockerfile               # Alpine 3.22.3 + php83-fpm + wp-cli
    │   ├── php-fpm.conf             # listens on 0.0.0.0:9000
    │   └── entrypoint.sh            # reads 10 secrets, writes wp-config.php, wp core install
    ├── redis/
    │   ├── Dockerfile               # Alpine 3.22.3 + redis
    │   ├── redis.conf               # allkeys-lru, maxmemory 128mb, dangerous cmds disabled
    │   └── entrypoint.sh            # reads secret, passes --requirepass at runtime
    ├── ftp/
    │   ├── Dockerfile               # Alpine 3.22.3 + vsftpd
    │   ├── vsftpd.conf              # passive ports 21100–21110, chroot jail
    │   └── entrypoint.sh            # reads secrets, creates FTP user at runtime
    ├── static/
    │   ├── Dockerfile               # multi-stage: CBQN builder + nginx server
    │   ├── nginx.conf               # listens on 8080
    │   ├── template.bqn             # real barbell BQN template engine
    │   └── site/
    │       ├── template.html
    │       ├── style.css
    │       └── *.bar                # fragments substituted by barbell at build time
    ├── adminer/
    │   ├── Dockerfile               # Alpine 3.22.3 + php83-fpm + nginx + Adminer 4.8.1
    │   ├── nginx.conf               # listens on 8081, IP allowlist for private ranges
    │   └── php-fpm.conf             # listens on 127.0.0.1:9001
    ├── monitoring/
    │   ├── Dockerfile               # Alpine 3.22.3 + prometheus + grafana + supervisor
    │   ├── supervisord.conf         # runs prometheus + grafana as child processes
    │   ├── prometheus.yml           # scrapes docker-host:9323, localhost:9090, cadvisor:8080
    │   └── grafana/
    │       ├── provisioning/
    │       │   ├── datasources/prometheus.yml   # auto-wires Prometheus as default datasource
    │       │   └── dashboards/dashboard.yml     # tells Grafana where to load JSON dashboards
    │       └── dashboards/
    │           └── docker.json                  # pre-built Docker-containers dashboard
    └── cadvisor/
        ├── Dockerfile               # Alpine 3.22.3 + python3 + curl
        └── exporter.py              # custom Prometheus exporter over /var/run/docker.sock
```

---

## Building and launching the project

### Using the Makefile (recommended)

```zsh
# Build all images from scratch and start all nine containers in the background
make

# Stop all containers (all volumes preserved)
make down

# Stop all containers, delete all volumes, remove all images
make fclean

# Full rebuild from scratch
make re
```

### Actual Makefile

```makefile
NAME    = inception

all: $(NAME)

$(NAME):
	docker compose -f srcs/docker-compose.yml build --no-cache
	docker compose -f srcs/docker-compose.yml up -d

down:
	docker compose -f srcs/docker-compose.yml down

fclean: down
	docker compose -f srcs/docker-compose.yml down --volumes --rmi all --remove-orphans
	docker image prune -af

re: fclean all

.PHONY: all down fclean re
```

### Using Docker Compose directly

Because the compose file lives under `srcs/`, every raw compose command must pass `-f srcs/docker-compose.yml`:

```zsh
# Build images and start in detached mode
docker compose -f srcs/docker-compose.yml up -d --build

# Start without rebuilding
docker compose -f srcs/docker-compose.yml up -d

# Stop containers
docker compose -f srcs/docker-compose.yml down

# Stop containers and destroy all volumes
docker compose -f srcs/docker-compose.yml down -v

# Rebuild and restart a single service without touching the rest
docker compose -f srcs/docker-compose.yml build monitoring
docker compose -f srcs/docker-compose.yml up -d --no-deps monitoring
```

> Tip: since `-f srcs/docker-compose.yml` gets tedious, consider `alias dcomp='docker compose -f srcs/docker-compose.yml'` in your zsh rc for interactive work.

---

## Managing containers and volumes

### Container lifecycle

```zsh
# Show running containers
docker compose -f srcs/docker-compose.yml ps

# Show all containers including stopped ones
docker compose -f srcs/docker-compose.yml ps -a

# Open a shell inside a running container
docker compose -f srcs/docker-compose.yml exec nginx sh
docker compose -f srcs/docker-compose.yml exec wordpress sh
docker compose -f srcs/docker-compose.yml exec mariadb sh
docker compose -f srcs/docker-compose.yml exec monitoring sh
docker compose -f srcs/docker-compose.yml exec cadvisor sh
```

### Logs

```zsh
# Stream all logs
docker compose -f srcs/docker-compose.yml logs -f

# One service with last 50 lines
docker compose -f srcs/docker-compose.yml logs -f --tail=50 monitoring
```

### Images

```zsh
# List project images (compose project name is "inception")
docker images | grep inception

# Force a full rebuild with no cache
docker compose -f srcs/docker-compose.yml build --no-cache

# Remove dangling images
docker image prune -f
```

### Volumes

```zsh
# List project volumes
docker volume ls | grep inception

# Inspect a volume
docker volume inspect inception_db_data
docker volume inspect inception_wp_data
docker volume inspect inception_redis_data
docker volume inspect inception_prometheus_data
docker volume inspect inception_grafana_data

# Delete a specific volume (the container using it must be stopped first)
docker compose -f srcs/docker-compose.yml stop monitoring
docker volume rm inception_prometheus_data
```

### Network

```zsh
# Inspect the limbo network
docker network inspect inception_limbo

# List all containers attached to it
docker network inspect inception_limbo \
    --format '{{range .Containers}}{{.Name}} {{end}}'
```

Expected attached containers: nine, matching the services.

---

## Where data is stored and how it persists

The project uses five **named Docker volumes** plus one **read-only bind mount**.

### `db_data` — MariaDB data directory

| Property      | Value                                                                                                        |
| ------------- | ------------------------------------------------------------------------------------------------------------ |
| Mounted at    | `/var/lib/mariadb` (mariadb)                                                                                 |
| Initialised by| `srcs/mariadb/entrypoint.sh`, on first start only, when `/var/lib/mariadb/mysql` does not yet exist           |

The bootstrap sequence runs `mysql_install_db`, starts a temporary `mariadbd --skip-networking` to set the root password and create the WordPress database and user from secrets, then shuts it down cleanly before handing off to the real `mariadbd` process (so PID 1 is a long-lived daemon, never `tail -f` or any other forbidden pattern).

### `wp_data` — WordPress web root

| Property      | Value                                                                                                                         |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Mounted at    | `/var/www/html` read-write (wordpress, ftp) · `/var/www/html` read-only (nginx)                                                |
| Initialised by| `srcs/wordpress/entrypoint.sh` — writes `wp-config.php`, runs `wp core install`, creates both users, enables Redis object-cache plugin |

`nginx` mounts it read-only to serve static assets directly without hitting PHP-FPM. `ftp` mounts it read-write, so files uploaded via FTP are instantly visible to WordPress.

### `redis_data` — Redis snapshot directory

| Property | Value                                                                             |
| -------- | --------------------------------------------------------------------------------- |
| Mounted at | `/data` (redis)                                                                   |
| Contents | `dump.rdb` RDB snapshot, saved automatically per the `save` schedule in `redis.conf` |

If wiped, Redis starts empty and WordPress regenerates the cache on demand — no permanent data loss.

### `prometheus_data` — Prometheus time-series database

| Property  | Value                                                                                |
| --------- | ------------------------------------------------------------------------------------ |
| Mounted at| `/var/lib/prometheus` (monitoring)                                                   |
| Retention | 15 days (configured via `--storage.tsdb.retention.time=15d` in `supervisord.conf`)   |

Retains scraped metrics across container restarts so historical graphs remain available in Grafana.

### `grafana_data` — Grafana state

| Property | Value                                                                      |
| -------- | -------------------------------------------------------------------------- |
| Mounted at | `/var/lib/grafana` (monitoring)                                            |
| Contents | User accounts, manually created dashboards, alert rules, plugin data       |

The provisioned Docker-containers dashboard and Prometheus datasource are baked into the image at build time and are always present regardless of this volume. This volume only needs to persist things added manually through the Grafana UI (user accounts, new dashboards, alerts).

### `/var/run/docker.sock` — Docker Engine API (read-only bind mount)

| Property   | Value                                                                |
| ---------- | -------------------------------------------------------------------- |
| Mounted at | `/var/run/docker.sock:ro` (cadvisor)                                 |
| Purpose    | Lets the custom Python exporter query `/containers/json` and `/containers/<id>/stats` over the local Docker Engine API |

Read-only is deliberate: the exporter only reads, never writes.

### Persistence behaviour summary

| Action                     | `db_data` | `wp_data` | `redis_data` | `prometheus_data` | `grafana_data` |
| -------------------------- | :-------: | :-------: | :----------: | :---------------: | :------------: |
| `make down`                |     ✅    |     ✅    |      ✅      |         ✅        |       ✅       |
| `make fclean` / `make re`  |     ❌    |     ❌    |      ❌      |         ❌        |       ❌       |
| `docker compose build`     |     ✅    |     ✅    |      ✅      |         ✅        |       ✅       |
| Container crash / restart  |     ✅    |     ✅    |      ✅      |         ✅        |       ✅       |
| Host reboot                |     ✅    |     ✅    |      ✅      |         ✅        |       ✅       |

---

## Network architecture

All nine containers share the single `limbo` bridge network, declared in `srcs/docker-compose.yml`:

```yaml
networks:
  limbo:
    driver: bridge
```

Docker Compose names the actual network `inception_limbo` (project prefix + network name) and provides automatic DNS resolution between all containers by service name — so `wordpress` can reach MariaDB via the hostname `mariadb`, Prometheus can reach the exporter via `cadvisor`, and so on.

The `monitoring` container additionally declares `extra_hosts: host-gateway:host-gateway` so it can reach the Docker daemon's metrics endpoint on the host machine without switching to host-network mode. `cadvisor` reaches the Docker Engine API via a read-only bind-mount of `/var/run/docker.sock` — again, no host-network mode required. `network: host`, `--link`, and `links:` are never used; they are forbidden by the subject.

### Ports published to the host

| Port         | Service    | Protocol                                |
| ------------ | ---------- | --------------------------------------- |
| 80           | nginx      | HTTP (301 redirect to 443)              |
| 443          | nginx      | HTTPS / TLS 1.3                         |
| 8080         | static     | HTTP                                    |
| 8081         | adminer    | HTTP (private IP ranges only)           |
| 21           | ftp        | FTP control                             |
| 21100–21110  | ftp        | FTP passive data                        |
| 3000         | monitoring | Grafana UI                              |
| 9090         | monitoring | Prometheus UI                           |

MariaDB (3306), Redis (6379), and cAdvisor (8080 inside `limbo`) are **not** published — they are reachable only within `limbo`.

---

## Monitoring architecture

The `monitoring` container runs two processes managed by **supervisord**:

- **Prometheus** — scrapes metrics every 15 seconds from three targets:
  - `host-gateway:9323` — the Docker daemon's built-in metrics endpoint, exposing engine-level counters (containers running, image count, etc.)
  - `localhost:9090` — Prometheus itself (self-monitoring)
  - `cadvisor:8080` — the custom Python exporter, exposing per-container CPU, memory, network, and block-I/O counters with `{name="..."}` labels
- **Grafana** — provisioned at startup with Prometheus as the default datasource and a Docker-containers dashboard pre-loaded from `grafana/dashboards/docker.json`. The dashboard uses metrics from **both** the Docker daemon (`engine_daemon_*`) and the custom exporter (`container_cpu_usage_seconds_total`, `container_memory_usage_bytes`, `container_network_*`, `container_blkio_*`).

Both processes log to stdout/stderr, which `docker compose -f srcs/docker-compose.yml logs -f monitoring` captures normally.

To verify Prometheus is successfully scraping all three targets:

```zsh
curl -s http://jaehylee.42.fr:9090/api/v1/targets | python3 -m json.tool | grep -E '"health"|"job"'
```

All three targets should report `"health": "up"`.

---

## cAdvisor — the custom container-metrics exporter

The `cadvisor` service is a deliberately minimal, from-scratch Prometheus exporter written in Python. It is **not** Google's cAdvisor binary — it is a ~100-line single-file exporter that demonstrates the Docker Engine API directly.

| Property           | Value                                                                        |
| ------------------ | ---------------------------------------------------------------------------- |
| Base image         | `alpine:3.22.3`                                                              |
| Runtime            | Python 3 (`python3` apk package only; no third-party libraries)              |
| Docker socket      | `/var/run/docker.sock` mounted read-only                                     |
| Listen port        | `8080` (inside `limbo` only, not published)                                  |
| Metrics endpoint   | `GET /metrics` in Prometheus text format                                     |
| Scrape interval    | 5 seconds (background collector thread)                                      |

Exposed metric families (all counters or gauges with `{name="<container_name>"}` labels):

- `container_cpu_usage_seconds_total` (counter)
- `container_memory_usage_bytes` (gauge)
- `container_network_receive_bytes_total` / `container_network_transmit_bytes_total` (counters)
- `container_blkio_device_usage_total{op="Read"|"Write"}` (counters)

The exporter reads `/containers/json` to enumerate running containers, then `/containers/<id>/stats?stream=false&one-shot=true` for each to collect a point-in-time stats snapshot, which it formats as Prometheus text. A single background collector thread refreshes an in-memory cache; HTTP handlers serve the cache without touching the Docker socket per request, so scrape latency stays low and constant.

To test manually:

```zsh
docker compose -f srcs/docker-compose.yml exec monitoring \
    wget -qO- http://cadvisor:8080/metrics | head -30
```

---

## Static site build pipeline

The `static` service uses a **two-stage Docker build** with real barbell (BQN) — not a shell-based imitation.

**Stage 1 (builder):** `alpine:3.22.3` + `git`, `clang`, `make`, `libffi-dev`, `libstdc++-dev`.

1. Clones `github.com/dzaima/CBQN` (reference BQN runtime in C++).
2. Compiles CBQN from source (`CXX=clang++ make`).
3. Copies `site/` and `template.bqn` into the builder.
4. Runs:

   ```zsh
   ./BQN /build/site/template.bqn /build/site/template.html > /build/site/index.html
   ```

   This is the real barbell template engine: `template.bqn` reads `template.html`, replaces every `|variable|` placeholder with the contents of the matching `variable.bar` file in the same directory, and writes the fully-substituted HTML to stdout.

**Stage 2 (server):** `alpine:3.22.3` + `nginx` only. Copies only the compiled `index.html` and `style.css` from the builder. The final image carries no BQN runtime, no C++ compiler, no template sources — just nginx and the two static files.

To update the site content, edit files under `srcs/static/site/` (the `.bar` fragments or `template.html`) and rebuild only the `static` service:

```zsh
docker compose -f srcs/docker-compose.yml build static
docker compose -f srcs/docker-compose.yml up -d --no-deps static
```

---

## TLS certificate

The `nginx` image generates a self-signed RSA-4096 certificate at build time via `openssl req -x509`:

```
/etc/nginx/ssl/server.crt
/etc/nginx/ssl/server.key
```

The CN is set to `jaehylee.42.fr`, validity is 365 days. `nginx.conf` enforces `ssl_protocols TLSv1.3` only (the subject allows 1.2 or 1.3; this project takes the stricter option) and emits an HSTS header with `max-age=63072000` (two years).

For production, mount real certificates via a Docker volume or bind mount and update `nginx.conf` to point to them. For local development and 42 evaluation, the self-signed certificate is sufficient — browsers will prompt the first time and remember your acceptance.

---

## Subject compliance checklist (for evaluation)

A quick reference of the rules that drove design decisions:

- ✅ All images built from `alpine:3.22.3` (penultimate stable Alpine); no `:latest` tag anywhere.
- ✅ Every service has its own Dockerfile; no ready-made service images pulled (Alpine base only).
- ✅ `nginx` is the sole entrypoint, on port 443, TLS 1.3 only.
- ✅ `wordpress` contains php-fpm, no nginx. `mariadb` contains only mariadb, no nginx.
- ✅ Two WordPress users; administrator username does not contain `admin`/`Admin`/`administrator`/`Administrator`.
- ✅ Named volumes for the WordPress database and website files (plus three more for redis/prometheus/grafana).
- ✅ Single custom bridge network (`limbo`), declared explicitly in `docker-compose.yml`; no `network: host`, `--link`, or `links:`.
- ✅ `restart: unless-stopped` on every service — containers recover automatically from crashes.
- ✅ No `tail -f`, `sleep infinity`, `bash`, or `while true` as PID 1 or anywhere in entrypoints; every container's PID 1 is a real long-running daemon (`mariadbd`, `php-fpm83 -F`, `nginx -g 'daemon off;'`, `redis-server`, `vsftpd`, `supervisord -n`, `python3 exporter.py`).
- ✅ `.env` in `srcs/` holds only non-sensitive configuration; all credentials are Docker Secrets.
- ✅ Secrets live in `secrets/` at repo root and are gitignored.
- ✅ Domain `jaehylee.42.fr` pointing to local IP via `/etc/hosts`.
