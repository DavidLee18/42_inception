# Developer Documentation — Inception

## Prerequisites

Make sure the following are installed before proceeding:

| Tool | Minimum version | Check |
|---|---|---|
| Docker Engine | 24.0 | `docker --version` |
| Docker Compose plugin | 2.20 | `docker compose version` |
| make | any | `make --version` |
| git | any | `git --version` |

Docker must be running (`sudo systemctl start docker` on Linux).

---

## Setting Up the Environment from Scratch

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

### 3. Create `srcs/.env`

All non-sensitive configuration lives here. Docker Compose automatically reads it because it is co-located with `docker-compose.yml`.

```bash
cat > srcs/.env <<'EOF'
DOMAIN_NAME=jaehylee.42.fr
WORDPRESS_DB_HOST=mariadb:3306
DB_HOST=mariadb
DB_PORT=3306
REDIS_HOST=redis
REDIS_PORT=6379
DOCKER_METRICS_HOST=host-gateway:9323
EOF
```

| Variable | Used by | Purpose |
|---|---|---|
| `DOMAIN_NAME` | `ftp` entrypoint, `wordpress` entrypoint | Sets `pasv_address` in vsftpd, `WP_HOME`/`WP_SITEURL` in wp-config |
| `WORDPRESS_DB_HOST` | `wordpress` container | DB host passed as environment variable |
| `DB_HOST` / `DB_PORT` | `wordpress` entrypoint | Health-check `nc -z` before WP install |
| `REDIS_HOST` / `REDIS_PORT` | `wordpress` entrypoint | Written into wp-config.php |
| `DOCKER_METRICS_HOST` | `monitoring` entrypoint | Substituted into `prometheus.yml` at startup |

### 4. Create the secrets

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

### 5. Add the domain to your hosts file

```bash
echo "127.0.0.1  jaehylee.42.fr" | sudo tee -a /etc/hosts
```

### 6. Verify configuration files are present

```
.
├── Makefile
├── secrets/                         # 13 files as created above
└── srcs/
    ├── .env                         # non-sensitive config
    ├── docker-compose.yml
    ├── nginx/
    │   ├── Dockerfile
    │   └── nginx.conf
    ├── mariadb/
    │   ├── Dockerfile
    │   ├── my.cnf
    │   └── entrypoint.sh
    ├── wordpress/
    │   ├── Dockerfile
    │   ├── php-fpm.conf
    │   └── entrypoint.sh
    ├── redis/
    │   ├── Dockerfile
    │   ├── redis.conf
    │   └── entrypoint.sh
    ├── ftp/
    │   ├── Dockerfile
    │   ├── vsftpd.conf
    │   └── entrypoint.sh
    ├── static/
    │   ├── Dockerfile
    │   ├── nginx.conf
    │   ├── build.sh
    │   └── site/
    │       ├── template.html
    │       ├── index.md
    │       ├── style.css
    │       └── *.bar
    ├── adminer/
    │   ├── Dockerfile
    │   ├── nginx.conf
    │   └── php-fpm.conf
    └── monitoring/
        ├── Dockerfile
        ├── entrypoint.sh
        ├── supervisord.conf
        ├── prometheus.yml
        └── grafana/
            ├── provisioning/
            │   ├── datasources/prometheus.yml
            │   └── dashboards/dashboard.yml
            └── dashboards/
                ├── docker.json
                └── prometheus.json
```

---

## Building and Launching the Project

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
	docker compose -f srcs/docker-compose.yml up -d --build

down:
	docker compose -f srcs/docker-compose.yml down

fclean: down
	docker compose -f srcs/docker-compose.yml down --volumes --rmi all --remove-orphans
	docker image prune -af

re: fclean all

.PHONY: all down fclean re
```

---

## Architecture

### Network

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

### Volume Map

| Volume | Mounted at | Service(s) | Contents |
|---|---|---|---|
| `db_data` | `/var/lib/mariadb` | mariadb | MariaDB data directory |
| `wp_data` | `/var/www/html` | wordpress (rw), nginx (ro), ftp (rw) | WordPress web root |
| `redis_data` | `/data` | redis | `dump.rdb` RDB snapshot |
| `prometheus_data` | `/var/lib/prometheus` | monitoring | TSDB, 15-day retention |
| `grafana_data` | `/var/lib/grafana` | monitoring | User accounts, manual dashboards, alert rules |

### Persistence Behaviour

| Action | `db_data` | `wp_data` | `redis_data` | `prometheus_data` | `grafana_data` |
|---|---|---|---|---|---|
| `make down` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `make fclean` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `docker compose build` | ✅ | ✅ | ✅ | ✅ | ✅ |
| Container crash / restart | ✅ | ✅ | ✅ | ✅ | ✅ |
| Host reboot | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Environment Variables and Secrets

### `.env` file (`srcs/.env`)

Docker Compose automatically reads `srcs/.env` because it is co-located with `docker-compose.yml`. Variables defined here are interpolated into `docker-compose.yml` at runtime using `${VARIABLE}` syntax.

```
DOMAIN_NAME=jaehylee.42.fr
WORDPRESS_DB_HOST=mariadb:3306
DB_HOST=mariadb
DB_PORT=3306
REDIS_HOST=redis
REDIS_PORT=6379
DOCKER_METRICS_HOST=host-gateway:9323
```

Config files that do not natively support environment variables (`vsftpd.conf`, `prometheus.yml`) are patched at container startup by their respective entrypoint scripts using `sed`.

### Docker Secrets

Credentials are never passed as plain environment variable values. Each secret is a file mounted at `/run/secrets/<name>` inside the container. Entrypoint scripts read them with a `read_secret()` helper:

```sh
read_secret() {
    cat "$1"
}
```

The 13 secrets in use:

| Secret file | Consumer |
|---|---|
| `db_root_password.txt` | mariadb |
| `db_name.txt` | mariadb, wordpress |
| `db_user.txt` | mariadb, wordpress |
| `db_password.txt` | mariadb, wordpress |
| `redis_password.txt` | redis, wordpress |
| `wp_admin_user.txt` | wordpress |
| `wp_admin_password.txt` | wordpress |
| `wp_admin_email.txt` | wordpress |
| `wp_user.txt` | wordpress |
| `wp_user_password.txt` | wordpress |
| `wp_user_email.txt` | wordpress |
| `ftp_user.txt` | ftp |
| `ftp_password.txt` | ftp |

---

## Service Details

### nginx

- Listens on 80 (redirect to 443) and 443 (TLS 1.3 only)
- Proxies PHP requests to `wordpress:9000` via FastCGI
- Serves static WordPress assets directly from the `wp_data` volume (read-only mount)
- Self-signed certificate generated at build time with CN=`jaehylee.42.fr`
- HSTS header with `max-age=63072000` (2 years) enforced on all responses

### wordpress

- PHP-FPM 8.3 listening on `0.0.0.0:9000`
- WP-CLI used in entrypoint to install WordPress core, create two users, and enable the Redis object cache plugin — fully automated, no browser interaction required
- `wp-config.php` written at first start using secrets and `.env` values
- Admin username validated at startup — must not contain `admin` (case-insensitive)

### mariadb

- Custom Alpine 3.22.3 build (not official image)
- Initialised with `mysql_install_db` on first start
- Binds to `0.0.0.0` within `limbo` (not exposed to host)

### redis

- Object cache for WordPress using the `redis-cache` plugin
- `allkeys-lru` eviction policy with `maxmemory 128mb` — ideal for a WordPress cache where keys carry no TTLs
- RDB snapshot persistence to `redis_data` volume
- Dangerous commands (`FLUSHALL`, `DEBUG`, `SHUTDOWN`) renamed to empty strings

### ftp

- vsftpd in passive mode on ports `21100–21110`
- FTP user home directory is `/var/www/html` (WordPress web root)
- Chroot jail enforced via `chroot_local_user=YES` — the user cannot navigate above the web root
- `pasv_address` is substituted from `DOMAIN_NAME` at runtime by `entrypoint.sh`

### static

Two-stage build:

1. **Builder stage** (Alpine 3.22.3 + pandoc + bash): runs `build.sh`, which converts `site/index.md` to an HTML fragment via pandoc and performs barbell-style `|variable|` substitution via `sed` against `site/template.html`.
2. **Final stage** (Alpine 3.22.3 + nginx): contains only the compiled `index.html` and `style.css`.

To update site content, edit files under `static/site/` and rebuild:

```bash
docker compose build static && docker compose up -d --no-deps static
```

### adminer

- Single-file PHP database UI served by nginx + php-fpm
- Restricted to private IP ranges (10.x, 172.16–31.x, 192.168.x) via nginx `allow`/`deny`

### monitoring

- Single container running two processes managed by **supervisord** (PID 1):
  - **Prometheus** — scrapes metrics every 15 seconds; targets substituted from `DOCKER_METRICS_HOST` at startup by `entrypoint.sh`
  - **Grafana** — provisioned at startup with Prometheus as default datasource and two dashboards pre-loaded from JSON files

Prometheus targets:

| Job | Target | Metrics provided |
|---|---|---|
| `docker` | `host-gateway:9323` | Per-container CPU, memory, network, block I/O |
| `prometheus` | `localhost:9090` | Prometheus self-monitoring |

Grafana dashboards provisioned automatically:

| Dashboard | Source file | Content |
|---|---|---|
| Docker Containers | `grafana/dashboards/docker.json` | Container resource usage |
| Prometheus 2.0 Overview | `grafana/dashboards/prometheus.json` | Scrape health, TSDB stats |

---

## TLS Certificate

The nginx image generates a self-signed certificate at build time:

```
/etc/nginx/ssl/server.crt
/etc/nginx/ssl/server.key
```

The CN is set to `jaehylee.42.fr`. For production, mount real certificates via a volume and update `nginx.conf` to point to them.

---

## Useful Commands

### Container management

```bash
# Check status of all containers
docker compose ps

# Follow logs for a specific service
docker compose logs -f <service>

# Restart a single service without rebuilding
docker compose restart <service>

# Rebuild and restart a single service
docker compose build <service> && docker compose up -d --no-deps <service>

# Open a shell inside a container
docker compose exec <service> sh
```

### WordPress

```bash
# List WordPress users
docker compose exec wordpress wp user list --allow-root --path=/var/www/html

# Check Redis object cache status
docker compose exec wordpress wp redis status --allow-root --path=/var/www/html

# Flush the Redis cache
docker compose exec wordpress wp redis flush --allow-root --path=/var/www/html
```

### MariaDB

```bash
# Check database is alive
docker compose exec mariadb mysqladmin \
    --socket=/run/mysqld/mysqld.sock ping

# Open MariaDB CLI as root
docker compose exec mariadb mariadb \
    --socket=/run/mysqld/mysqld.sock -u root
```

### Redis

```bash
# Ping Redis
docker compose exec redis redis-cli \
    -a "$(cat secrets/redis_password.txt)" ping

# Check memory usage
docker compose exec redis redis-cli \
    -a "$(cat secrets/redis_password.txt)" info memory
```

### Prometheus

```bash
# Verify scrape targets are healthy
curl -s http://jaehylee.42.fr:9090/api/v1/targets \
    | python3 -m json.tool | grep health
```

### Volumes

```bash
# List all named volumes
docker volume ls

# Inspect a volume
docker volume inspect inception_wp_data

# Back up the MariaDB volume
docker run --rm \
    -v inception_db_data:/data \
    -v $(pwd):/backup \
    alpine tar czf /backup/db_data_backup.tar.gz /data
```
