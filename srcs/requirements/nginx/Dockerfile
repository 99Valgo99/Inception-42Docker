# NGINX Dockerfile

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    --no-install-recommends && rm -rf /var/lib/apt/lists/*

RUN mkdir /etc/nginx/ssl

RUN openssl req -x500 -nodes -days 111 \
    -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/ayel-bou.cer \
    -subj "/CN=ayel-bou.42.fr"

COPY  conf/nginx.conf /etc/nginx/nginx.conf