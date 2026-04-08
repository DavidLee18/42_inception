*This project has been created as part of the 42 curriculum by jaehylee.*

---

# Inception

## Description

Inception is a system administration project from the 42 curriculum. Its goal is to broaden knowledge of system administration by using **Docker** to set up a small but complete infrastructure composed of several services, all running inside a personal virtual machine.

The project consists of seven containerised services orchestrated with **Docker Compose**, all built on **Alpine Linux 3.22.3**:

| Service | Role |
|---|---|
| **nginx** | Reverse proxy, TLS 1.3 termination, static asset serving for WordPress |
| **wordpress** | PHP-FPM application server running WordPress |
| **mariadb** | Relational database backend for WordPress |
| **redis** | In-memory object cache for WordPress |
| **ftp** | vsftpd FTP server giving direct access to the WordPress web root |
| **static** | Standalone static resume/portfolio site built with a barbell-style pipeline |
| **adminer** | Lightweight web-based database management UI |

The WordPress site is accessible at `https://jaehylee.42.fr` over **TLS 1.3 only**. All seven services share a single custom bridge network called `limbo`.

### Main Design Choices

#### Virtual Machines vs Docker

| | Virtual Machines | Docker |
|---|---|---|
| Isolation | Full OS-level isolation via hypervisor | Process-level isolation via Linux namespaces and cgroups |
| Resource usage | Heavy — each VM carries its own kernel | Lightweight — containers share the host kernel |
| Boot time | Minutes | Milliseconds |
| Portability | Image files are large (GBs) | Images are layered and cache-friendly |
| Use case | Full OS simulation, strong security boundaries | Microservices, reproducible environments |

This project uses Docker because we need lightweight, reproducible, and composable service units — not full OS simulation. Each service runs in its own container, keeping responsibilities separated while remaining efficient.

#### Secrets vs Environment Variables

| | Environment Variables | Docker Secrets |
|---|---|---|
| Visibility | Exposed in `docker inspect`, `/proc/<pid>/environ`, and shell history | Mounted as in-memory tmpfs files under `/run/secrets/`, invisible to `inspect` |
| Risk surface | Any process in the container can read them; leaked in logs | Only accessible to services explicitly granted them |
| Suitability | Non-sensitive config (hostnames, ports) | Passwords, tokens, private keys |

This project uses **Docker Secrets** for all credentials: database passwords, WordPress admin and user accounts, Redis password, and FTP credentials. Each service's `entrypoint.sh` reads the secret files at runtime, so raw credentials never appear as environment variable values anywhere in the stack.

#### Docker Network vs Host Network

| | Docker Network (bridge) | Host Network |
|---|---|---|
| Isolation | Containers communicate over a private virtual network | Containers share the host's network namespace directly |
| Port exposure | Only explicitly published ports are reachable from outside | All container ports are immediately reachable from the host |
| DNS | Docker provides automatic DNS resolution by service name | No container-level DNS; must use `localhost` or IPs |
| Security | Strong: inter-service traffic is invisible to the host | Weak: no network boundary between container and host |

This project uses a single custom bridge network named **`limbo`**. All seven containers are attached to it, which gives them automatic DNS resolution by service name (e.g. `wordpress` can reach `mariadb` simply by that name) while keeping all inter-service traffic invisible to the host. Only the ports explicitly declared under `ports:` in `docker-compose.yml` are reachable from outside.

#### Docker Volumes vs Bind Mounts

| | Docker Volumes | Bind Mounts |
|---|---|---|
| Managed by | Docker daemon | Host filesystem path |
| Portability | Fully portable; no host path dependency | Tied to the host directory structure |
| Performance | Optimised by Docker (especially on macOS/Windows) | Direct host I/O |
| Backup | Via `docker volume` commands | Direct filesystem access |
| Typical use | Persistent data (databases, uploads) | Development (live code reload) |

This project uses **named Docker Volumes**:
- `db_data` — MariaDB data directory (`/var/lib/mysql`)
- `wp_data` — WordPress web root (`/var/www/html`), mounted read-write by WordPress and the FTP server, and read-only by nginx so nginx can serve static assets directly without hitting PHP-FPM
- `redis_data` — Redis RDB snapshot directory (`/data`)

---

## Instructions

### Prerequisites

- Docker Engine ≥ 24
- Docker Compose plugin (`docker compose`)
- `make`

### 1. Clone the repository

```bash
git clone https://github.com/DavidLee18/42_inception.git
cd 42_inception
```

### 2. Create the secrets

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

> **Never commit the `secrets/` directory.** It is listed in `.gitignore`.

### 3. Add the domain to `/etc/hosts` (local testing only)

```bash
echo "127.0.0.1  jaehylee.42.fr" | sudo tee -a /etc/hosts
```

### 4. Build and start

```bash
make
```

### 5. Access the services

| Service | URL |
|---|---|
| WordPress | `https://jaehylee.42.fr` |
| WordPress admin | `https://jaehylee.42.fr/wp-admin` |
| Static site | `http://jaehylee.42.fr:8080` |
| Adminer | `http://jaehylee.42.fr:8081` |
| FTP | `ftp://jaehylee.42.fr:21` |

Accept the self-signed certificate warning on first visit to the WordPress site. WordPress is fully installed automatically — no browser wizard required.

### 6. Stop and clean up

```bash
# Stop containers (preserves volumes)
make down

# Stop containers and erase all data
make fclean
```

### Project structure

```
.
├── docker-compose.yml
├── Makefile
├── secrets/                    # Not committed to Git
│   ├── db_root_password.txt
│   ├── db_name.txt
│   ├── db_user.txt
│   ├── db_password.txt
│   ├── redis_password.txt
│   ├── wp_admin_user.txt
│   ├── wp_admin_password.txt
│   ├── wp_admin_email.txt
│   ├── wp_user.txt
│   ├── wp_user_password.txt
│   ├── wp_user_email.txt
│   ├── ftp_user.txt
│   └── ftp_password.txt
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
│       ├── name.bar
│       ├── title.bar
│       ├── description.bar
│       └── pubDate.bar
└── adminer/
    ├── Dockerfile
    ├── nginx.conf
    └── php-fpm.conf
```

---

## Resources

### Documentation

- [Docker official documentation](https://docs.docker.com/)
- [Docker Compose file reference](https://docs.docker.com/compose/compose-file/)
- [Docker Secrets documentation](https://docs.docker.com/engine/swarm/secrets/)
- [nginx documentation](https://nginx.org/en/docs/)
- [nginx `fastcgi_params` and PHP-FPM](https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html)
- [Alpine Linux package index](https://pkgs.alpinelinux.org/packages)
- [WordPress `wp-config.php` documentation](https://developer.wordpress.org/apis/wp-config-php/)
- [WP-CLI documentation](https://wp-cli.org/)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)
- [Redis configuration documentation](https://redis.io/docs/management/config/)
- [vsftpd manual](https://security.appspot.com/vsftpd/vsftpd_conf.html)
- [Adminer documentation](https://www.adminer.org/)
- [barbell — BQN template engine](https://github.com/jhvst/barbell)
- [OpenSSL TLS 1.3 overview](https://www.openssl.org/blog/blog/2018/09/11/release111/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)

### Articles & Tutorials

- [Docker networking overview](https://docs.docker.com/network/)
- [Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Manage sensitive data with Docker secrets](https://docs.docker.com/engine/swarm/secrets/)
- [PHP-FPM configuration guide](https://www.php.net/manual/en/install.fpm.configuration.php)
- [TLS 1.3 — What's New](https://www.ietf.org/blog/tls13/)
- [HSTS — HTTP Strict Transport Security](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Strict-Transport-Security)
- [Redis eviction policies](https://redis.io/docs/reference/eviction/)
- [vsftpd and passive mode FTP](https://wiki.alpinelinux.org/wiki/FTP)

### AI Usage

**Claude (Anthropic)** was used as an assistant throughout this project for the following tasks:

- **Dockerfile generation** — producing Alpine 3.22.3-based Dockerfiles for all seven services, including the correct `apk` package names, multi-stage builds (static site), and per-service entrypoint scripts.
- **docker-compose.yml structure** — defining multi-service orchestration, the unified `limbo` bridge network, named volumes, and secret injection patterns across all services.
- **Docker Secrets integration** — designing consistent `entrypoint.sh` scripts across mariadb, wordpress, redis, and ftp that read secret files at runtime, so raw credentials never appear as environment variable values.
- **nginx configuration** — TLS 1.3-only enforcement, HTTP→HTTPS redirect, FastCGI proxying to PHP-FPM, static asset caching, and security headers.
- **WordPress automation** — using WP-CLI in the WordPress entrypoint to fully install WordPress, create the admin and subscriber accounts, and enable the Redis object cache plugin without any browser interaction.
- **Static site pipeline** — replicating the barbell `|variable|` substitution mechanic with `sed` and `pandoc` inside a multi-stage Alpine build.
- **Documentation** — drafting and structuring this README, USER_DOC.md, and DEV_DOC.md.

AI was used as a productivity and reference tool. All generated output was reviewed, understood, and validated before being included in the project.
