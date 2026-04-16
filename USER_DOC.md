# User Documentation

This document is for end users and administrators of the Inception stack. It explains what the stack provides, how to start and stop it, how to reach each service, where credentials live, and how to confirm that everything is running.

## What services does this stack provide?

The Inception stack runs nine services on a single bridge network (`limbo`):

| Service        | What it does                                                                                                                                                 | Where to reach it                                                         |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------- |
| **nginx**      | The sole public entrypoint of the stack. Enforces HTTPS (TLS 1.3), redirects HTTP to HTTPS, forwards PHP requests to WordPress, and serves static files.     | `https://jaehylee.42.fr`                                                   |
| **wordpress**  | The WordPress application, running via PHP-FPM 8.3. Handles all dynamic page generation and content management.                                               | `https://jaehylee.42.fr` (through nginx)                                   |
| **mariadb**    | The database storing all WordPress content: posts, pages, users, settings, and comments.                                                                      | Internal only                                                              |
| **redis**      | An in-memory object cache that speeds up WordPress by caching database query results.                                                                         | Internal only                                                              |
| **ftp**        | A vsftpd FTP server giving direct file access to the WordPress web root. Useful for uploading themes, plugins, or media.                                      | `ftp://jaehylee.42.fr:21`                                                  |
| **static**     | A standalone static portfolio / résumé site, compiled at build time from a real barbell (BQN) template — no PHP, no database, no runtime dependencies.       | `http://jaehylee.42.fr:8080`                                               |
| **adminer**    | A lightweight web interface for browsing and managing the MariaDB database. Restricted to private network ranges.                                             | `http://jaehylee.42.fr:8081` (LAN only)                                    |
| **monitoring** | Prometheus and Grafana in one container, managed by supervisord. Collects per-container metrics and visualises them.                                           | Grafana: `http://jaehylee.42.fr:3000` · Prometheus: `http://jaehylee.42.fr:9090` |
| **cadvisor**   | A custom lightweight Python exporter that reads the Docker Engine API and publishes per-container metrics for Prometheus to scrape.                           | Internal only (scraped by Prometheus on `cadvisor:8080`)                   |

> `mariadb`, `redis`, and `cadvisor` are intentionally not published to the host — they are reachable only from within `limbo` by other containers.

---

## Starting and stopping the project

All commands must be run from the root of the repository.

### Start the project

```zsh
make
```

This builds all images from scratch (`--no-cache`) and starts all nine containers in the background. On first run the build takes a few minutes; subsequent `make` invocations after `make down` are fast because images are reused.

### Stop the project (keeps all data)

```zsh
make down
```

The database, WordPress files, Redis cache, and monitoring history are all preserved in their named Docker volumes. Running `make` again resumes exactly where you left off.

### Stop the project and erase all data

```zsh
make fclean
```

> ⚠️ This permanently deletes every named volume (database, WordPress uploads, Prometheus metrics, Grafana state) **and** every built image. Use only for a completely clean slate.

### Full rebuild

```zsh
make re
```

Equivalent to `make fclean && make`.

### Restart a single service

```zsh
docker compose -f srcs/docker-compose.yml restart <service>
# e.g.
docker compose -f srcs/docker-compose.yml restart nginx
docker compose -f srcs/docker-compose.yml restart monitoring
```

---

## Accessing the services

### WordPress website

```
https://jaehylee.42.fr
```

The certificate is self-signed — accept the warning on first visit (click **Advanced → Proceed**). WordPress is fully set up automatically on first boot; there is no installation wizard.

### WordPress administration panel

```
https://jaehylee.42.fr/wp-admin
```

Log in with the credentials stored in `secrets/wp_admin_user.txt` and `secrets/wp_admin_password.txt`.

> The administrator username intentionally does not contain `admin` (case-insensitive) — this is a project requirement and is enforced at container startup. Check the file for the actual username.

### Static portfolio site

```
http://jaehylee.42.fr:8080
```

Standalone site. No login required.

### Adminer (database UI)

```
http://jaehylee.42.fr:8081
```

| Field    | Value                                |
| -------- | ------------------------------------ |
| System   | MySQL                                |
| Server   | `mariadb`                            |
| Username | contents of `secrets/db_user.txt`    |
| Password | contents of `secrets/db_password.txt`|
| Database | contents of `secrets/db_name.txt`    |

> Adminer is IP-restricted to loopback and private ranges (`127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) and is not accessible from the public internet.

### FTP access

Connect with any FTP client (e.g. FileZilla) using passive mode:

| Field      | Value                                 |
| ---------- | ------------------------------------- |
| Host       | `jaehylee.42.fr`                      |
| Port       | `21`                                  |
| Protocol   | Plain FTP (**not** SFTP)              |
| Encryption | None                                  |
| Username   | contents of `secrets/ftp_user.txt`    |
| Password   | contents of `secrets/ftp_password.txt`|

Passive-mode data ports are `21100–21110`. The FTP user is jailed inside the WordPress web root and cannot escape it.

### Grafana (monitoring dashboards)

```
http://jaehylee.42.fr:3000
```

Default first-login credentials: `admin` / `admin`. Grafana will prompt you to change the password on first login.

A **Docker Containers** dashboard is pre-loaded automatically, showing per-container CPU, memory, network I/O, and block I/O in real time from both the Docker daemon endpoint and the custom `cadvisor` exporter. No manual setup is needed.

### Prometheus (raw metrics)

```
http://jaehylee.42.fr:9090
```

No login required. Use this to run ad-hoc PromQL queries or verify that scrape targets are healthy via **Status → Targets**.

---

## Locating and managing credentials

All sensitive credentials are stored as plain-text files inside the `secrets/` directory at the root of the repository. These files are gitignored and must never be committed.

```
secrets/
├── db_root_password.txt    ← MariaDB root password
├── db_name.txt             ← WordPress database name
├── db_user.txt             ← WordPress database user
├── db_password.txt         ← WordPress database user password
├── redis_password.txt      ← Redis authentication password
├── wp_admin_user.txt       ← WordPress administrator username (must NOT contain "admin")
├── wp_admin_password.txt   ← WordPress administrator password
├── wp_admin_email.txt      ← WordPress administrator email
├── wp_user.txt             ← WordPress subscriber username
├── wp_user_password.txt    ← WordPress subscriber password
├── wp_user_email.txt       ← WordPress subscriber email
├── ftp_user.txt            ← FTP username
└── ftp_password.txt        ← FTP password
```

Docker Compose mounts these files into each container at `/run/secrets/<name>` as in-memory tmpfs. Each service's `entrypoint.sh` reads the relevant files at startup.

> The monitoring stack (Prometheus, Grafana, cadvisor) requires no secrets: Prometheus scrapes unauthenticated local endpoints, Grafana's initial admin credentials are set via its first-login flow, and cadvisor reads the Docker socket read-only.

### Changing a credential

1. Edit the relevant file in `secrets/`.
2. Restart the affected container:

```zsh
docker compose -f srcs/docker-compose.yml restart <service>
```

> Changing a database or WordPress credential **after** first boot may require manual updates inside the database, because the values are also persisted in MariaDB. The simplest safe procedure is `make fclean && make`, which wipes the database and lets the entrypoints re-bootstrap everything from the new secrets.

---

## Checking that the services are running correctly

### Quick status overview

```zsh
docker compose -f srcs/docker-compose.yml ps
```

All nine services should show `running` (or `Up`) in the Status column.

### View live logs

```zsh
# All services at once
docker compose -f srcs/docker-compose.yml logs -f

# One service at a time
docker compose -f srcs/docker-compose.yml logs -f nginx
docker compose -f srcs/docker-compose.yml logs -f wordpress
docker compose -f srcs/docker-compose.yml logs -f mariadb
docker compose -f srcs/docker-compose.yml logs -f redis
docker compose -f srcs/docker-compose.yml logs -f monitoring
docker compose -f srcs/docker-compose.yml logs -f cadvisor
```

Press `Ctrl+C` to stop following logs.

### Check HTTPS and TLS version

```zsh
curl -vk https://jaehylee.42.fr 2>&1 | grep -E "SSL connection|TLSv"
```

Expected output contains `TLSv1.3`.

### Check that HTTP redirects to HTTPS

```zsh
curl -sI http://jaehylee.42.fr | head -1
```

Expected: `HTTP/1.1 301 Moved Permanently`.

### Check the database is alive

```zsh
docker compose -f srcs/docker-compose.yml exec mariadb \
    mariadb-admin --socket=/run/mysqld/mysqld.sock ping
```

Expected: `mariadbd is alive`.

### Check the Redis cache is alive

```zsh
docker compose -f srcs/docker-compose.yml exec redis \
    redis-cli -a "$(cat secrets/redis_password.txt)" ping
```

Expected: `PONG`.

### Check WordPress users

```zsh
docker compose -f srcs/docker-compose.yml exec wordpress \
    wp user list --allow-root --path=/var/www/html
```

Should list exactly two users: the administrator (username does not contain `admin`) and the subscriber.

### Check Prometheus scrape targets

Open `http://jaehylee.42.fr:9090/targets` in your browser. Three jobs should appear, all with state **UP**:

- `docker` — Docker daemon's built-in metrics at `host-gateway:9323`
- `prometheus` — Prometheus self-scrape at `localhost:9090`
- `cadvisor` — custom exporter at `cadvisor:8080`

Equivalently, from the command line:

```zsh
curl -s http://jaehylee.42.fr:9090/api/v1/targets | python3 -m json.tool | grep -E '"health"|"scrapeUrl"'
```

### Check the custom cadvisor exporter directly

```zsh
docker compose -f srcs/docker-compose.yml exec monitoring \
    wget -qO- http://cadvisor:8080/metrics | head -20
```

Expected: Prometheus-format metrics beginning with `container_cpu_usage_seconds_total`, `container_memory_usage_bytes`, etc.
