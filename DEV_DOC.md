# Developer Documentation

This document is for developers who need to set up, extend, or modify the Inception stack from source. For operational guidance (starting/stopping, credentials, health), see `USER_DOC.md`.

---

## 1. Setting up the environment from scratch

### 1.1 Host prerequisites

The project targets two supported host environments. Pick one.

**Recommended: Vagrant + VirtualBox (matches the evaluation workflow)**

- [VirtualBox](https://www.virtualbox.org/) ≥ 7.0
- [Vagrant](https://www.vagrantup.com/) ≥ 2.4
- GNU `make`
- `git`

**Alternative: direct on any Linux host with Docker already installed**

- Docker Engine ≥ 24
- Docker Compose plugin (`docker compose version` should print ≥ 2.29)
- GNU `make`
- `git`

### 1.2 Repository layout

```
.
├── Makefile                    # entry point — stack management + VM management
├── Vagrantfile                 # VM definition (VirtualBox provider)
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── ansible/
│   └── playbook.yml            # idempotent VM provisioning (Docker + secrets + hosts)
└── srcs/
    ├── .env                    # non-sensitive config (committed)
    ├── secrets/                # 13 credential files (gitignored, not present until provisioned)
    ├── docker-compose.yml      # orchestrates 9 services over the `limbo` bridge network
    ├── nginx/
    ├── wordpress/
    ├── mariadb/
    ├── redis/
    ├── ftp/
    ├── static/
    ├── adminer/
    ├── monitoring/
    └── cadvisor/
```

### 1.3 Configuration files

**`srcs/.env`** — non-sensitive configuration, loaded into `wordpress`, `nginx`, and `ftp` via Compose's `env_file:` directive. Paths are resolved relative to the Compose file, so this must live next to `docker-compose.yml`, not at the repo root.

Current keys:

```
DOMAIN_NAME=jaehylee.42.fr
DB_HOST=mariadb
DB_PORT=3306
REDIS_HOST=redis
REDIS_PORT=6379
WP_HOST=wordpress
WP_FPM_PORT=9000
WP_TITLE=Inception
```

**`srcs/secrets/`** — thirteen plain-text files holding credentials. Required for the stack to start. Every file in this directory is wired as a Docker Secret in `docker-compose.yml`. See `USER_DOC.md` §4 for the full file list.

### 1.4 First-time setup

**Using Vagrant (automated):**

```zsh
git clone https://github.com/DavidLee18/42_inception.git
cd 42_inception
make vm          # vagrant up — runs ansible_local, writes default secrets
make vm-ssh      # enter the VM
cd /vagrant && make
```

Ansible performs the following on first `vagrant up`:

1. Installs Docker Engine (`5:27.3.1-1~debian.12~bookworm`) and the Compose plugin.
2. Writes `/etc/docker/daemon.json` to enable the Prometheus metrics endpoint on `0.0.0.0:9323`.
3. Creates bind-mount directories `/home/jaehylee/data/db` and `/home/jaehylee/data/wp`, owned by the `vagrant` user.
4. Registers `127.0.0.1 jaehylee.42.fr` in the VM's `/etc/hosts`.
5. Writes default secrets to `srcs/secrets/*.txt` with `force: no` (idempotent — your edits survive re-provisioning).

**Manual setup on an existing host:**

```zsh
# 1. Enable Docker daemon metrics
sudo tee /etc/docker/daemon.json <<'EOF'
{ "metrics-addr": "0.0.0.0:9323", "experimental": true }
EOF
sudo systemctl restart docker

# 2. Create bind-mount directories (the subject requires /home/login/data)
sudo mkdir -p /home/jaehylee/data/{db,wp}
sudo chown -R "$USER:$USER" /home/jaehylee/data

# 3. Create secrets (defaults shown; edit to taste)
mkdir -p srcs/secrets && chmod 700 srcs/secrets
cat > srcs/secrets/db_root_password.txt  <<< 'changeme_dbroot'
cat > srcs/secrets/db_name.txt           <<< 'wordpress'
cat > srcs/secrets/db_user.txt           <<< 'wpuser'
cat > srcs/secrets/db_password.txt       <<< 'changeme_dbpass'
cat > srcs/secrets/redis_password.txt    <<< 'changeme_redis'
cat > srcs/secrets/wp_admin_user.txt     <<< 'jaehylee'      # must NOT contain "admin"
cat > srcs/secrets/wp_admin_password.txt <<< 'changeme_admin'
cat > srcs/secrets/wp_admin_email.txt    <<< 'jaehylee@42seoul.kr'
cat > srcs/secrets/wp_user.txt           <<< 'subscriber1'
cat > srcs/secrets/wp_user_password.txt  <<< 'changeme_user'
cat > srcs/secrets/wp_user_email.txt     <<< 'user@42seoul.kr'
cat > srcs/secrets/ftp_user.txt          <<< 'ftpuser'       # must NOT be "root"
cat > srcs/secrets/ftp_password.txt      <<< 'changeme_ftp'
chmod 600 srcs/secrets/*.txt

# 4. Add domain to /etc/hosts
echo '127.0.0.1 jaehylee.42.fr' | sudo tee -a /etc/hosts

# 5. Build and launch
make
```

### 1.5 Validation constraints

Several runtime checks fail-fast at container start. Violate them and the affected service will refuse to come up:

| Check | Enforced by | Failure mode |
|---|---|---|
| `wp_admin_user` must not contain `admin` in any casing | `srcs/wordpress/entrypoint.sh` (`grep -qi 'admin'`) | Container exits with error message |
| `ftp_user` must not be `root` | `srcs/ftp/entrypoint.sh` | Container exits with error message |
| Every `.env` variable consumed by a service must be set | `: "${VAR:?...}"` guards in every entrypoint | Container exits with `VAR: parameter null or not set` |
| Every required secret file must exist | `read_secret()` helper in every entrypoint | Container exits with `ERROR: secret file not found: /run/secrets/<name>` |

---

## 2. Building and launching

### 2.1 Makefile targets

The Makefile has two logical groups: stack management (run **inside the VM**) and VM management (run **on the host**).

**Stack management (inside the VM):**

| Target | What it does |
|---|---|
| `make` / `make all` | Creates bind-mount directories, builds all images from scratch, starts the stack detached |
| `make down` | Stops all containers (preserves volumes, images, and bind-mounted data) |
| `make fclean` | Stops containers, removes all volumes and images, clears everything except bind-mounted data |
| `make re` | `fclean` then `all` — full rebuild |

**VM management (on the host):**

| Target | What it does |
|---|---|
| `make vm` | `vagrant up` — provisions the VM if not already running |
| `make vm-ssh` | SSH into the VM |
| `make vm-sync` | Snapshot-copies the repo tree into `/home/vagrant/inception` inside the VM (alternative to the live `/vagrant` synced folder) |
| `make vm-destroy` | `vagrant destroy -f` — removes the VM entirely |

### 2.2 Under the hood

`make` expands to:

```zsh
mkdir -p /home/jaehylee/data/db /home/jaehylee/data/wp
docker compose -f srcs/docker-compose.yml build --no-cache
docker compose -f srcs/docker-compose.yml up -d
```

`--no-cache` guarantees a fresh build — important because several images install system packages, and subtle apk cache differences can mask build-order bugs.

### 2.3 Service start-up ordering

`depends_on` with `condition: service_healthy` enforces:

- `wordpress` waits for `mariadb` AND `redis` to report healthy.
- `nginx` waits for `wordpress` to report healthy.
- `adminer` waits for `mariadb` to report healthy.
- `monitoring` waits for `cadvisor` to report healthy.

This eliminates race conditions at first start. Typical cold-start time on a 2-vCPU / 4 GB VM: ~60 seconds until all nine services are `healthy`.

---

## 3. Managing containers and volumes

### 3.1 Everyday container operations

```zsh
# list all services with status
docker compose -f srcs/docker-compose.yml ps

# follow aggregated logs
docker compose -f srcs/docker-compose.yml logs -f

# follow a single service's logs
docker compose -f srcs/docker-compose.yml logs -f wordpress

# exec into a running container
docker compose -f srcs/docker-compose.yml exec wordpress sh
docker compose -f srcs/docker-compose.yml exec mariadb sh

# restart one service
docker compose -f srcs/docker-compose.yml restart nginx

# rebuild one service without touching the others
docker compose -f srcs/docker-compose.yml up -d --build --force-recreate nginx
```

### 3.2 Volume inventory

```zsh
docker volume ls | grep inception
```

Expect to see:

| Volume | Type | Backing store |
|---|---|---|
| `inception_db_data` | bind | `/home/jaehylee/data/db` |
| `inception_wp_data` | bind | `/home/jaehylee/data/wp` |
| `inception_redis_data` | named | `/var/lib/docker/volumes/inception_redis_data/_data` |
| `inception_prometheus_data` | named | `/var/lib/docker/volumes/inception_prometheus_data/_data` |
| `inception_grafana_data` | named | `/var/lib/docker/volumes/inception_grafana_data/_data` |

### 3.3 Inspecting a volume

```zsh
docker volume inspect inception_db_data
```

For bind mounts, the `Mountpoint` and `Options.device` fields point at the host path. For named volumes, `Mountpoint` is under the Docker state directory.

### 3.4 Modifying a service

Typical edit cycle:

1. Edit the service's Dockerfile, `entrypoint.sh`, or config file under `srcs/<service>/`.
2. If you changed `srcs/.env`, note that `env_file:` is applied at container start — containers pick up the change on restart without rebuild.
3. For Dockerfile / entrypoint changes, rebuild just that service:
   ```zsh
   docker compose -f srcs/docker-compose.yml up -d --build --force-recreate <service>
   ```
4. Verify with `docker compose -f srcs/docker-compose.yml logs -f <service>`.

### 3.5 Rendering the final compose configuration

To see the fully-resolved config (with `env_file:` merged in, secrets expanded, etc.):

```zsh
docker compose -f srcs/docker-compose.yml config
```

Useful for debugging why an env var isn't reaching a container.

---

## 4. Data storage and persistence

### 4.1 Where each service's data lives

| Service | Mount path inside container | Host location | Persistence behaviour |
|---|---|---|---|
| `mariadb` | `/var/lib/mariadb` | `/home/jaehylee/data/db` (bind mount) | Survives `make down` and `make fclean` |
| `wordpress` | `/var/www/html` | `/home/jaehylee/data/wp` (bind mount) | Survives `make down` and `make fclean` |
| `nginx` | `/var/www/html` (read-only) | same as `wordpress` | Shares the WordPress volume |
| `ftp` | `/var/www/html` | same as `wordpress` | Shares the WordPress volume |
| `redis` | `/data` | `inception_redis_data` (named volume) | Survives `make down`; erased by `make fclean` |
| `monitoring` | `/var/lib/prometheus`, `/var/lib/grafana` | `inception_prometheus_data`, `inception_grafana_data` (named volumes) | Survives `make down`; erased by `make fclean` |
| `static`, `adminer`, `cadvisor` | — | stateless | No persistence |

### 4.2 Why bind mounts for `db_data` and `wp_data`

The subject mandates *"Your volumes will be available in the `/home/login/data` folder of the host machine using Docker"*. Named Docker volumes live under `/var/lib/docker/volumes/` by default — the only way to satisfy the `/home/<login>/data` requirement is a bind mount. The Compose stanza used:

```yaml
volumes:
  db_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/jaehylee/data/db
```

This keeps the top-level `volumes:` syntax idiomatic while forcing the backing store onto a specific host path.

### 4.3 Why named volumes for the rest

`redis_data`, `prometheus_data`, and `grafana_data` don't need host-side visibility — they exist only to let restarts preserve cache state, scrape history, and dashboard edits. Named volumes offer better portability, better Docker integration (`docker volume` tooling works cleanly), and don't clutter `/home/jaehylee/`.

### 4.4 First-run vs subsequent runs

Every entrypoint uses an initialisation guard so that expensive one-time work only happens once per data volume:

| Service | Guard | What runs on first start only |
|---|---|---|
| `mariadb` | `/var/lib/mariadb/.init_complete` | `mariadb-install-db`, user/DB creation, root password set |
| `wordpress` | existence of `/var/www/html/wp-config.php` AND `wp core is-installed` check | `wp-config.php` generation, `wp core install`, user creation, Redis plugin install |
| `ftp` | `id "$FTP_USER"` check | User creation, `chpasswd` |
| `nginx` | existence of `/etc/nginx/ssl/server.crt` | `openssl req` self-signed cert generation |

This means that after `make fclean` (which removes the named volumes but **leaves bind-mounted data intact**), `mariadb` and `wordpress` will detect the existing data and skip re-initialisation.

### 4.5 Total reset

```zsh
# inside the VM
make fclean
sudo rm -rf /home/jaehylee/data/{db,wp}
sudo mkdir -p /home/jaehylee/data/{db,wp}
make
```

Or, from the host, simply `make vm-destroy && make vm && make vm-ssh && cd /vagrant && make`.

### 4.6 Backup

The state a real-world operator would back up:

- `/home/jaehylee/data/db` — MariaDB (SQL data files)
- `/home/jaehylee/data/wp` — WordPress (uploads, plugins, themes, `wp-config.php`)
- `/var/lib/docker/volumes/inception_grafana_data` — Grafana (dashboard edits, saved users)

The rest (Redis cache, Prometheus TSDB, cAdvisor state, static site) is fully reproducible from source and does not need backing up.

---

## 5. Extending the stack

### 5.1 Adding a new service

1. Create `srcs/<new-service>/` with a `Dockerfile` (and optionally `entrypoint.sh`, config files).
2. Add a service stanza to `srcs/docker-compose.yml`. Template:
   ```yaml
   <new-service>:
     image: <new-service>:alpine3.22.4
     build:
       context: ./<new-service>
     restart: unless-stopped
     networks: [limbo]
     healthcheck: { ... }
   ```
3. If the service consumes non-sensitive config, add `env_file: - .env`.
4. If it consumes credentials, declare a new secret at the top of `docker-compose.yml` and reference it under `secrets:` in the service.
5. If it is externally reachable, add a port mapping **and** a matching forward in `Vagrantfile`.
6. Rebuild: `make re`.

### 5.2 Changing the domain

1. Edit `DOMAIN_NAME` in `srcs/.env`.
2. Update `/etc/hosts` inside the VM (and on the cluster PC).
3. Run `make re` to regenerate the self-signed TLS certificate with the new CN — the nginx entrypoint only regenerates the cert when `/etc/nginx/ssl/server.crt` is absent, which happens naturally after `make fclean`.

### 5.3 Testing changes quickly

For iterative development, the live `/vagrant` mount inside the VM means edits on the host filesystem are immediately visible to `make` inside the VM. A typical loop:

```zsh
# on the host: edit any file under srcs/
# then, inside the VM:
docker compose -f srcs/docker-compose.yml up -d --build --force-recreate <service>
docker compose -f srcs/docker-compose.yml logs -f <service>
```

No `make re` needed unless multiple services are affected.
