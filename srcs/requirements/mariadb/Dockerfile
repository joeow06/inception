FROM debian:bookworm

# Install MariaDB
RUN apt-get update && apt-get install -y \
    mariadb-server \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /var/run/mysqld \
    && chown -R mysql:mysql /var/run/mysqld \
    && chmod 755 /var/run/mysqld

# Copy configuration
COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/
COPY tools/init_db.sh /usr/local/bin/

# Set permissions
RUN chmod +x /usr/local/bin/init_db.sh

# Environment variables (can be overridden at runtime)
ENV MYSQL_ROOT_PASSWORD=root \
    MYSQL_DATABASE=app_db \
    MYSQL_USER=app_user \
    MYSQL_PASSWORD=app_pass

EXPOSE 3306

ENTRYPOINT ["init_db.sh"]
