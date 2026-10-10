# NGINX Dockerfile

FROM debian:bookworm

RUN apt-get update && apt-get install -y \
    --no-install-recommends nginx openssl && rm -rf /var/lib/apt/lists/*

RUN mkdir /etc/nginx/ssl

RUN openssl req -x509 -nodes -days 111 \
    -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/ayel-bou.cer \
    -subj "/CN=ayel-bou.42.fr"

COPY  conf/extended.conf /etc/nginx/conf.d/extended.conf

ENTRYPOINT ["nginx", "-g", "daemon off;"]