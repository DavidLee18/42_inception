*This project has been created as part of the 42 curriculum by jaehylee.*

---

# Inception

## Description

Inception is a system-administration project from the 42 curriculum. Its goal is to broaden knowledge of system administration by using **Docker** to set up a small but complete infrastructure composed of several services, all running inside a personal virtual machine.

The project consists of **nine containerised services** orchestrated with **Docker Compose**, every image built from scratch on **Alpine Linux 3.22.4**. The mandatory stack delivers a WordPress site served over **TLS 1.3 only** at `https://jaehylee.42.fr`, backed by MariaDB. The bonus stack adds caching, file transfer, a static showcase site, a database UI, and a full observability layer.

| # | Service | Role | Status |
|---|---|---|---|
| 1 | `nginx` | Reverse proxy; TLS 1.3 termination; only external entrypoint (port 443) | Mandatory |
| 2 | `wordpress` | PHP-FPM + WP-CLI, application server for WordPress | Mandatory |
| 3 | `mariadb` | Relational database backend | Mandatory |
| 4 | `redis` | In-memory object cache for WordPress | Bonus |
| 5 | `ftp` | `vsftpd` FTP server pointing at the WordPress volume | Bonus |
| 6 | `static` | Standalone résumé site built via a multi-stage pipeline (CBQN + `sed`) | Bonus |
| 7 | `adminer` | Lightweight web-based database management UI | Bonus |
| 8 | `monitoring` | Prometheus + Grafana (supervisord), scraping Docker daemon metrics | Bonus (5th service) |
| 9 | `cadvisor` | Custom Python Prometheus exporter for per-container metrics | Bonus (5th service) |

All nine containers share a single custom bridge network named **`limbo`**.

---

## Instructions

### Option A — Automated (Vagrant + Ansible, recommended for evaluation)

**Prerequisites on the host machine:**

- [VirtualBox](https://www.virtualbox.org/)
- [Vagrant](https://www.vagrantup.com/)

**From the repository root:**

```zsh
git clone https://github.com/DavidLee18/42_inception.git
cd 42_inception
make vm      # vagrant up — provisions Docker + writes default secrets
make vm-ssh  # SSH into the VM
cd /vagrant && make
```

On first `vagrant up`, the Ansible playbook (`ansible/playbook.yml`) idempotently:

- installs Docker Engine and the Compose plugin,
- enables the Docker daemon Prometheus metrics endpoint on `:9323`,
- creates the bind-mount data directories under `/home/jaehylee/data/`,
- registers `jaehylee.42.fr → 127.0.0.1` inside the VM's `/etc/hosts`,
- writes default secrets to `srcs/secrets/` (skipped if the files already exist).

**Accessing the services from the cluster PC** — port forwarding is configured in the `Vagrantfile`, mapping cluster-PC loopback ports to VM-internal ports (TCP only, `127.0.0.1`-bound):

| Cluster PC URL | Guest port | Service |
|---|---|---|
| `https://jaehylee.42.fr:8443` | 443 | WordPress (nginx) |
| `http://localhost:8080` | 8080 | Static site |
| `http://localhost:8081` | 8081 | Adminer |
| `http://localhost:9090` | 9090 | Prometheus |
| `http://localhost:3000` | 3000 | Grafana |
| `ftp://localhost:2121` | 21 | FTP (control) |

Domain resolution options on the cluster PC, without `sudo`:

```zsh
# Firefox only (most reliable, per-profile):
echo 'user_pref("network.dns.localDomains","jaehylee.42.fr");' \
    >> ~/.mozilla/firefox/*.default*/user.js

# Or shell-wide via HOSTALIASES:
echo 'jaehylee.42.fr localhost' > ~/.hosts
echo 'export HOSTALIASES=$HOME/.hosts' >> ~/.zshrc
exec zsh -l
```

To wipe everything and start fresh:

```zsh
make vm-destroy && make vm
```

### Option B — Manual (bare metal or existing VM)

**Prerequisites:** Docker Engine ≥ 24, the Docker Compose plugin, `make`.

1. Clone the repository and `cd` into it.
2. Enable the Docker daemon Prometheus metrics endpoint — add the following to `/etc/docker/daemon.json` and restart Docker:
   ```json
   { "metrics-addr": "0.0.0.0:9323", "experimental": true }
   ```
3. Create the thirteen secret files under `srcs/secrets/` (see `DEV_DOC.md` for the complete list and constraints).
4. Add `jaehylee.42.fr 127.0.0.1` to `/etc/hosts`.
5. Run `make` from the repository root.

Stop and clean up:

```zsh
make down    # stop containers, preserve volumes
make fclean  # stop containers and erase all data
```

---

## Project Description

### Docker usage and sources

The project uses Docker Compose to orchestrate nine services, each defined by its own Dockerfile under `srcs/<service>/`. All images derive from `alpine:3.22.4` — the penultimate stable Alpine branch at the time of writing, as required by the subject. No pre-built images are pulled from any registry other than the permitted Alpine base. Every image is pinned to the tag `<service>:alpine3.22.4`; no `:latest` tag appears anywhere in the stack.

Non-sensitive configuration lives in `srcs/.env` (committed) and is wired into the compose file via `env_file:`. All credentials live in `srcs/secrets/` (gitignored) and are mounted into containers as Docker Secrets. Each service's `entrypoint.sh` reads its secret files from `/run/secrets/` at runtime, so raw credentials never appear as environment variable values, in `docker inspect`, in process environments, or anywhere in image layers.

### Main design comparisons

#### Virtual Machines vs Docker

| | Virtual Machines | Docker |
|---|---|---|
| Isolation | Full OS-level isolation via hypervisor | Process-level isolation via Linux namespaces and cgroups |
| Resource cost | Heavy — each VM carries its own kernel | Lightweight — containers share the host kernel |
| Start-up time | Tens of seconds to minutes | Milliseconds to a few seconds |
| Image size | Typically gigabytes | Layered; tens to hundreds of megabytes |
| Primary use case | Full OS simulation; strong security boundaries; running non-Linux guests | Reproducible microservices; CI/CD; immutable infrastructure |

This project uses Docker because the requirement is to compose multiple co-operating services reproducibly — not to simulate full operating systems. Each service runs in its own container, keeping responsibilities separated while remaining efficient.

#### Secrets vs Environment Variables

| | Environment Variables | Docker Secrets |
|---|---|---|
| Storage | Set in the process environment | Mounted as tmpfs files under `/run/secrets/` |
| Visibility | Visible in `docker inspect`, `/proc/<pid>/environ`, image history if baked in | Only readable by processes inside the container granted access |
| Risk surface | Leak through logs, crash dumps, child processes | Confined to the container filesystem at runtime |
| Suitable for | Non-sensitive config (hostnames, ports, feature flags) | Passwords, tokens, private keys, certificates |

This project uses **Docker Secrets** for all thirteen credentials (DB, WordPress, Redis, FTP) and the **`srcs/.env` file** only for non-sensitive configuration (domain name, service hostnames, ports, site title).

#### Docker Network vs Host Network

| | Docker Network (bridge) | Host Network |
|---|---|---|
| Isolation | Containers communicate over a private virtual network | Containers share the host's network namespace directly |
| Port exposure | Only explicitly published ports are reachable from outside | Every container port is immediately reachable from the host |
| DNS | Compose provides automatic service-name resolution | No container-level DNS; must use `localhost` or fixed IPs |
| Security | Strong — inter-service traffic is invisible to the host | Weak — no network boundary between container and host |

All nine containers share a single custom bridge network, `limbo`. `nginx` is the sole external entrypoint on port 443, satisfying the subject's requirement. The `monitoring` container uses `extra_hosts: host-gateway` to reach the Docker daemon metrics endpoint on the host without switching to host networking.

#### Docker Volumes vs Bind Mounts

| | Docker Volumes | Bind Mounts |
|---|---|---|
| Managed by | Docker daemon | Host filesystem path |
| Portability | Fully portable; no host-path dependency | Tied to a specific host directory |
| Performance | Optimised by Docker; volume driver chosen by user | Direct host I/O |
| Backup | Via `docker volume` commands | Direct filesystem access |
| Typical use | Persistent state that doesn't need host visibility | Host–container file sharing; development |

This project uses **both**. `db_data` and `wp_data` are bind mounts under `/home/jaehylee/data/`, as required by the subject (*"Your volumes will be available in the `/home/login/data` folder of the host machine using Docker"*). `redis_data`, `prometheus_data`, and `grafana_data` are named Docker volumes because they don't need host-side visibility.

---

## Resources

### Documentation

- [Docker official documentation](https://docs.docker.com/)
- [Docker Compose file reference](https://docs.docker.com/reference/compose-file/)
- [Docker Secrets](https://docs.docker.com/engine/swarm/secrets/)
- [Docker daemon metrics endpoint](https://docs.docker.com/engine/daemon/prometheus/)
- [Best practices for writing Dockerfiles](https://docs.docker.com/build/building/best-practices/)
- [Alpine Linux package index](https://pkgs.alpinelinux.org/packages)
- [nginx documentation](https://nginx.org/en/docs/)
- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [WordPress `wp-config.php` reference](https://developer.wordpress.org/apis/wp-config-php/)
- [WP-CLI documentation](https://wp-cli.org/)
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/documentation/)
- [Redis configuration](https://redis.io/docs/latest/operate/oss_and_stack/management/config/)
- [vsftpd configuration manual](https://security.appspot.com/vsftpd/vsftpd_conf.html)
- [Adminer](https://www.adminer.org/)
- [barbell — BQN template engine](https://github.com/jhvst/barbell)
- [Prometheus documentation](https://prometheus.io/docs/introduction/overview/)
- [Grafana provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Vagrant documentation](https://developer.hashicorp.com/vagrant/docs)
- [Ansible documentation](https://docs.ansible.com/)

### Articles and background reading

- [TLS 1.3 — What's New (IETF)](https://www.ietf.org/blog/tls13/)
- [HSTS — HTTP Strict Transport Security (MDN)](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Strict-Transport-Security)
- [PID 1 inside containers](https://petermalmgren.com/signal-handling-docker/)
- [OverlayFS — the Linux kernel documentation](https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html)

### AI usage

**Claude (Anthropic)** was used as an assistant throughout the project. Specifically, AI helped with:

- Drafting and reviewing the nine Dockerfiles, including the multi-stage `static` build and the supervisord-managed `monitoring` image.
- Designing the `docker-compose.yml` file: secret injection, `env_file:` wiring, healthchecks, `depends_on` ordering, bind-mount declarations, and the `extra_hosts: host-gateway` pattern.
- Writing per-service `entrypoint.sh` scripts that read secrets from `/run/secrets/` and template configuration files at runtime from `.env`-sourced variables.
- Configuring nginx (TLS 1.3-only, FastCGI to PHP-FPM, security headers), WordPress via WP-CLI (one-shot core install, admin/subscriber user creation, Redis-cache plugin activation), MariaDB bootstrap SQL, `vsftpd` passive-mode setup, and the Prometheus + Grafana provisioning layout.
- Authoring this `README.md`, `USER_DOC.md`, and `DEV_DOC.md`.
- Auditing the repository against the subject requirements and drafting remediation patches.

Every AI-generated artefact was read, understood, and tested before being committed. No code, configuration, or documentation was included that could not be explained by the author at evaluation time.
