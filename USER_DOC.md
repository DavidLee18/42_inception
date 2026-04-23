# User Documentation

This document is for end users and administrators of the Inception stack. For developer-facing documentation (how to modify the project from source), see `DEV_DOC.md`.

---

## 1. What the stack provides

Nine services run simultaneously, all orchestrated by Docker Compose from a single VM:

| Service | What it does | How you reach it |
|---|---|---|
| **nginx** | Reverse proxy; handles TLS 1.3 termination; the only externally reachable service | `https://jaehylee.42.fr:8443` |
| **wordpress** | Runs the WordPress site via PHP-FPM | accessed via nginx |
| **mariadb** | Stores WordPress data | internal only |
| **redis** | Object cache for WordPress; reduces DB load | internal only |
| **ftp** | File transfer access to the WordPress web root | `ftp://localhost:2121` (passive, 21100–21110) |
| **static** | Standalone résumé / showcase site | `http://localhost:8080` |
| **adminer** | Web-based MariaDB management UI (restricted to private IP ranges) | `http://localhost:8081` |
| **monitoring** | Prometheus metrics scraping + Grafana dashboards | `http://localhost:9090` (Prometheus), `http://localhost:3000` (Grafana) |
| **cadvisor** | Custom exporter publishing per-container resource metrics to Prometheus | internal only |

All inter-service traffic flows over a single Docker bridge network, `limbo`. Nothing except `nginx` (mapped to VM port 443) is required to be exposed externally per the subject; the other ports exist to support bonus services and the monitoring stack.

---

## 2. Starting and stopping the project

All of the following commands are run **from the repository root** on the host machine.

| Action | Command |
|---|---|
| Start the VM (first time or after `vm-destroy`) | `make vm` |
| SSH into the VM | `make vm-ssh` |
| Build and start the Docker stack (inside the VM) | `cd /vagrant && make` |
| Stop the stack (preserves data) | `make down` (inside the VM) |
| Stop the stack and erase all data | `make fclean` (inside the VM) |
| Rebuild from scratch | `make re` (inside the VM) |
| Destroy the VM entirely | `make vm-destroy` (on the host) |

A typical start-to-finish session looks like:

```zsh
make vm
make vm-ssh
# now inside the VM
cd /vagrant && make
# … use the services …
exit
```

To fully reset everything:

```zsh
make vm-destroy && make vm && make vm-ssh
cd /vagrant && make
```

---

## 3. Accessing the website and administration panel

### WordPress site

Open `https://jaehylee.42.fr:8443` in a browser. The certificate is self-signed, so the browser will warn; accept the warning to continue.

If `jaehylee.42.fr` does not resolve on your machine, one of the following options works without `sudo`:

```zsh
# Firefox only (per-profile, most reliable):
echo 'user_pref("network.dns.localDomains","jaehylee.42.fr");' \
    >> ~/.mozilla/firefox/*.default*/user.js

# Shell-wide (curl + most glibc clients):
echo 'jaehylee.42.fr localhost' > ~/.hosts
echo 'export HOSTALIASES=$HOME/.hosts' >> ~/.zshrc
exec zsh -l
```

### WordPress administration panel

Navigate to `https://jaehylee.42.fr:8443/wp-admin`. Log in using the administrator credentials (see §4). Two WordPress accounts are created at first launch:

- **Administrator** — username stored in `srcs/secrets/wp_admin_user.txt`. Per the subject, this username must not contain the substring `admin` in any casing; the `wordpress` entrypoint script enforces this at start-up.
- **Subscriber** — username stored in `srcs/secrets/wp_user.txt`.

### Adminer (database UI)

Navigate to `http://localhost:8081`. Use the credentials from `srcs/secrets/db_user.txt` and `srcs/secrets/db_password.txt`, server `mariadb`, database `wordpress`.

Access to Adminer is restricted to private IP ranges (`127.0.0.1`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) at the nginx layer, so it is not reachable from the public internet.

### Grafana (monitoring dashboards)

Navigate to `http://localhost:3000`. Default credentials are `admin` / `admin`; Grafana will prompt you to change the password on first login. Two dashboards are pre-provisioned: **Docker** (per-container resource usage via cAdvisor) and **Prometheus** (self-monitoring).

### FTP

Connect with any FTP client to `localhost:2121` in passive mode. Credentials are in `srcs/secrets/ftp_user.txt` and `srcs/secrets/ftp_password.txt`. The user is chrooted to `/var/www/html` — the WordPress web root.

---

## 4. Locating and managing credentials

### Where credentials live

All thirteen credentials live as individual plain-text files under `srcs/secrets/`. This directory is gitignored; credentials are never committed to Git.

| File | Purpose |
|---|---|
| `db_root_password.txt` | MariaDB `root` password |
| `db_name.txt` | WordPress database name |
| `db_user.txt` | WordPress database user |
| `db_password.txt` | WordPress database user password |
| `redis_password.txt` | Redis `AUTH` password |
| `wp_admin_user.txt` | WordPress administrator username (must not contain `admin`) |
| `wp_admin_password.txt` | WordPress administrator password |
| `wp_admin_email.txt` | WordPress administrator email |
| `wp_user.txt` | WordPress subscriber username |
| `wp_user_password.txt` | WordPress subscriber password |
| `wp_user_email.txt` | WordPress subscriber email |
| `ftp_user.txt` | FTP username (must not be `root`) |
| `ftp_password.txt` | FTP user password |

### Default values

When the VM is first provisioned, the Ansible playbook writes default values of the form `changeme_*` to any secret file that does not already exist. Existing files are never overwritten (`force: no`), so edits survive re-provisioning.

### Changing credentials

1. Edit the relevant file under `srcs/secrets/` on the host (or directly in the VM at `/vagrant/srcs/secrets/`).
2. Run `make fclean && make` inside the VM to rebuild with the new values.

Note: once WordPress has been installed, changing `wp_admin_*` / `wp_user_*` files only affects accounts created at first launch. Post-launch changes must be made through the WordPress admin UI or via `wp user update` inside the `wordpress` container.

### Rotating the root DB password

The MariaDB entrypoint uses a marker file (`/var/lib/mariadb/.init_complete`) to detect first-run initialisation. After a successful first run, the root password is already set inside the database and is not re-applied on subsequent starts. To rotate it, either delete the bind-mount directory and rebuild (`make fclean && make`), or update the password manually via `mariadb` inside the container.

---

## 5. Checking that services are running correctly

### Quick overall view

Run inside the VM:

```zsh
cd /vagrant
docker compose -f srcs/docker-compose.yml ps
```

Each service shows a health status: `healthy`, `starting`, or `unhealthy`. The stack is fully up when all nine services report `healthy`.

### Per-service health-check endpoints

Every container has a Docker-native healthcheck defined in `docker-compose.yml`. A summary:

| Service | Check |
|---|---|
| `mariadb` | `mariadb-admin ping` with the root password |
| `redis` | `redis-cli ping` with the Redis password |
| `wordpress` | `php-fpm83 -t` plus TCP probe on `127.0.0.1:9000` |
| `nginx` | HTTPS GET on `127.0.0.1:443` |
| `ftp` | TCP probe on `127.0.0.1:21` |
| `static` | HTTP GET on `127.0.0.1:8080` |
| `adminer` | HTTP GET on `127.0.0.1:8081` |
| `monitoring` | HTTP GET on Prometheus `/-/healthy` and Grafana `/api/health` |
| `cadvisor` | HTTP GET on `127.0.0.1:8080/metrics` |

### Reading logs

```zsh
# follow logs from all services
docker compose -f srcs/docker-compose.yml logs -f

# just one service
docker compose -f srcs/docker-compose.yml logs -f wordpress
```

### Verifying TLS

From the VM or the cluster PC:

```zsh
openssl s_client -connect jaehylee.42.fr:8443 -tls1_3 -servername jaehylee.42.fr </dev/null 2>/dev/null | grep -E 'Protocol|Cipher'
```

Expected: `Protocol: TLSv1.3`. TLS 1.2 connection attempts (`-tls1_2`) should fail, as the subject requires.

### Verifying the Redis cache is active

From inside the WordPress container:

```zsh
docker exec -it srcs-wordpress-1 wp --allow-root redis status
```

Expected status: `Connected`.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Browser shows `ERR_NAME_NOT_RESOLVED` | `jaehylee.42.fr` not resolving on the client | Use one of the DNS options in §3 |
| `unhealthy` on `wordpress` | MariaDB not up yet; first start can take ~40 s | Wait; it will self-heal |
| `unhealthy` on `monitoring` | Docker daemon metrics endpoint not enabled | Confirm `/etc/docker/daemon.json` has `metrics-addr` set and Docker has been restarted |
| FTP client hangs after login | Client not in passive mode, or passive range blocked | Enable passive mode; ensure ports 21100–21110 are forwarded |
| Grafana dashboards empty | Prometheus has no scrape target yet, or scrape interval hasn't elapsed | Wait ~30 s; then check Prometheus targets at `http://localhost:9090/targets` |
