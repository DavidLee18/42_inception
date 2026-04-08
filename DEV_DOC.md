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

### 2. Create the secrets

The stack requires thirteen secret files. Create them manually — never commit them to Git.

```bash
mkdir -p secrets
echo "strongrootpassword"       > secrets/db_root_password.txt
echo "wordpress"                > secrets/db_name.txt
echo "wpuser"                   > secrets/db_user.txt
echo "strongwppassword"         > secrets/db_password.txt
echo "strongredispassword"      > secrets/redis_password.txt
echo "jaehylee"                 > secrets/wp_admin_user.txt
echo "strongadminpassword"      > secrets/wp_admin_password.txt
echo "jaehylee@42gyeongsan.kr"  > secrets/wp_admin_email.txt
echo "subscriber1"              > secrets/wp_user.txt
echo "stronguserpassword"       > secrets/wp_user_password.txt
echo "user@42seoul.kr"          > secrets/wp_user_email.txt
echo "ftpuser"                  > secrets/ftp_user.txt
echo "strongftppassword"        > secrets/ftp_password.txt
```

> **Constraint:** the WordPress admin username must not contain `admin` (case-insensitive) in any form. The `wordpress/entrypoint.sh` enforces this at startup and will exit with an error if the constraint is violated.

Verify `secrets/` is gitignored:

```bash
grep secrets .gitignore   # must return "secrets/"
```

### 3. Add the domain to your hosts file (local development only)

```bash
echo "127.0.0.1  jaehylee.42.fr" | sudo tee -a /etc/hosts
```

### 4. Verify the configuration files are present

```
.
├── docker-compose.yml
├── Makefile
├── secrets/                    # 13 files as created above
├── nginx/
│   ├── Dockerfile              # Alpine 3.22.3, openssl, nginx
│   └── nginx.conf              # TLS 1.3, FastCGI to wordpress:9000
├── mariadb/
│   ├── Dockerfile              # Alpine 3.22.3, mariadb
│   ├── my.cnf                  # utf8mb4, bind 0.0.0.0
│   └── entrypoint.sh           # reads secrets, runs mysql_install_db once
├── wordpress/
│   ├── Dockerfile              # Alpine 3.22.3, php83-fpm, wp-cli
│   ├── php-fpm.conf            # listen 0.0.0.0:9000
│   └── entrypoint.sh           # reads secrets, writes wp-config.php, wp core install
├── redis/
│   ├── Dockerfile              # Alpine 3.22.3, redis
│   ├── redis.conf              # allkeys-lru, maxmemory 128mb, dangerous cmds disabled
│   └── entrypoint.sh           # reads secret, passes --requirepass
├── ftp/
│   ├── Dockerfile              # Alpine 3.22.3, vsftpd
│   ├── vsftpd.conf             # passive mode, ports 21100-21110, chroot
│   └── entrypoint.sh           # reads secrets, creates FTP user
├── static/
│   ├── Dockerfile              # multi-stage: Alpine builder + Alpine nginx
│   ├── nginx.conf              # listens on 8080
│   ├── build.sh                # barbell-style |variable| substitution via sed + pandoc
│   └── site/
│       ├── template.html
│       ├── index.md
│       ├── style.css
│       └── *.bar
└── adminer/
    ├── Dockerfile              # Alpine 3.22.3, php83-fpm, nginx, adminer single file
    ├── nginx.conf              # listens on 8081, IP allowlist for private ranges
    └── php-fpm.conf            # listen 127.0.0.1:9001
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

# Start without rebuilding (faster if nothing changed)
docker compose up -d

# Stop containers
docker compose down

# Stop containers and destroy all volumes
docker compose down -v

# Rebuild and restart a single service only
docker compose build wordpress
docker compose up -d --no-deps wordpress
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
# Show running containers and their status
docker compose ps

# Show all containers including stopped ones
docker compose ps -a

# Restart a single service
docker compose restart <service>

# Open a shell inside a running container
docker compose exec nginx sh
docker compose exec wordpress sh
docker compose exec mariadb sh
docker compose exec redis sh
docker compose exec ftp sh
docker compose exec adminer sh
```

### Logs

```bash
# Stream logs from all services
docker compose logs -f

# Stream logs from a specific service with last 50 lines
docker compose logs -f --tail=50 wordpress
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

# Inspect a volume (shows host mount point)
docker volume inspect inception_db_data
docker volume inspect inception_wp_data
docker volume inspect inception_redis_data

# Delete a specific volume (container must be stopped first)
docker volume rm inception_db_data
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

The project uses three **named Docker volumes** to persist state across container restarts and rebuilds.

### `db_data` — MariaDB data directory

| Property | Value |
|---|---|
| Mounted at (container) | `/var/lib/mysql` |
| Contents | All database files: tables, indexes, transaction logs |
| Initialised by | `mariadb/entrypoint.sh` on first start only, when `/var/lib/mysql/mysql` does not yet exist |

The bootstrap sequence runs `mysql_install_db` once, then starts a temporary `mysqld` with `--skip-networking` to safely set the root password and create the WordPress database and user, then shuts it down before handing off to the real `mysqld` process.

### `wp_data` — WordPress web root

| Property | Value |
|---|---|
| Mounted at (wordpress) | `/var/www/html` (read-write) |
| Mounted at (nginx) | `/var/www/html` (read-only) |
| Mounted at (ftp) | `/var/www/html` (read-write) |
| Contents | WordPress core files, `wp-config.php`, plugins, themes, uploaded media |
| Initialised by | `wordpress/entrypoint.sh` on first start — writes `wp-config.php` from secrets, runs `wp core install`, creates both users, installs and enables the Redis cache plugin |

nginx mounts this volume read-only so it can serve static assets directly without forwarding every request to PHP-FPM. The FTP container mounts it read-write so files uploaded via FTP are immediately visible to WordPress.

### `redis_data` — Redis snapshot directory

| Property | Value |
|---|---|
| Mounted at (container) | `/data` |
| Contents | `dump.rdb` — RDB snapshot of the object cache |
| Initialised by | Redis on first write |

RDB persistence means the object cache survives container restarts without a cold-start performance hit. If the volume is wiped, Redis starts empty and WordPress regenerates the cache on demand — no data loss occurs.

### Persistence behaviour summary

| Action | `db_data` | `wp_data` | `redis_data` |
|---|---|---|---|
| `make down` | ✅ Preserved | ✅ Preserved | ✅ Preserved |
| `make fclean` | ❌ Deleted | ❌ Deleted | ❌ Deleted |
| `docker compose build` | ✅ Preserved | ✅ Preserved | ✅ Preserved |
| Container crash / restart | ✅ Preserved | ✅ Preserved | ✅ Preserved |
| Host reboot | ✅ Preserved | ✅ Preserved | ✅ Preserved |

---

## Network architecture

All seven containers share the single `limbo` bridge network declared in `docker-compose.yml`:

```yaml
networks:
  limbo:
```

No driver is specified — Docker defaults to `bridge` on single-host deployments. Docker Compose automatically creates the network with the name `inception_limbo` and provides DNS resolution so every container can reach any other by its service name.

Ports reachable from the host:

| Port | Service | Protocol |
|---|---|---|
| 80 | nginx | HTTP (redirects to 443) |
| 443 | nginx | HTTPS / TLS 1.3 |
| 8080 | static | HTTP |
| 8081 | adminer | HTTP |
| 21 | ftp | FTP control |
| 21100–21110 | ftp | FTP passive data |

MariaDB (3306) and Redis (6379) are intentionally not published — they are reachable only within the `limbo` network.

---

## TLS certificate

The nginx image generates a self-signed certificate at build time:

```
/etc/nginx/ssl/server.crt
/etc/nginx/ssl/server.key
```

The CN is set to `jaehylee.42.fr`. This is sufficient for local development and 42 evaluation. For production, mount real certificates via a volume and update `nginx.conf` to point to them.

---

## Static site build pipeline

The `static` service uses a two-stage Docker build. The builder stage (Alpine 3.22.3 + pandoc + bash) runs `build.sh`, which:

1. Converts `site/index.md` to an HTML fragment via pandoc, saving it as `content.bar`.
2. Iterates over all `*.bar` files and substitutes every `|variable|` placeholder in `site/template.html` using `sed` — faithfully replicating the mechanic of the barbell BQN template engine.
3. Copies the resulting `index.html` and `style.css` to the output directory.

The final image contains only Alpine 3.22.3 + nginx + the compiled HTML and CSS. To update the site content, edit files under `static/site/` and rebuild:

```bash
docker compose build static && docker compose up -d --no-deps static
```
