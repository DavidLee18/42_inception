# User Documentation

## What services does this stack provide?

The Inception stack runs seven services working together:

| Service | What it does | Where to reach it |
|---|---|---|
| **nginx** | The front door of the WordPress application. Enforces HTTPS (TLS 1.3), forwards PHP requests to WordPress, and serves static files directly. | `https://jaehylee.42.fr` |
| **wordpress** | The WordPress application, running via PHP-FPM. Handles all dynamic page generation and content management. | `https://jaehylee.42.fr` |
| **mariadb** | The database storing all WordPress content: posts, pages, users, settings, and comments. Never directly reachable from outside the stack. | Internal only |
| **redis** | An in-memory object cache that speeds up WordPress by storing database query results and computed data. Never directly reachable from outside. | Internal only |
| **ftp** | An FTP server giving direct file access to the WordPress web root. Useful for uploading themes, plugins, or media. | `ftp://jaehylee.42.fr:21` |
| **static** | A standalone static portfolio/resume website, built at image build time — no PHP, no database. | `http://jaehylee.42.fr:8080` |
| **adminer** | A lightweight web interface for browsing and managing the MariaDB database. | `http://jaehylee.42.fr:8081` |

---

## Starting and stopping the project

All commands must be run from the root of the repository.

### Start the project

```bash
make
```

This builds all images and starts all seven containers in the background. On first run, Docker builds the images before starting them — this takes a few minutes.

### Stop the project (keeps all data)

```bash
make down
```

The database, WordPress files, and Redis cache are preserved in Docker volumes. Running `make` again resumes exactly where you left off.

### Stop the project and erase all data

```bash
make fclean
```

> ⚠️ This permanently deletes the database and all WordPress files. Use only if you want a completely clean slate.

### Restart a single service

```bash
docker compose restart nginx
docker compose restart wordpress
docker compose restart mariadb
docker compose restart redis
docker compose restart ftp
docker compose restart static
docker compose restart adminer
```

---

## Accessing the website and the administration panel

### WordPress website

```
https://jaehylee.42.fr
```

Accept the self-signed certificate warning on first visit (click "Advanced" → "Proceed"). WordPress is fully set up automatically on first boot — there is no installation wizard.

### WordPress administration panel

```
https://jaehylee.42.fr/wp-admin
```

Log in with the admin credentials stored in `secrets/wp_admin_user.txt` and `secrets/wp_admin_password.txt`.

### Static portfolio site

```
http://jaehylee.42.fr:8080
```

A standalone static site served by its own nginx instance. No login required.

### Adminer (database UI)

```
http://jaehylee.42.fr:8081
```

Fill in the login form as follows:

| Field | Value |
|---|---|
| System | MySQL |
| Server | `mariadb` |
| Username | contents of `secrets/db_user.txt` |
| Password | contents of `secrets/db_password.txt` |
| Database | contents of `secrets/db_name.txt` |

> Adminer is restricted to private network ranges and is not accessible from the public internet.

### FTP access

Connect with any FTP client (e.g. FileZilla):

| Field | Value |
|---|---|
| Host | `jaehylee.42.fr` |
| Port | `21` |
| Protocol | Plain FTP (not SFTP) |
| Encryption | None |
| Username | contents of `secrets/ftp_user.txt` |
| Password | contents of `secrets/ftp_password.txt` |

The FTP user is jailed inside the WordPress web root — they cannot access anything outside `/var/www/html`.

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

### Changing a credential

1. Edit the relevant file in `secrets/`.
2. Restart the affected container:

```bash
docker compose restart <service>
```

> Note: changing a database or WordPress credential after first boot may also require manual updates inside the running database, or a full volume wipe and rebuild with `make fclean && make`.

---

## Checking that the services are running correctly

### Quick status overview

```bash
docker compose ps
```

All seven services should show `running` in the Status column.

### View live logs

```bash
# All services at once
docker compose logs -f

# One service at a time
docker compose logs -f nginx
docker compose logs -f wordpress
docker compose logs -f mariadb
docker compose logs -f redis
docker compose logs -f ftp
docker compose logs -f static
docker compose logs -f adminer
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
docker compose exec redis redis-cli -a "$(cat secrets/redis_password.txt)" ping
```

Expected: `PONG`

### Check WordPress users

```bash
docker compose exec wordpress wp user list --allow-root --path=/var/www/html
```

Should list exactly two users: the administrator and the subscriber.
