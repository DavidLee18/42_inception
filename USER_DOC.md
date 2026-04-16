# User Documentation — Inception

## Overview of Services

The Inception stack provides the following services:

| Service | URL / Address | Purpose |
|---|---|---|
| **WordPress** | `https://jaehylee.42.fr` | Main website |
| **WordPress Admin** | `https://jaehylee.42.fr/wp-admin` | CMS administration panel |
| **Adminer** | `http://jaehylee.42.fr:8081` | Database management UI |
| **Static site** | `http://jaehylee.42.fr:8080` | Portfolio / resume site |
| **Grafana** | `http://jaehylee.42.fr:3000` | Container monitoring dashboards |
| **Prometheus** | `http://jaehylee.42.fr:9090` | Raw metrics and scrape target status |
| **FTP** | `jaehylee.42.fr:21` | Direct file access to WordPress web root |

MariaDB (3306) and Redis (6379) are internal only — not reachable from outside the stack.

---

## Starting and Stopping the Project

### Start everything

```bash
make
```

This builds all images from scratch and starts all containers in detached mode. On first run, WordPress installation runs automatically — no browser interaction needed.

### Stop containers (preserve data)

```bash
make down
```

All volumes are preserved. Restarting with `make` resumes exactly where you left off.

### Stop and erase all data

```bash
make fclean
```

This removes all containers, images, and volumes. The next `make` performs a full rebuild from scratch.

### Full rebuild

```bash
make re
```

Equivalent to `make fclean && make`.

---

## Accessing the Website

Navigate to `https://jaehylee.42.fr` in your browser. Because the TLS certificate is self-signed, your browser will display a security warning — this is expected. Proceed past it.

The site uses **TLS 1.3 only**. Plain HTTP requests to port 80 are automatically redirected to HTTPS.

---

## Accessing the WordPress Admin Panel

Go to `https://jaehylee.42.fr/wp-admin` and log in with the administrator credentials from `secrets/wp_admin_user.txt` and `secrets/wp_admin_password.txt`.

---

## Accessing Adminer (Database UI)

Adminer is available at `http://jaehylee.42.fr:8081`.

> **Note:** Adminer is restricted to private IP ranges only (10.x.x.x, 172.16–31.x.x, 192.168.x.x). It is not accessible from the public internet.

Use the following connection details:

| Field | Value |
|---|---|
| System | MySQL |
| Server | `mariadb` |
| Username | contents of `secrets/db_user.txt` |
| Password | contents of `secrets/db_password.txt` |
| Database | contents of `secrets/db_name.txt` |

---

## Accessing Grafana (Monitoring)

Navigate to `http://jaehylee.42.fr:3000`.

On first login, use the default Grafana credentials (`admin` / `admin`) and set a new password when prompted.

Two dashboards are pre-loaded automatically:

- **Docker Containers** — per-container CPU, memory, network I/O, and block I/O in real time.
- **Prometheus 2.0 Overview** — Prometheus self-monitoring: scrape durations, TSDB head series, target health.

No manual setup is needed for either dashboard.

### Prometheus (raw metrics)

```
http://jaehylee.42.fr:9090
```

No login required. Use this to run ad-hoc PromQL queries or verify that scrape targets are healthy via **Status → Targets**.

---

## Locating and Managing Credentials

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

Non-sensitive configuration (domain name, service hostnames, ports) lives in `srcs/.env`:

```
srcs/.env
├── DOMAIN_NAME             ← e.g. jaehylee.42.fr
├── WORDPRESS_DB_HOST       ← e.g. mariadb:3306
├── DB_HOST                 ← e.g. mariadb
├── DB_PORT                 ← e.g. 3306
├── REDIS_HOST              ← e.g. redis
├── REDIS_PORT              ← e.g. 6379
└── DOCKER_METRICS_HOST     ← e.g. host-gateway:9323
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

## Checking That Services Are Running Correctly

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

```bash
curl -s http://jaehylee.42.fr:9090/api/v1/targets \
    | python3 -m json.tool | grep health
```

All targets should report `"health": "up"`.

---

## Using FTP

Connect to `jaehylee.42.fr` on port `21` using the credentials from `secrets/ftp_user.txt` and `secrets/ftp_password.txt`.

The FTP user is locked into the WordPress web root (`/var/www/html`) via a chroot jail — navigation above that directory is not possible. Files uploaded via FTP are immediately visible to WordPress.

Passive mode ports `21100–21110` must be reachable from your FTP client. Use passive mode in your client settings.

Example using `lftp`:

```bash
lftp -u "$(cat secrets/ftp_user.txt)","$(cat secrets/ftp_password.txt)" \
     ftp://jaehylee.42.fr
```
