*This project has been created as part of the 42 curriculum by jaehylee.*

---

# Inception

## Description

Inception is a system administration project from the 42 curriculum. Its goal is to broaden knowledge of system administration by using **Docker** to set up a small but complete infrastructure composed of several services, all running inside a personal virtual machine.

The project consists of three containerized services orchestrated with **Docker Compose**:

| Service | Image base | Role |
|---|---|---|
| **nginx** | Alpine 3.22.3 | Reverse proxy, TLS 1.3 termination, static asset serving |
| **wordpress** | Alpine 3.22.3 | PHP-FPM application server running WordPress |
| **mariadb** | Alpine 3.22.3 | Relational database backend |

The site is accessible at `https://jaehylee.42.fr` over **TLS 1.3 only**.

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

This project uses **Docker Secrets** for all credentials (database root password, database name, user, and password). MariaDB reads them natively via `_FILE` environment variables. WordPress reads them via a custom `entrypoint.sh` that writes `wp-config.php` at runtime, so raw passwords never appear in environment variables.

#### Docker Network vs Host Network

| | Docker Network (bridge) | Host Network |
|---|---|---|
| Isolation | Containers communicate over a private virtual network | Containers share the host's network namespace directly |
| Port exposure | Only explicitly published ports are reachable from outside | All container ports are immediately reachable from the host |
| DNS | Docker provides automatic DNS resolution by service name | No container-level DNS; must use `localhost` or IPs |
| Security | Strong: inter-service traffic is invisible to the host | Weak: no network boundary between container and host |

This project uses **one custom bridge networks**:
- `inception` — nginx ↔ wordpress ↔ mariadb

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
- `wp_data` — WordPress web root (`/var/www/html`), shared read-write by WordPress and read-only by nginx so nginx can serve static assets directly without hitting PHP-FPM.

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
echo "strongrootpassword" > secrets/db_root_password.txt
echo "wordpress"          > secrets/db_name.txt
echo "wpuser"             > secrets/db_user.txt
echo "strongwppassword"   > secrets/db_password.txt
```

> **Never commit the `secrets/` directory.** It is listed in `.gitignore`.

### 3. Add the domain to `/etc/hosts` (local testing only)

```bash
echo "127.0.0.1  jaehylee.42.fr" | sudo tee -a /etc/hosts
```

### 4. Build and start

```bash
make all
```

### 5. Access the site

Open `https://jaehylee.42.fr` in your browser. Accept the self-signed certificate warning on first visit.

The WordPress installation wizard will guide you through the initial setup.

### 6. Stop and clean up

```bash
# Stop containers (preserves volumes)
docker compose down

make clean
```

### Project structure

```
.
├── docker-compose.yml
├── secrets/                   # Secret files (not committed)
│   ├── db_root_password.txt
│   ├── db_name.txt
│   ├── db_user.txt
│   └── db_password.txt
├── nginx/
│   ├── Dockerfile
│   └── nginx.conf
└── wordpress/
    ├── Dockerfile
    ├── php-fpm.conf
    └── entrypoint.sh
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
- [MariaDB Docker Hub — environment variables](https://hub.docker.com/_/mariadb)
- [OpenSSL TLS 1.3 overview](https://www.openssl.org/blog/blog/2018/09/11/release111/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)

### Articles & Tutorials

- [Docker networking overview](https://docs.docker.com/network/)
- [Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Manage sensitive data with Docker secrets](https://docs.docker.com/engine/swarm/secrets/)
- [PHP-FPM configuration guide](https://www.php.net/manual/en/install.fpm.configuration.php)
- [TLS 1.3 — What's New](https://www.ietf.org/blog/tls13/)
- [HSTS — HTTP Strict Transport Security](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Strict-Transport-Security)

### AI Usage

**Claude (Anthropic)** was used as an assistant throughout this project for the following tasks:

- **Dockerfile generation** — producing Alpine-based Dockerfiles for nginx (with TLS 1.3) and WordPress (with PHP-FPM), including the correct `apk` package names for PHP 8.3 extensions.
- **docker-compose.yml structure** — defining multi-service orchestration, network segmentation (`frontend`/`backend`), named volumes, and secret injection patterns.
- **Docker Secrets integration** — designing the `entrypoint.sh` script that reads secret files at runtime and writes `wp-config.php`, avoiding credential exposure in environment variables.
- **nginx configuration** — configuring TLS 1.3-only, HTTP→HTTPS redirect, FastCGI proxying to PHP-FPM, static asset caching, and security headers.
- **README writing** — drafting and structuring this document, including the comparison tables for VM vs Docker, Secrets vs Env Vars, Docker Network vs Host Network, and Volumes vs Bind Mounts.

AI was used as a productivity and reference tool. All generated output was reviewed, understood, and validated before being included in the project.
