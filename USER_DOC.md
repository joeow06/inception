# User Documentation

This guide explains, in simple terms, how to operate the **Inception** stack as
an end user or administrator.

## What the stack provides

Inception runs a complete, self-hosted **WordPress website** served securely
over HTTPS. It is made of three cooperating services:

| Service       | Role                                                             | Reachable from |
| ------------- | ---------------------------------------------------------------- | -------------- |
| **NGINX**     | Web server / HTTPS entry point (TLS 1.2 & 1.3, self-signed cert) | The host, port `443` |
| **WordPress** | The website itself (WordPress + PHP-FPM)                         | Internal only  |
| **MariaDB**   | The database storing all website content                         | Internal only  |

Only NGINX is exposed to the outside world. Visitors always connect through
`https://` on port `443`; WordPress and MariaDB stay hidden on a private
internal network.

## Starting and stopping the project

All operations are run from the **root of the repository** using `make`.

| Action                       | Command       |
| ---------------------------- | ------------- |
| Start everything (build + run) | `make`      |
| Stop the project             | `make down`   |
| Restart from scratch         | `make re`     |
| Stop and clean up everything | `make fclean` |

After `make`, the containers run in the background. The first start takes longer
because the images are built and WordPress is downloaded and configured
automatically.

## Accessing the website

1. Make sure the domain name resolves to the host. For local use, add this line
   to `/etc/hosts`:

   ```
   127.0.0.1   jow.42.fr
   ```

2. Open your browser at:

   ```
   https://jow.42.fr
   ```

3. Because the certificate is **self-signed**, your browser will show a security
   warning. This is expected — accept/continue to reach the site.

### Administration panel

The WordPress admin dashboard is available at:

```
https://jow.42.fr/wp-admin
```

On the very first visit, WordPress runs its installation wizard, where you set
the **site title** and create the **administrator account** (admin username and
password). After that, log in at `/wp-admin` with those credentials to manage
posts, pages, users, themes, and settings.

## Locating and managing credentials

There are two distinct sets of credentials:

### 1. Database credentials (managed by you, the administrator)

These are defined **before** starting the stack:

- **Non-secret settings** live in `srcs/.env` (database name, WordPress DB user
  name, domain name, etc.).
- **Passwords** live in the `secrets/` directory, one password per file:
  - `secrets/db_root_password.txt` — the MariaDB **root** password.
  - `secrets/db_password.txt` — the MariaDB **application user** password used by
    WordPress.

To change a database password: stop the stack (`make down`), edit the relevant
file in `secrets/`, then start again. For a fully clean re-initialization of the
database, use `make re`.

> These passwords are mounted into the containers as Docker **secrets** (files
> under `/run/secrets/…`), so they are never exposed through `docker inspect` or
> baked into the images.

### 2. WordPress credentials (managed in the browser)

The WordPress administrator account is **not** stored in the project files. You
create it during the installation wizard on first visit, and you manage it
afterward from **`/wp-admin` → Users**.

## Checking that the services are running

Run these from the repository root:

- **List running containers** — all three should appear and stay `Up`:

  ```bash
  docker compose -f srcs/docker-compose.yml ps
  ```

  You should see `nginx`, `wordpress`, and `mariadb`. MariaDB additionally
  reports a `healthy` status once its health check passes.

- **View logs** (helpful if something doesn't start):

  ```bash
  docker compose -f srcs/docker-compose.yml logs          # all services
  docker compose -f srcs/docker-compose.yml logs nginx    # one service
  ```

- **Test the website responds** over HTTPS (`-k` accepts the self-signed cert):

  ```bash
  curl -k https://jow.42.fr
  ```

If all three containers are `Up` and the website loads in the browser, the stack
is working correctly.

## Troubleshooting quick reference

| Symptom                                  | What to check                                                        |
| ---------------------------------------- | -------------------------------------------------------------------- |
| Browser can't reach `jow.42.fr`          | Is the `/etc/hosts` entry present? Are the containers `Up`?          |
| Certificate warning                      | Expected — the certificate is self-signed; accept and continue.      |
| A container keeps restarting             | Check its logs (see above), especially MariaDB/WordPress passwords.  |
| Want a completely fresh install          | `make fclean` then `make` (this erases all data — see DEV_DOC.md).   |
