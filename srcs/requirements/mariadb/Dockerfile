# MariaDB Dockerfile

FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    mariadb-server && rm -rf /var/lib/apt/lists/* && rm -rf /var/lib/mysql/*

COPY tools/mariadb.sh /mariadb.sh
RUN chmod +x /mariadb.sh

COPY conf/mariadb.cnf /etc/mysql/mariadb.conf.d/mariadb.cnf

HEALTHCHECK --interval=5s --timeout=3s --retries=3 \
    CMD mariadb-admin ping -u root -p"$(cat /run/secrets/db_root_password)" --silent || exit 1

EXPOSE 3306

ENTRYPOINT ["/mariadb.sh"]