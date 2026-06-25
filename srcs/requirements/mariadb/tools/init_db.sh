#!/bin/bash
set -e

echo "Starting MariaDB initialization..."

# Resolve _FILE secrets
if [ -f "${MYSQL_ROOT_PASSWORD_FILE}" ]; then
    MYSQL_ROOT_PASSWORD=$(cat "${MYSQL_ROOT_PASSWORD_FILE}")
fi
if [ -f "${MYSQL_PASSWORD_FILE}" ]; then
    MYSQL_PASSWORD=$(cat "${MYSQL_PASSWORD_FILE}")
fi

# Create the data directory's system tables on a brand-new volume.
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing data directory..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null
fi

# Bootstrap the application database/user whenever it is missing. This covers a
# fresh volume AND a half-initialized one (e.g. a previous run that set the root
# password but failed before creating the database), so it is self-healing.
if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
    echo "Bootstrapping database '${MYSQL_DATABASE}' and user '${MYSQL_USER}'..."

    # Start the server (no networking for setup)
    echo "Starting temporary MariaDB server for setup..."
    mysqld --skip-networking --socket=/run/mysqld/mysqld.sock --user=mysql &
    pid="$!"

    # Wait for MariaDB to be ready
    echo "Waiting for MariaDB to be ready..."
    until mysqladmin --socket=/run/mysqld/mysqld.sock ping >/dev/null 2>&1; do
        sleep 1
    done
    echo "MariaDB is ready!"

    # Authenticate as root: a brand-new volume has no root password yet, while a
    # half-initialized one already does. Try passwordless first, then fall back.
    if mysql --socket=/run/mysqld/mysqld.sock -u root -e "SELECT 1;" >/dev/null 2>&1; then
        ROOT_AUTH="-u root"
    else
        ROOT_AUTH="-u root -p${MYSQL_ROOT_PASSWORD}"
    fi

    # Run setup SQL
    echo "Running setup SQL..."
    mysql --socket=/run/mysqld/mysqld.sock $ROOT_AUTH << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF

    # Shut down temporary server
    echo "Shutting down temporary MariaDB..."
    mysqladmin --socket=/run/mysqld/mysqld.sock -u root -p"${MYSQL_ROOT_PASSWORD}" shutdown

    wait "$pid" || true
fi

echo "Initialization complete. Starting MariaDB..."
exec mysqld --user=mysql --datadir=/var/lib/mysql --socket=/run/mysqld/mysqld.sock
