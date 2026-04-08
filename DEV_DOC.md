# Developer Documentation

## Prerequisites

Make sure the following are installed before proceeding:

| Tool | Minimum version | Check |
|---|---|---|
| Docker Engine | 24.0 | `docker --version` |
| Docker Compose plugin | 2.20 | `docker compose version` |
| make | any | `make --version` |
| git | any | `git --version` |

Docker must be running (`sudo systemctl start docker` on Linux, or open Docker Desktop on macOS/Windows).

---

## Setting up the environment from scratch

### 1. Clone the repository

```bash
git clone https://github.com/DavidLee18/42_inception.git
cd 42_inception
```

### 2. Enable Docker daemon metrics on the host

The `monitoring` container scrapes per-container metrics from the Docker daemon's built-in Prometheus endpoint. This must be enabled on the host before starting the stack.

Add or merge the following into `/etc/docker/daemon.json`:

```json
{
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
```

Then restart Docker:

```bash
sudo systemctl restart docker
```

Verify it works:

```bash
curl -s http://localhost:9323/metrics | head -5
```

### 3. Create the secrets

The stack requires thirteen secret files. Create them manually — never commit them to Git.

```bash
mkdir -p secrets
echo "strongrootpassword"   > secrets/db_root_password.txt
echo "wordpress"            > secrets/db_name.txt
echo "wpuser"               > secrets/db_user.txt
echo "strongwppassword"     > secrets/db_password.txt
echo "strongredispassword"  > secrets/redis_password.txt
echo "jaehylee"             > secrets/wp_admin_user.txt
echo "strongadminpassword"  > secrets/wp_admin_password.txt
echo "jaehylee@42seoul.kr"  > secrets/wp_admin_email.txt
echo "subscriber1"          > secrets/wp_user.txt
echo "stronguserpassword"   > secrets/wp_user_password.txt
echo "user@42seoul.kr"      > secrets/wp_user_email.txt
echo "ftpuser"              > secrets/ftp_user.txt
echo "strongftppassword"    > secrets/ftp_password.txt
```

> **Constraint:** the WordPress admin username must not contain `admin` (case-insensitive). The `wordpress/entrypoint.sh` enforces this at startup and exits with an error if violated.

Verify `secrets/` is gitignored:

```bash
grep secrets .gitignore   # must return "secrets/"
```

### 4. Add the domain to your hosts file (local development only)

```bash
echo "127.0.0.1  jaehylee.42.fr" | sudo tee -a /etc/hosts
```

### 5. Verify the configuration files are present

```
.
├── docker-compose.yml
├── Makefile
├── secrets/                         # 13 files as created above
├── nginx/
│   ├── Dockerfile                   # Alpine 3.22.3, openssl, nginx
│   └── nginx.conf                   # TLS 1.3, FastCGI to wordpress:9000
├── mariadb/
│   ├── Dockerfile                   # Alpine 3.22.3, mariadb
│   ├── my.cnf                       # utf8mb4, bind 0.0.0.0
│   └── entrypoint.sh                # reads secrets, runs mysql_install_db once
├── wordpress/
│   ├── Dockerfile                   # Alpine 3.22.3, php83-fpm, wp-cli
│   ├── php-fpm.conf                 # listen 0.0.0.0:9000
│   └── entrypoint.sh                # reads secrets, writes wp-config.php, wp core install
├── redis/
│   ├── Dockerfile                   # Alpine 3.22.3, redis
│   ├── redis.conf                   # allkeys-lru, maxmemory 128mb, dangerous cmds disabled
│   └── entrypoint.sh                # reads secret, passes --requirepass
├── ftp/
│   ├── Dockerfile                   # Alpine 3.22.3, vsftpd
│   ├── vsftpd.conf                  # passive mode 21100-21110, chroot
│   └── entrypoint.sh                # reads secrets, creates FTP user
├── static/
│   ├── Dockerfile                   # multi-stage: Alpine 3.22.3 builder + Alpine 3.22.3 nginx
│   ├── nginx.conf                   # listens on 8080
│   ├── build.sh                     # barbell-style |variable| substitution via sed + pandoc
│   └── site/
│       ├── template.html
│       ├── index.md
│       ├── style.css
│       └── *.bar
├── adminer/
│   ├── Dockerfile                   # Alpine 3.22.3, php83-fpm, nginx, adminer single file
│   ├── nginx.conf                   # listens on 8081, IP allowlist for private ranges
│   └── php-fpm.conf                 # listen 127.0.0.1:9001
└── monitoring/
    ├── Dockerfile                   # Alpine 3.22.3, prometheus, grafana, supervisor
    ├── supervisord.conf             # manages prometheus + grafana as child processes
    ├── prometheus.yml               # scrapes host:9323 (Docker daemon) and localhost:9090
    └── grafana/
        ├── provisioning/
        │   ├── datasources/
        │   │   └── prometheus.yml   # auto-wires Prometheus as default datasource
        │   └── dashboards/
        │       └── dashboard.yml    # tells Grafana where to load dashboard JSON from
        └── dashboards/
            docker.json              # pre-built Docker container metrics dashboard
```

---

## Building and launching the project

### Using the Makefile (recommended)

```bash
# Build all images and start all containers
make

# Stop all containers (data preserved)
make down

# Stop all containers and delete all volumes and images
make fclean

# Full rebuild from scratch
make re
```

### Using Docker Compose directly

```bash
# Build images and start in detached mode
docker compose up -d --build

# Start without rebuilding
docker compose up -d

# Stop containers
docker compose down

# Stop containers and destroy all volumes
docker compose down -v

# Rebuild and restart a single service
docker compose build monitoring
docker compose up -d --no-deps monitoring
```

### Makefile reference

```makefile
NAME = inception

all: up

up:
	docker compose -f docker-compose.yml up -d --build

down:
	docker compose -f docker-compose.yml down

fclean: down
	docker compose -f docker-compose.yml down -v
	docker image prune -af

re: fclean all

.PHONY: all up down fclean re
```

---

## Managing containers and volumes

### Container lifecycle

```bash
# Show running containers
docker compose ps

# Show all containers including stopped ones
docker compose ps -a

# Open a shell inside a running container
docker compose exec nginx sh
docker compose exec wordpress sh
docker compose exec mariadb sh
docker compose exec monitoring sh
```

### Logs

```bash
# Stream all logs
docker compose logs -f

# One service with last 50 lines
docker compose logs -f --tail=50 monitoring
```

### Images

```bash
# List project images
docker images | grep inception

# Force full rebuild without cache
docker compose build --no-cache

# Remove dangling images
docker image prune -f
```

### Volumes

```bash
# List project volumes
docker volume ls | grep inception

# Inspect a volume
docker volume inspect inception_db_data
docker volume inspect inception_wp_data
docker volume inspect inception_redis_data
docker volume inspect inception_prometheus_data
docker volume inspect inception_grafana_data

# Delete a specific volume (container must be stopped first)
docker volume rm inception_prometheus_data
```

### Network

```bash
# Inspect the limbo network
docker network inspect inception_limbo

# List all containers attached to it
docker network inspect inception_limbo \
    --format '{{range .Containers}}{{.Name}} {{end}}'
```

---

## Where data is stored and how it persists

The project uses five **named Docker volumes**.

### `db_data` — MariaDB data directory

| Property | Value |
|---|---|
| Mounted at | `/var/lib/mysql` (mariadb) |
| Initialised by | `mariadb/entrypoint.sh` on first start only, when `/var/lib/mysql/mysql` does not yet exist |

The bootstrap sequence runs `mysql_install_db`, then starts a temporary `mysqld --skip-networking` to set the root password and create the WordPress database and user, then shuts it down before handing off to the real process.

### `wp_data` — WordPress web root

| Property | Value |
|---|---|
| Mounted at | `/var/www/html` read-write (wordpress, ftp) · `/var/www/html` read-only (nginx) |
| Initialised by | `wordpress/entrypoint.sh` — writes `wp-config.php`, runs `wp core install`, creates both users, enables Redis cache plugin |

nginx mounts it read-only to serve static assets without hitting PHP-FPM. FTP mounts it read-write so uploaded files are immediately visible to WordPress.

### `redis_data` — Redis snapshot directory

| Property | Value |
|---|---|
| Mounted at | `/data` (redis) |
| Contents | `dump.rdb` RDB snapshot, saved automatically per `redis.conf` schedule |

If wiped, Redis starts empty and WordPress regenerates the cache on demand — no permanent data loss.

### `prometheus_data` — Prometheus time-series database

| Property | Value |
|---|---|
| Mounted at | `/var/lib/prometheus` (monitoring) |
| Retention | 15 days (configured via `--storage.tsdb.retention.time`) |

Retains scraped metrics across container restarts so historical graphs remain available in Grafana.

### `grafana_data` — Grafana state

| Property | Value |
|---|---|
| Mounted at | `/var/lib/grafana` (monitoring) |
| Contents | User accounts, manually created dashboards, alert rules, plugin data |

The provisioned Docker dashboard and Prometheus datasource are loaded from files in the image and are always present regardless of this volume. This volume only needs to persist things you add manually through the UI.

### Persistence behaviour summary

| Action | `db_data` | `wp_data` | `redis_data` | `prometheus_data` | `grafana_data` |
|---|---|---|---|---|---|
| `make down` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `make fclean` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `docker compose build` | ✅ | ✅ | ✅ | ✅ | ✅ |
| Container crash / restart | ✅ | ✅ | ✅ | ✅ | ✅ |
| Host reboot | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Network architecture

All eight containers share the single `limbo` bridge network:

```yaml
networks:
  limbo:
```

No `driver` is specified — Docker defaults to `bridge` on single-host deployments. Docker Compose names the network `inception_limbo` and provides automatic DNS resolution between all containers by service name.

The `monitoring` container uses `extra_hosts: host-gateway` to reach the Docker daemon metrics endpoint (`host:9323`) on the host machine without switching to host network mode.

Ports published to the host:

| Port | Service | Protocol |
|---|---|---|
| 80 | nginx | HTTP (redirects to 443) |
| 443 | nginx | HTTPS / TLS 1.3 |
| 8080 | static | HTTP |
| 8081 | adminer | HTTP (private ranges only) |
| 21 | ftp | FTP control |
| 21100–21110 | ftp | FTP passive data |
| 3000 | monitoring | Grafana UI |
| 9090 | monitoring | Prometheus UI |

MariaDB (3306) and Redis (6379) are intentionally not published — they are reachable only within `limbo`.

---

## Monitoring architecture

The `monitoring` container runs two processes managed by **supervisord**:

- **Prometheus** — scrapes metrics every 15 seconds from two targets:
  - `host-gateway:9323` — the Docker daemon's built-in metrics endpoint, exposing per-container CPU, memory, network, and block I/O counters
  - `localhost:9090` — Prometheus itself (self-monitoring)
- **Grafana** — provisioned at startup with Prometheus as the default datasource and a Docker Containers dashboard pre-loaded from `grafana/dashboards/docker.json`

Both processes log to stdout/stderr, which `docker compose logs -f monitoring` captures normally.

To verify Prometheus is successfully scraping:

```bash
curl -s http://jaehylee.42.fr:9090/api/v1/targets | python3 -m json.tool | grep health
```

All targets should report `"health": "up"`.

---

## Static site build pipeline

The `static` service uses a two-stage Docker build. The builder stage (Alpine 3.22.3 + pandoc + bash) runs `build.sh`, which:

1. Converts `site/index.md` to an HTML fragment via pandoc, saving it as `content.bar`.
2. Iterates over all `*.bar` files and substitutes every `|variable|` placeholder in `site/template.html` using `sed`, faithfully replicating the mechanic of the barbell BQN template engine.
3. Copies the resulting `index.html` and `style.css` to the output directory.

The final image contains only Alpine 3.22.3 + nginx + the compiled HTML and CSS. To update the site content, edit files under `static/site/` and rebuild:

```bash
docker compose build static && docker compose up -d --no-deps static
```

---

## TLS certificate

The nginx image generates a self-signed certificate at build time:

```
/etc/nginx/ssl/server.crt
/etc/nginx/ssl/server.key
```

The CN is set to `jaehylee.42.fr`. This is sufficient for local development and 42 evaluation. For production, mount real certificates via a volume and update `nginx.conf` to point to them.
