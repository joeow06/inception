# Inception

_This project has been created as part of the 42 curriculum by jow._

## Description

**Inception** is a system administration project whose goal is to build a small
but complete web infrastructure entirely with **Docker**. Everything runs inside
a single virtual machine, and every service lives in its own dedicated container,
built from a custom `Dockerfile` based on the penultimate stable release of
**Debian** — no ready-made application images are pulled from Docker Hub.

The stack reproduces a classic WordPress hosting setup:

```
                         ┌──────────────────────────────────────────────┐
        HTTPS :443       │              inception-network (bridge)      │
  client ───────────────►│  ┌─────────┐   :9000     ┌───────────┐       │
                         │  │  NGINX  │───────────► │ WordPress │       │
                         │  │  (TLS)  │  FastCGI    │ (PHP-FPM) │       │
                         │  └─────────┘             └─────┬─────┘       │
                         │                                │ :3306       │
                         │                          ┌─────▼─────┐       │
                         │                          │  MariaDB  │       │
                         │                          └───────────┘       │
                         └──────────────────────────────────────────────┘
```

- **NGINX** — the only entry point into the infrastructure. It terminates TLS
  (TLSv1.2 / TLSv1.3 only, self-signed certificate) and is the sole container
  exposing a port to the host (`443`).
- **WordPress + PHP-FPM** — runs the WordPress application, listening on port
  `9000` and reachable only from inside the Docker network.
- **MariaDB** — the database backing WordPress, reachable only from inside the
  Docker network on port `3306`.

Persistent data (the database and the WordPress files) is stored on the host
machine through Docker volumes, so containers can be destroyed and recreated
without losing any content.

## Instructions

### Prerequisites

- A Linux host (or VM) with **Docker** and the **Docker Compose** plugin
  installed.
- `make`.
- The domain name `jow.42.fr` resolving to the host. For local testing, add the
  following line to `/etc/hosts`:

  ```
  127.0.0.1   jow.42.fr
  ```

### Configuration

Two pieces of configuration drive the stack:

- `srcs/.env` — non-secret environment variables (domain name, database name,
  WordPress user names, etc.).
- `secrets/` — the sensitive passwords, stored one per file:
  - `secrets/db_root_password.txt` — MariaDB root password.
  - `secrets/db_password.txt` — MariaDB application-user password.

> Note: in the submitted project the volumes bind to `/home/jow/data`. If you run
> this on another machine, adjust the `DATA_DIR` in the `Makefile` and the
> `device:` paths in `srcs/docker-compose.yml` accordingly.

### Build & run

Everything is driven by the `Makefile` at the root of the repository:

```bash
make            # setup + build + up  (build images and start everything detached)
make build      # build all images only
make up         # create host data dirs and start the stack (-d)
make down       # stop and remove the containers
make clean      # down + prune dangling Docker resources
make fclean     # down -v, prune everything, and remove host data dirs
make re         # fclean then full rebuild
```

Once up, browse to:

```
https://jow.42.fr
```

Your browser will warn about the self-signed certificate — this is expected;
accept it to reach the WordPress site. The first visit walks through the
WordPress installation wizard.

## Project description

### Use of Docker

The whole infrastructure is described declaratively in
`srcs/docker-compose.yml` and built from sources under
`srcs/requirements/<service>/`. Each service directory contains:

- a `Dockerfile` — builds the image from `debian:bookworm`/`debian:bullseye`,
  installs only the packages that service needs, and copies in its config and
  entrypoint script;
- `conf/` — the service configuration files (`nginx.conf`, `50-server.cnf`,
  `www.conf`);
- `tools/` — the entrypoint script that prepares and then launches the service
  as **PID 1** in the foreground (`init_db.sh`, `generate_ssl.sh`,
  `setup_wordpress.sh`).

Key design choices:

- **One process per container.** Each container runs a single foreground service
  (`mysqld`, `php-fpm`, `nginx`) using `exec`, so Docker can supervise and
  restart it correctly. `restart: always` keeps the services alive.
- **Idempotent, self-healing entrypoints.** The MariaDB and WordPress scripts
  detect whether initialization has already happened (existing data directory,
  existing `wp-login.php`) and bootstrap only what is missing, so the stack
  survives restarts and partial initializations.
- **No latest tags, no hand-running containers.** Images are pinned to a Debian
  release and built locally; the stack is only ever started through Compose.
- **Minimal exposure.** Only NGINX publishes a port (`443`). WordPress and
  MariaDB are reachable exclusively over the internal Docker network.
- **Secrets resolved at runtime.** Passwords are read from files mounted under
  `/run/secrets/…` (the `*_FILE` convention) rather than baked into images or
  passed as plain environment variables.

### Sources included in the project

```
.
├── Makefile                     # entry point: build / up / down / clean / re
├── secrets/                     # password files mounted as Docker secrets
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs/
    ├── .env                     # non-secret environment variables
    ├── docker-compose.yml       # service / network / volume / secret definitions
    └── requirements/
        ├── mariadb/             # Dockerfile + conf/50-server.cnf + tools/init_db.sh
        ├── nginx/               # Dockerfile + conf/nginx.conf + tools/generate_ssl.sh
        └── wordpress/           # Dockerfile + conf/www.conf + tools/setup_wordpress.sh
```

### Technical comparisons

#### Virtual Machines vs Docker

A **virtual machine** virtualizes hardware: a hypervisor runs a full guest
operating system, with its own kernel, on top of (or beside) the host OS. That
gives strong isolation but is heavy — each VM carries a complete OS, boots
slowly, and consumes a lot of disk and RAM.

**Docker** uses OS-level virtualization: containers share the host kernel and are
isolated with namespaces and cgroups. They ship only the application and its
dependencies, so they are far lighter, start in seconds, and are trivial to
version and reproduce from a `Dockerfile`. The trade-off is weaker isolation than
a VM and a dependency on the host kernel. For this project Docker is ideal: we
need several reproducible, lightweight, independently restartable services on one
machine — not several full operating systems.

#### Secrets vs Environment Variables

**Environment variables** (here, `srcs/.env`) are convenient for non-sensitive
configuration, but they leak easily: they are visible in `docker inspect`, in the
process environment, in `docker-compose.yml`, and often end up committed to git.

**Docker secrets** mount sensitive values as files inside the container (under
`/run/secrets/…`) instead of injecting them into the environment. They are not
exposed by `docker inspect` and are not part of the image layers. In this project
the database passwords are provided through secrets and read by the entrypoint
scripts via the `*_FILE` variables, while only harmless settings (database name,
user names, domain) live in `.env`. This keeps credentials out of the image and
out of the process environment.

#### Docker Network vs Host Network

With the **host network**, a container shares the host's network stack directly —
no isolation, port conflicts are possible, and every service is reachable on the
host's interfaces.

A **user-defined Docker network** (here the `inception-network` bridge) gives the
containers their own isolated network with built-in DNS: services reach each
other by container name (`wordpress` talks to `mariadb`, `nginx` talks to
`wordpress:9000`). Only the ports explicitly published — `443` on NGINX — are
reachable from the host. This is more secure and more maintainable: the database
is never exposed outside the network, and services are decoupled from host
networking. This is why the project uses a custom bridge network rather than the
host network.

#### Docker Volumes vs Bind Mounts

A **bind mount** maps an arbitrary host path straight into a container. It is
simple and great for development, but it ties the data to a specific host path
and to host file permissions/ownership.

A **Docker volume** is managed by Docker and decoupled from any specific host
path, which makes it the recommended way to persist container data, easy to back
up, and portable. This project uses **named volumes** (`mariadb_data`,
`wordpress_data`) — so Docker manages their lifecycle — but configures them with
`driver_opts` (`type: none`, `o: bind`, `device: …`) to bind them to a known host
directory under `/home/jow/data`. This combines the manageability of named
volumes with the requirement that the data physically live in the user's home
directory.

## Resources

Classic references used while building this project:

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose file reference](https://docs.docker.com/compose/compose-file/)
- [Docker secrets in Compose](https://docs.docker.com/compose/how-tos/use-secrets/)
- [Dockerfile best practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [NGINX documentation](https://nginx.org/en/docs/) and the
  [FastCGI / PHP-FPM configuration guide](https://www.nginx.com/resources/wiki/start/topics/examples/phpfcgi/)
- [PHP-FPM documentation](https://www.php.net/manual/en/install.fpm.php)
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/documentation/)
- [WordPress: editing `wp-config.php`](https://wordpress.org/documentation/article/editing-wp-config-php/)
- [Self-signed certificates with OpenSSL](https://www.openssl.org/docs/)

### Use of AI

AI (Claude) was used as a learning and reviewing assistant, not as a substitute
for understanding the project. Specifically:

- **Explaining concepts** — clarifying the differences covered in the comparisons
  above (VMs vs containers, secrets vs env vars, bridge vs host networking,
  volumes vs bind mounts) and how Docker namespaces, cgroups and Compose work.
