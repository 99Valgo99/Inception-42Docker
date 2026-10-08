# wordpress Dockerfile

FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    php-fpm php-mysqli curl ca-certificates && rm -rf /var/lib/apt/lists/*

RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp

RUN sed -i 's|listen = /run/php/php8.2-fpm.sock|listen = 9000|g' /etc/php/8.2/fpm/pool.d/www.conf

COPY tools/wordpress_start.sh /wordpress_start.sh
RUN chmod +x /wordpress_start.sh

EXPOSE 9000

ENTRYPOINT ["/wordpress_start.sh"]