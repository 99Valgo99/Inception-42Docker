# wordpress Dockerfile

FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install recommends \
    php-fpm php-mysqli curl && rm -rf /var/lib/apt/lists/*

RUN curl -O https://raw.githubusercontent.com/wp-cli/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp

