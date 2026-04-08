# User Documentation

## What services does this stack provide?

The Inception stack runs eight services:

| Service | What it does | Where to reach it |
|---|---|---|
| **nginx** | The front door of the WordPress application. Enforces HTTPS (TLS 1.3), forwards PHP requests to WordPress, and serves static files directly. | `https://jaehylee.42.fr` |
| **wordpress** | The WordPress application, running via PHP-FPM. Handles all dynamic page generation and content management. | `https://jaehylee.42.fr` |
| **mariadb** | The database storing all WordPress content: posts, pages, users, settings, and comments. Never directly reachable from outside the stack. | Internal only |
| **redis** | An in-memory object cache that speeds up WordPress by storing database query results. Never directly reachable from outside. | Internal only |
| **ftp** | An FTP server giving direct file access to the WordPress web root. Useful for uploading themes, plugins, or media. | `ftp://jaehylee.42.fr:21` |
| **static** | A standalone static portfolio/resume website built at image build time — no PHP, no database. | `http://jaehylee.42.fr:8080` |
| **adminer** | A lightweight web interface for browsing and managing the MariaDB database. | `http://jaehylee.42.fr:8081` |
| **monitoring** | Prometheus and Grafana running together in one container. Collects and visualises metrics from all containers via the Docker daemon. | Grafana: `http://jaehylee.42.fr:3000` · Prometheus: `http://jaehylee.42.fr:9090` |

---

## Starting and stopping the project

All commands must be run from the root of the repository.

### Start the project

```bash
make
```

This builds all images and starts all eight containers in the background. On first run, Docker builds the images before starting them — this takes a few minutes.

### Stop the project (keeps all data)

```bash
make down
```

The database, WordPress files, Redis cache, and monitoring history are all preserved in Docker volumes. Running `make` again resumes exactly where you left off.

### Stop the project and erase all data

```bash
make fclean
```

> ⚠️ This permanently deletes all volumes including the database, WordPress uploads, and Prometheus metrics history. Use only if you want a completely clean slate.

### Restart a single service

```bash
docker compose restart <service>
# e.g.
docker compose restart nginx
docker compose restart monitoring
```

---

## Accessing the services

### WordPress website

```
https://jaehylee.42.fr
```

Accept the self-signed certificate warning on first visit (click "Advanced" → "Proceed"). WordPress is fully set up automatically on first boot — there is no installation wizard.

### WordPress administration panel

```
https://jaehylee.42.fr/wp-admin
```

Log in with the credentials stored in `secrets/wp_admin_user.txt` and `secrets/wp_admin_password.txt`.

> The administrator username is intentionally not `admin` — this is a project requirement. Check the file for the actual username.

### Static portfolio site

```
http://jaehylee.42.fr:8080
```

A standalone static site. No login required.

### Adminer (database UI)

```
http://jaehylee.42.fr:8081
```

| Field | Value |
|---|---|
| System | MySQL |
| Server | `mariadb` |
| Username | contents of `secrets/db_user.txt` |
| Password | contents of `secrets/db_password.txt` |
| Database | contents of `secrets/db_name.txt` |

> Adminer is restricted to private network ranges and is not accessible from the public internet.

### FTP access

Connect with any FTP client (e.g. FileZilla) using passive mode:

| Field | Value |
|---|---|
| Host | `jaehylee.42.fr` |
| Port | `21` |
| Protocol | Plain FTP (not SFTP) |
| Encryption | None |
| Username | contents of `secrets/ftp_user.txt` |
| Password | contents of `secrets/ftp_password.txt` |

The FTP user is jailed inside the WordPress web root and cannot access anything outside it.

### Grafana (monitoring dashboards)

```
http://jaehylee.42.fr:3000
```

Default credentials: `admin` / `admin`. You will be prompted to change the password on first login.

A **Docker Containers** dashboard is pre-loaded automatically, showing per-container CPU, memory, network I/O, and block I/O in real time. No manual setup is needed.

### Prometheus (raw metrics)

```
http://jaehylee.42.fr:9090
```

No login required. Use this to run ad-hoc PromQL queries or verify that scrape targets are healthy via **Status → Targets**.

---

## Locating and managing credentials

All sensitive credentials are stored as plain text files inside the `secrets/` directory at the root of the repository. These files are never committed to Git.

```
secrets/
├── db_root_password.txt    ← MariaDB root password
├── db_name.txt             ← WordPress database name
├── db_user.txt             ← WordPress database user
├── db_password.txt         ← WordPress database user password
├── redis_password.txt      ← Redis authentication password
├── wp_admin_user.txt       ← WordPress administrator username
├── wp_admin_password.txt   ← WordPress administrator password
├── wp_admin_email.txt      ← WordPress administrator email
├── wp_user.txt             ← WordPress subscriber username
├── wp_user_password.txt    ← WordPress subscriber password
├── wp_user_email.txt       ← WordPress subscriber email
├── ftp_user.txt            ← FTP username
└── ftp_password.txt        ← FTP password
```

> The monitoring stack (Prometheus + Grafana) requires no secrets — Prometheus scrapes the Docker daemon's unauthenticated local metrics endpoint, and Grafana's default credentials are set through its first-login flow.

### Changing a credential

1. Edit the relevant file in `secrets/`.
2. Restart the affected container:

```bash
docker compose restart <service>
```

> Changing a database or WordPress credential after first boot may require manual updates inside the database, or a full wipe and rebuild with `make fclean && make`.

---

## Checking that the services are running correctly

### Quick status overview

```bash
docker compose ps
```

All eight services should show `running` in the Status column.

### View live logs

```bash
# All services at once
docker compose logs -f

# One service at a time
docker compose logs -f nginx
docker compose logs -f wordpress
docker compose logs -f mariadb
docker compose logs -f redis
docker compose logs -f monitoring
```

Press `Ctrl+C` to stop following logs.

### Check HTTPS and TLS version

```bash
curl -vk https://jaehylee.42.fr 2>&1 | grep "SSL connection\|TLSv"
```

Expected output contains `TLSv1.3`.

### Check the database is alive

```bash
docker compose exec mariadb mysqladmin \
    --socket=/run/mysqld/mysqld.sock ping
```

Expected: `mysqld is alive`

### Check the Redis cache is alive

```bash
docker compose exec redis redis-cli \
    -a "$(cat secrets/redis_password.txt)" ping
```

Expected: `PONG`

### Check WordPress users

```bash
docker compose exec wordpress \
    wp user list --allow-root --path=/var/www/html
```

Should list exactly two users: the administrator and the subscriber.

### Check Prometheus scrape targets

Open `http://jaehylee.42.fr:9090/targets` in your browser. Both `docker` and `prometheus` jobs should show state **UP**.
