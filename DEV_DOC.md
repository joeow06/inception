# Developer Documentation

This guide explains how to set up, build, run, and maintain the **Inception**
project from a developer's point of view.

## 1. Setting up the environment from scratch

### Prerequisites

- A Linux host (or VM) with:
  - **Docker Engine**
  - the **Docker Compose** plugin (`docker compose …`, v2)
  - **make**
  - `git`, `curl` (handy for testing)
- A user account that can run Docker, and `sudo` rights (the `fclean` target
  removes the host data directory with `sudo`).

### Repository layout

```
.
├── Makefile                     # build / up / down / clean / fclean / re
├── secrets/                     # password files (mounted as Docker secrets)
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs/
    ├── .env                     # non-secret environment variables
    ├── docker-compose.yml       # services, network, volumes, secrets
    └── requirements/
        ├── mariadb/   # Dockerfile + conf/50-server.cnf + tools/init_db.sh
        ├── nginx/     # Dockerfile + conf/nginx.conf  + tools/generate_ssl.sh
        └── wordpress/ # Dockerfile + conf/www.conf    + tools/setup_wordpress.sh
```

### Configuration files

**`srcs/.env`** — non-secret runtime configuration. Consumed by Compose via
`${VAR}` interpolation:

```env
DOMAIN_NAME=jow.42.fr
MYSQL_DATABASE=wordpress_db
MYSQL_USER=wp_user
WORDPRESS_DB_NAME=wordpress_db
WORDPRESS_DB_USER=wp_user
WORDPRESS_DB_HOST=mariadb
WORDPRESS_TABLE_PREFIX=wp_
```

**`secrets/`** — sensitive values, one password per file. They are declared in
`docker-compose.yml` under `secrets:` and exposed to containers as files under
`/run/secrets/…`. The entrypoint scripts read them through the `*_FILE`
environment variables (`MYSQL_ROOT_PASSWORD_FILE`, `MYSQL_PASSWORD_FILE`,
`WORDPRESS_DB_PASSWORD_FILE`):

```bash
# create / edit the two secret files
echo "your-root-password" > secrets/db_root_password.txt
echo "your-wp-db-password" > secrets/db_password.txt
```

> **Host data path.** The named volumes bind to `/home/jow/data` (see
> `DATA_DIR` in the `Makefile` and the `device:` paths in
> `docker-compose.yml`). On a different machine or user, update **both** places
> to match. The `make setup` step creates `$(DATA_DIR)/mariadb` and
> `$(DATA_DIR)/wordpress` before starting, because the bind mounts require those
> directories to already exist.

## 2. Building and launching with the Makefile / Compose

The `Makefile` is a thin wrapper around Docker Compose
(`COMPOSE_FILE = srcs/docker-compose.yml`):

| Target        | What it does                                                           |
| ------------- | ---------------------------------------------------------------------- |
| `make` / `all`| `build` + `up`                                                         |
| `make setup`  | Creates the host data directories the volumes bind to                  |
| `make build`  | `docker compose build` — build all images                              |
| `make up`     | `setup` then `docker compose up -d` — start detached                   |
| `make down`   | `docker compose down` — stop and remove containers                     |
| `make clean`  | `down` + `docker system prune -af`                                     |
| `make fclean` | `down -v`, prune images/volumes, `sudo rm -rf` the host data dir       |
| `make re`     | `fclean` then `all` — full rebuild from scratch                        |

Equivalent raw Compose commands (run from repo root):

```bash
docker compose -f srcs/docker-compose.yml build
docker compose -f srcs/docker-compose.yml up -d
docker compose -f srcs/docker-compose.yml down
```

### What happens on first launch

1. Each image is built from its `Dockerfile` (`debian:bookworm`), 
    pinned — no `latest` tags.
2. Each container runs its entrypoint script, which prepares state and then
   `exec`s the service in the foreground as **PID 1**:
   - **mariadb** (`init_db.sh`) — initializes the data dir if empty, bootstraps
     the database/user if missing (idempotent / self-healing), then
     `exec mysqld`.
   - **wordpress** (`setup_wordpress.sh`) — waits for MariaDB, downloads
     WordPress if absent, regenerates `wp-config.php` from env/secrets, fixes
     ownership/permissions, then `exec php-fpm`.
   - **nginx** (`generate_ssl.sh`) — generates a self-signed certificate if
     missing, runs `nginx -t`, then `exec nginx -g "daemon off;"`.

## 3. Managing containers and volumes

Set a shorthand for the compose file to keep commands short:

```bash
DC="docker compose -f srcs/docker-compose.yml"
```

**Containers**

```bash
$DC ps                       # status of the three services
$DC logs -f                  # follow logs (all services)
$DC logs -f wordpress        # follow one service
$DC restart nginx            # restart a single service
$DC exec mariadb bash        # open a shell inside a container
$DC build --no-cache nginx   # force-rebuild one image
```

**Inspecting the network**

```bash
docker network ls
docker network inspect srcs_inception-network
```

Services resolve each other by name on the `inception-network` bridge
(`wordpress` → `mariadb:3306`, `nginx` → `wordpress:9000`). Only NGINX publishes
a host port (`443`).

**Volumes**

```bash
docker volume ls                          # list volumes
docker volume inspect srcs_mariadb_data   # see the bound host path
$DC down -v                               # stop + remove the named volumes
```

**Inspecting secrets at runtime**

```bash
$DC exec mariadb cat /run/secrets/db_root_password
```

## 4. Where the data lives and how it persists

Persistence is provided by two **named volumes** declared in
`docker-compose.yml`. They use the `local` driver with `driver_opts` set to
**bind** them to fixed host directories, so the data is both Docker-managed and
physically located under the user's home directory:

| Volume           | Container path      | Host path (bind device)   | Contents                       |
| ---------------- | ------------------- | ------------------------- | ------------------------------ |
| `mariadb_data`   | `/var/lib/mysql`    | `/home/jow/data/mariadb`  | MariaDB database files         |
| `wordpress_data` | `/var/www/html`     | `/home/jow/data/wordpress`| WordPress core, themes, uploads |

`wordpress_data` is mounted into **both** the `wordpress` and `nginx` containers:
PHP-FPM executes the PHP files and NGINX serves static assets from the same tree.

**Persistence behavior**

- Stopping/recreating containers (`make down`, `make up`, reboots) **keeps** all
  data, because it lives on the host bind paths, not inside the containers.
- The entrypoints are idempotent: on restart they detect the existing data and
  skip re-initialization.
- `make fclean` (or `docker compose down -v` + `sudo rm -rf /home/jow/data`)
  **destroys** the data. The next `make` performs a clean first-time install
  (fresh database, fresh WordPress download, new install wizard).

> If you change the host data path, update `DATA_DIR` in the `Makefile` **and**
> the two `device:` entries in `srcs/docker-compose.yml` so they stay in sync.
