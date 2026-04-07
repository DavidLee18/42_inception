# Developer Documentation

## Prerequisites

Make sure the following are installed on your machine before proceeding:

| Tool | Minimum version | Check |
|---|---|---|
| Docker Engine | 24.0 | `docker --version` |
| Docker Compose plugin | 2.20 | `docker compose version` |
| make | any | `make --version` |
| git | any | `git --version` |

Docker must be running as a daemon (`sudo systemctl start docker` on Linux, or open Docker Desktop on macOS/Windows).

---

## Setting up the environment from scratch

### 1. Clone the repository

```bash
git clone https://github.com/DavidLee18/42_inception.git
cd 42_inception
```

### 2. Create the secrets

The stack requires four secret files. Create them manually — never commit them to Git.

```bash
mkdir -p secrets
echo "strongrootpassword" > secrets/db_root_password.txt
echo "wordpress"          > secrets/db_name.txt
echo "wpuser"             > secrets/db_user.txt
echo "strongwppassword"   > secrets/db_password.txt
```

Verify the `secrets/` directory is in `.gitignore`:

```bash
grep secrets .gitignore   # should return "secrets/"
```

### 3. Add the domain to your hosts file (local development only)

```bash
echo "127.0.0.1  jaehylee.42.fr" | sudo tee -a /etc/hosts
```

### 4. Review configuration files

Before building, make sure the following files are present and complete:

```
.
├── docker-compose.yml
├── secrets/
│   ├── db_root_password.txt
│   ├── db_name.txt
│   ├── db_user.txt
│   └── db_password.txt
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf
├── mariadb/
│   ├── Dockerfile
│   ├── my.cnf
│   └── entrypoint.sh
└── wordpress/
    ├── Dockerfile
    ├── php-fpm.conf
    └── entrypoint.sh
```

---

## Building and launching the project

### Using the Makefile

```bash
# Build all images and start all containers
make

# Stop all containers (data preserved)
make clean

# Stop all containers and delete all volumes
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

# Stop containers and destroy volumes
docker compose down -v

# Rebuild a single service image
docker compose build wordpress
docker compose up -d --no-deps wordpress
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
docker compose restart mariadb

# Exec into a running container
docker compose exec nginx sh
docker compose exec wordpress sh
docker compose exec mariadb sh
```

### Logs

```bash
# Stream logs from all services
docker compose logs -f

# Stream logs from a specific service
docker compose logs -f wordpress

# Show the last 50 lines
docker compose logs --tail=50 mariadb
```

### Images

```bash
# List project images
docker images | grep inception

# Force a full image rebuild (no cache)
docker compose build --no-cache

# Remove dangling (untagged) images
docker image prune -f
```

### Volumes

```bash
# List volumes used by the project
docker volume ls | grep inception

# Inspect a volume (shows its mount point on the host)
docker volume inspect inception_db_data
docker volume inspect inception_wp_data

# Delete a specific volume (container must be stopped first)
docker volume rm inception_db_data
```

### Networks

```bash
# List project networks
docker network ls | grep inception

# Inspect a network (shows which containers are attached)
docker network inspect inception_frontend
docker network inspect inception_backend
```

---

## Where data is stored and how it persists

The project uses two **named Docker volumes** to persist state across container restarts and rebuilds.

### `db_data` — MariaDB data directory

| Property | Value |
|---|---|
| Mounted at (container) | `/var/lib/mysql` |
| Contents | All database files: tables, indexes, transaction logs |
| Initialised by | `mariadb/entrypoint.sh` on first start, only if `/var/lib/mysql/mysql` does not yet exist |

The database is bootstrapped exactly once. On every subsequent start, the entrypoint detects the existing data directory and skips initialisation, handing off directly to `mysqld`.

### `wp_data` — WordPress web root

| Property | Value |
|---|---|
| Mounted at (wordpress container) | `/var/www/html` (read-write) |
| Mounted at (nginx container) | `/var/www/html` (read-only) |
| Contents | WordPress core files, `wp-config.php`, plugins, themes, and all uploaded media |
| Initialised by | `wordpress/entrypoint.sh` on first start (writes `wp-config.php` from secrets) |

nginx mounts this volume read-only so it can serve static assets (images, CSS, JS) directly without forwarding every request to PHP-FPM, which is the standard performance pattern for WordPress stacks.

### Persistence behaviour summary

| Action | `db_data` | `wp_data` |
|---|---|---|
| `docker compose down` | ✅ Preserved | ✅ Preserved |
| `docker compose down -v` | ❌ Deleted | ❌ Deleted |
| `docker compose build` | ✅ Preserved | ✅ Preserved |
| Container crash / restart | ✅ Preserved | ✅ Preserved |
| Host reboot | ✅ Preserved | ✅ Preserved |

---

## TLS certificate

The nginx image generates a **self-signed certificate** at build time using OpenSSL:

```
/etc/nginx/ssl/server.crt
/etc/nginx/ssl/server.key
```

This is sufficient for local development and 42 evaluation. For a production deployment, replace these with certificates issued by a trusted CA (e.g. Let's Encrypt) by mounting them into the nginx container via a volume.

---

## Makefile reference

```makefile
NAME    = inception

all: $(NAME)

$(NAME):
	cd srcs && docker compose up -d --build

clean:
	docker compose -f down

fclean: clean
	cd srcs && docker compose -f down --volumes --rmi all --remove-orphans
	docker image prune -af

re: fclean all

.PHONY: all clean fclean re
```
