#!/bin/sh
# mariadb entrypoint script

set -e

mkdir -p /run/mysqld
chown mysql:mysql /run/mysqld

DB_DIR="/var/lib/mysql"
MYSQL_PASSWORD="$(cat /run/secrets/db_password)"
MYSQL_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"

if [ ! -d "$DB_DIR/mysql" ]; then
    mariadb-install-db --user=mysql --datadir="$DB_DIR"

    mariadbd --user=mysql --datadir="$DB_DIR" --skip-networking &

    until mariadb-admin ping --silent do
        sleep 1
    done

    mariadb -u root << EOSQL
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOSQL

    mariadb-admin -u root -p"${MYSQL_ROOT_PASSWORD}" shutdown
fi

exec mariadbd --user=mysql --datadir="$DB_DIR"