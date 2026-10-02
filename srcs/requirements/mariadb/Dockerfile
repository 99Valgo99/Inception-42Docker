# MariaDB Dockerfile

FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install recommends \
    maraidb-server && rm -rf /var/lib/apt/lists/*

COPY tools/mariadb.sh /mariadb.sh
RUN chmod +x /mariadb.sh

COPY conf/mariadb.cnf /etc/mysql/mariadb.conf.d/mariadb.cnf

EXPOSE 3306

ENTRYPOINT ["mariadb.sh"]