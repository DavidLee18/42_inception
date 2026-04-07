# User Documentation

## What services does this stack provide?

The Inception stack runs three services working together to deliver a WordPress website:

| Service | What it does |
|---|---|
| **nginx** | The front door of the application. It receives all incoming traffic, enforces HTTPS (TLS 1.3), and forwards PHP requests to WordPress. It also serves static files (images, CSS, JS) directly for better performance. |
| **wordpress** | The application itself. It runs WordPress via PHP-FPM, handles all dynamic page generation, and connects to the database to read and write content. |
| **mariadb** | The database. It stores all WordPress content: posts, pages, users, settings, and comments. It is never directly reachable from outside the stack. |

The site is accessible at: **`https://jaehylee.42.fr`**

---

## Starting and stopping the project

All commands must be run from the root of the repository.

### Start the project

```bash
docker compose up -d
```

This starts all three containers in the background. On first run, Docker will build the images automatically before starting them.

### Stop the project (keeps all data)

```bash
docker compose down
```

The database and WordPress files are preserved in Docker volumes. Starting again with `docker compose up -d` will resume exactly where you left off.

### Stop the project and erase all data

```bash
docker compose down -v
```

> ⚠️ This permanently deletes the database and all uploaded WordPress files. Use only if you want a completely clean slate.

### Restart a single service

```bash
docker compose restart nginx
docker compose restart wordpress
docker compose restart mariadb
```

---

## Accessing the website and the administration panel

### Website

Open your browser and go to:

```
https://jaehylee.42.fr
```

Accept the self-signed certificate warning on first visit (click "Advanced" → "Proceed").

### WordPress administration panel

```
https://jaehylee.42.fr/wp-admin
```

Log in with the WordPress admin account created during the initial setup wizard.

> The setup wizard appears automatically on the very first visit to the site, before any admin account exists. Follow the on-screen steps to create your admin username and password.

---

## Locating and managing credentials

All sensitive credentials are stored as plain text files inside the `secrets/` directory at the root of the repository.

```
secrets/
├── db_root_password.txt   ← MariaDB root password
├── db_name.txt            ← WordPress database name
├── db_user.txt            ← WordPress database user
└── db_password.txt        ← WordPress database user password
```

> **Important:** these files are never committed to Git. If you are setting up the project for the first time, refer to the [Developer Documentation](DEV_DOC.md) for instructions on creating them.

### Changing a credential

1. Edit the relevant file in `secrets/`.
2. Restart the affected service(s):

```bash
# If changing a database credential, restart both:
docker compose restart mariadb wordpress
```

> Note: changing the database user password after the database has already been initialised also requires updating the password inside MariaDB manually, or wiping the volume and starting fresh.

---

## Checking that the services are running correctly

### Quick status overview

```bash
docker compose ps
```

All three services should show `Up` in the `Status` column.

### View live logs

```bash
# All services at once
docker compose logs -f

# One service at a time
docker compose logs -f nginx
docker compose logs -f wordpress
docker compose logs -f mariadb
```

Press `Ctrl+C` to stop following logs.

### Check the HTTPS connection and TLS version

```bash
curl -vk https://jaehylee.42.fr 2>&1 | grep "SSL connection\|TLSv"
```

You should see `TLSv1.3` in the output.

### Check that the database is accepting connections

```bash
docker compose exec mariadb mysqladmin \
    --socket=/run/mysqld/mysqld.sock ping
```

Expected response: `mysqld is alive`

### Check that PHP-FPM is running

```bash
docker compose exec wordpress php-fpm83 -t
```

Expected response: `configuration file /etc/php83/php-fpm.conf test is successful`
