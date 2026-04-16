*This project has been created as part of the 42 curriculum by jaehylee.*

---

# Inception

## Description

Inception is a system administration project from the 42 curriculum. Its goal is to broaden knowledge of system administration by using **Docker** to set up a small but complete infrastructure composed of several services, all running inside a personal virtual machine.

The project orchestrates **nine containerised services** with **Docker Compose**, each built from its own Dockerfile on **Alpine Linux 3.22.3** — no pre-built service images are pulled from any registry (Alpine itself being the only exception permitted by the subject).

| Service       | Role                                                                                              |
| ------------- | ------------------------------------------------------------------------------------------------- |
| **nginx**     | Sole public entrypoint. TLS 1.3 termination on port 443, HTTP→HTTPS redirect, FastCGI to WordPress |
| **wordpress** | PHP-FPM 8.3 application server running WordPress (installed and configured via WP-CLI)             |
| **mariadb**   | Relational database backend for WordPress                                                          |
| **redis**     | In-memory object cache for WordPress                                                               |
| **ftp**       | vsftpd FTP server giving direct file access to the WordPress web root volume                       |
| **static**    | Standalone static résumé / portfolio site, compiled from a real **barbell (BQN)** template         |
| **adminer**   | Lightweight web-based database management UI, restricted to private network ranges                 |
| **monitoring**| Prometheus + Grafana managed together by supervisord in a single container                         |
| **cadvisor**  | Custom Python container-metrics exporter reading the Docker Engine API; scraped by Prometheus      |

The WordPress site is reachable only at `https://jaehylee.42.fr` over **TLS 1.3 only**. All nine services share a single custom bridge network called **`limbo`**.

### Main Design Choices

#### Virtual Machines vs Docker

|                 | Virtual Machines                                            | Docker                                                     |
| --------------- | ----------------------------------------------------------- | ---------------------------------------------------------- |
| Isolation       | Full OS-level isolation via a hypervisor                    | Process-level isolation via Linux namespaces and cgroups   |
| Resource usage  | Heavy — each VM carries its own kernel                      | Lightweight — containers share the host kernel             |
| Boot time       | Minutes                                                     | Milliseconds                                               |
| Portability     | Image files are large (GBs)                                 | Images are layered and cache-friendly                      |
| Use case        | Full OS simulation, strong security boundaries              | Microservices, reproducible environments                   |

This project uses Docker because it needs lightweight, reproducible, and composable service units — not full OS simulation. Each service runs in its own container, keeping responsibilities separated while remaining efficient. The VM itself is used only as the outermost container host, as the subject requires.

#### Secrets vs Environment Variables

|                | Environment Variables                                                              | Docker Secrets                                                          |
| -------------- | ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Visibility     | Exposed in `docker inspect`, `/proc/<pid>/environ`, logs, shell history            | Mounted as in-memory tmpfs files under `/run/secrets/`, hidden from `inspect` |
| Risk surface   | Any process in the container can read them; may leak through logs or crash dumps    | Only accessible to services explicitly granted them                     |
| Suitability    | Non-sensitive configuration (hostnames, ports, flags)                              | Passwords, tokens, private keys                                         |

This project uses **Docker Secrets** for every credential — thirteen in total, covering MariaDB root/user passwords, WordPress admin and subscriber accounts (username, password, email for each), the Redis password, and FTP credentials. Each service's `entrypoint.sh` reads the secret files at runtime, so raw credentials never appear as environment variable values anywhere in the stack. Non-sensitive values (hostnames, ports, `*_FILE` pointers) remain plain environment variables.

#### Docker Network vs Host Network

|                | Docker Network (bridge)                                                     | Host Network                                                 |
| -------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------ |
| Isolation      | Containers communicate over a private virtual network                       | Containers share the host's network namespace directly        |
| Port exposure  | Only explicitly published ports are reachable from outside                  | All container ports are immediately reachable from the host  |
| DNS            | Docker provides automatic DNS resolution by service name                    | No container-level DNS; must use `localhost` or IPs          |
| Security       | Strong: inter-service traffic is invisible to the host                       | Weak: no network boundary between container and host         |

This project uses a single custom bridge network named **`limbo`**, declared explicitly with `driver: bridge` in `docker-compose.yml`. All nine containers attach to it, giving them automatic DNS resolution by service name while keeping all inter-service traffic invisible to the host. Only the ports listed under `ports:` in `docker-compose.yml` are reachable from outside. The `monitoring` container additionally declares `extra_hosts: host-gateway` so it can reach the Docker daemon metrics endpoint on the host machine without switching to host-network mode. `cadvisor` reaches the Docker Engine API by bind-mounting `/var/run/docker.sock` read-only — again, no host-network mode required.

#### Docker Volumes vs Bind Mounts

|                  | Docker Volumes                                    | Bind Mounts                                      |
| ---------------- | ------------------------------------------------- | ------------------------------------------------ |
| Managed by       | Docker daemon                                     | Host filesystem path                             |
| Portability      | Fully portable; no host-path dependency           | Tied to the host directory structure             |
| Performance      | Optimised by Docker (especially on macOS/Windows) | Direct host I/O                                  |
| Backup           | Via `docker volume` commands                      | Direct filesystem access                         |
| Typical use      | Persistent data (databases, uploads)              | Development (live code reload, host-owned files) |

This project uses **named Docker volumes** for all persistent state:

- `db_data` — MariaDB data directory (`/var/lib/mariadb`)
- `wp_data` — WordPress web root (`/var/www/html`), shared read-write by `wordpress` and `ftp`, read-only by `nginx`
- `redis_data` — Redis RDB snapshot directory (`/data`)
- `prometheus_data` — Prometheus time-series storage (`/var/lib/prometheus`), retaining 15 days of metrics
- `grafana_data` — Grafana state: user accounts, manually created dashboards, plugin data (`/var/lib/grafana`)

The only bind mount in the stack is `/var/run/docker.sock` → `cadvisor:/var/run/docker.sock:ro`, which is intentional: `cadvisor` needs live read-only access to the host's Docker Engine API to export container metrics.

---

## Instructions

### Prerequisites

- Docker Engine ≥ 24
- Docker Compose plugin (`docker compose`, v2)
- `make`
- A VM (Debian/Alpine recommended) or any Linux host

### 1. Clone the repository

```zsh
git clone https://github.com/DavidLee18/42_inception.git
cd 42_inception
```

### 2. Enable the Docker daemon metrics endpoint on the host

Prometheus scrapes the Docker daemon's built-in metrics endpoint (`host-gateway:9323`). Add or merge the following into `/etc/docker/daemon.json`, then restart Docker:

```json
{
  "metrics-addr": "0.0.0.0:9323",
  "experimental": true
}
```

```zsh
sudo systemctl restart docker
```

Verify:

```zsh
curl -s http://localhost:9323/metrics | head -5
```

### 3. Create the thirteen secret files

Populate `secrets/` at the repository root — it is gitignored and must never be committed. See `DEV_DOC.md` for a ready-to-paste block of commands.

### 4. Add the domain to `/etc/hosts` (local development only)

```zsh
echo "127.0.0.1  jaehylee.42.fr" | sudo tee -a /etc/hosts
```

### 5. Build and launch

```zsh
# Build all images and start all nine containers in the background
make

# Stop containers (preserves every volume)
make down

# Stop containers and erase all data + built images
make fclean

# Full rebuild from scratch
make re
```

Once the containers are up, open `https://jaehylee.42.fr` in your browser and accept the self-signed certificate warning.

### Project structure

```
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── LICENSE
├── secrets/                         # 13 gitignored secret files
└── srcs/
    ├── docker-compose.yml
    ├── .env                         # non-sensitive env vars only
    ├── nginx/
    │   ├── Dockerfile               # Alpine 3.22.3 + nginx + openssl (self-signed cert)
    │   └── nginx.conf               # TLS 1.3 only, HSTS, FastCGI → wordpress:9000
    ├── mariadb/
    │   ├── Dockerfile               # Alpine 3.22.3 + mariadb (custom-built, not official image)
    │   ├── my.cnf
    │   └── entrypoint.sh            # reads 4 secrets, bootstraps DB once
    ├── wordpress/
    │   ├── Dockerfile               # Alpine 3.22.3 + php83-fpm + wp-cli
    │   ├── php-fpm.conf
    │   └── entrypoint.sh            # reads 10 secrets, writes wp-config.php, wp core install
    ├── redis/
    │   ├── Dockerfile
    │   ├── redis.conf               # allkeys-lru, 128 MB cap, dangerous commands disabled
    │   └── entrypoint.sh
    ├── ftp/
    │   ├── Dockerfile
    │   ├── vsftpd.conf              # passive mode 21100–21110, chroot jail
    │   └── entrypoint.sh
    ├── static/
    │   ├── Dockerfile               # multi-stage: CBQN builder + nginx server
    │   ├── nginx.conf               # listens on 8080
    │   ├── template.bqn             # real barbell BQN template engine
    │   └── site/
    │       ├── template.html
    │       ├── style.css
    │       └── *.bar                # fragments substituted at build time
    ├── adminer/
    │   ├── Dockerfile               # Alpine 3.22.3 + php83-fpm + nginx + Adminer 4.8.1 single-file
    │   ├── nginx.conf               # listens on 8081, allows only private IP ranges
    │   └── php-fpm.conf             # listens on 127.0.0.1:9001
    ├── monitoring/
    │   ├── Dockerfile               # Alpine 3.22.3 + prometheus + grafana + supervisor
    │   ├── supervisord.conf         # manages prometheus + grafana as child processes
    │   ├── prometheus.yml           # scrapes docker-host:9323, localhost:9090, cadvisor:8080
    │   └── grafana/
    │       ├── provisioning/
    │       │   ├── datasources/prometheus.yml
    │       │   └── dashboards/dashboard.yml
    │       └── dashboards/docker.json
    └── cadvisor/
        ├── Dockerfile               # Alpine 3.22.3 + python3
        └── exporter.py              # custom Prometheus exporter over /var/run/docker.sock
```

---

## Resources

### Documentation

- [Docker official documentation](https://docs.docker.com/)
- [Docker Compose file reference](https://docs.docker.com/compose/compose-file/)
- [Docker Secrets documentation](https://docs.docker.com/engine/swarm/secrets/)
- [Docker Engine API](https://docs.docker.com/engine/api/)
- [nginx documentation](https://nginx.org/en/docs/)
- [nginx `fastcgi_params` and PHP-FPM](https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html)
- [Alpine Linux package index](https://pkgs.alpinelinux.org/packages)
- [WordPress `wp-config.php` documentation](https://developer.wordpress.org/apis/wp-config-php/)
- [WP-CLI documentation](https://wp-cli.org/)
- [MariaDB documentation](https://mariadb.com/kb/en/documentation/)
- [Redis configuration reference](https://redis.io/docs/management/config/)
- [vsftpd manual](https://security.appspot.com/vsftpd/vsftpd_conf.html)
- [Adminer documentation](https://www.adminer.org/)
- [barbell — BQN template engine](https://github.com/jhvst/barbell)
- [CBQN — BQN runtime](https://github.com/dzaima/CBQN)
- [Prometheus documentation](https://prometheus.io/docs/introduction/overview/)
- [Grafana documentation](https://grafana.com/docs/)
- [Docker daemon metrics](https://docs.docker.com/config/daemon/prometheus/)
- [OpenSSL TLS 1.3 overview](https://www.openssl.org/blog/blog/2018/09/11/release111/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)

### Articles & Tutorials

- [Docker networking overview](https://docs.docker.com/network/)
- [Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Manage sensitive data with Docker secrets](https://docs.docker.com/engine/swarm/secrets/)
- [PHP-FPM configuration guide](https://www.php.net/manual/en/install.fpm.configuration.php)
- [TLS 1.3 — What's new (IETF)](https://www.ietf.org/blog/tls13/)
- [HSTS — HTTP Strict Transport Security](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Strict-Transport-Security)
- [Redis eviction policies](https://redis.io/docs/reference/eviction/)
- [vsftpd and passive-mode FTP](https://wiki.alpinelinux.org/wiki/FTP)
- [Grafana provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Prometheus scrape configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#scrape_config)
- [Supervisord documentation](http://supervisord.org/)

### AI Usage

**Claude (Anthropic)** was used as an assistant throughout this project, for the following tasks and parts:

- **Dockerfile generation** — producing Alpine 3.22.3-based Dockerfiles for all nine services, including the multi-stage CBQN build for `static`, the supervisord-based process management in `monitoring`, and the per-service entrypoint scripts in `mariadb`, `wordpress`, `redis`, and `ftp`.
- **`docker-compose.yml` structure** — defining multi-service orchestration, the unified `limbo` bridge network, five named volumes, `extra_hosts: host-gateway` for Docker daemon metrics access, the read-only Docker-socket bind mount for `cadvisor`, and the secret-injection pattern across all services.
- **Docker Secrets integration** — designing consistent `entrypoint.sh` scripts that read secret files at runtime (`*_FILE` env-var convention), so raw credentials never appear as environment-variable values.
- **nginx configuration** — TLS 1.3-only enforcement, HTTP→HTTPS redirect, FastCGI proxying to PHP-FPM, static-asset caching, and security headers (HSTS).
- **WordPress automation** — using WP-CLI in the WordPress entrypoint to install WordPress, create the administrator and subscriber accounts, enforce the "no `admin`-substring" rule, and enable the Redis object-cache plugin without any browser interaction.
- **Static site pipeline** — compiling CBQN from source in the builder stage and running the real `barbell` BQN template engine against `template.bqn` + `template.html` + `*.bar` fragments to produce a static `index.html`.
- **Monitoring stack** — configuring Prometheus to scrape three targets (Docker daemon, itself, `cadvisor`), provisioning Grafana at startup with Prometheus as default datasource and a pre-built Docker-containers dashboard, and wiring Prometheus + Grafana under supervisord.
- **Custom cAdvisor exporter** — writing a lightweight Python Prometheus exporter that queries the Docker Engine API over `/var/run/docker.sock` and serves per-container CPU, memory, network, and block-I/O metrics on `:8080/metrics`, refreshed by a background collector thread.
- **Documentation** — drafting and structuring this `README.md`, `USER_DOC.md`, and `DEV_DOC.md`.

AI was used strictly as a productivity and reference tool. All generated output was reviewed, understood, and validated before inclusion; every architectural decision was driven by the author, and every configuration file was read line-by-line before committing.
