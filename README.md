# Inception

![Logo](Img/Inception.png)
 
*This project has been created as part of the 42 curriculum by ayel-bou.*
## Description
 
Inception sets up a small web infrastructure with **Docker Compose** inside a virtual machine. Three services, each in its own container, built from my own Dockerfiles on `debian:bookworm`:
 
| Service | Role | Port (internal) |
|---|---|---|
| `nginx` | Only entry point. Terminates TLS (v1.2/v1.3 only), serves static files, forwards PHP to php-fpm | 443 (published) |
| `wordpress` | WordPress + php-fpm (no web server), installed and configured with WP-CLI | 9000 (FastCGI) |
| `mariadb` | WordPress database | 3306 |
 
```
 Browser ──443/TLS──► nginx ──FastCGI :9000──► wordpress ──SQL :3306──► mariadb
                        │                          │                       │
                        └──── wordpress volume ────┘                mariadb volume
                                 (/home/ayel-bou/data/wordpress)    (/home/ayel-bou/data/mariadb)
```
 
All containers share one user-defined bridge network (`inception`) and restart automatically on crash.
 
## Instructions
 
```
sh
# 1. Point the domain to the VM
echo "127.0.0.1 ayel-bou.42.fr" | sudo tee -a /etc/hosts
 
# 2. Create srcs/.env and the files in secrets/ (see DEV_DOC.md)
 
# 3. Build and start everything
make up
 
# 4. Open https://ayel-bou.42.fr  (admin panel: /wp-admin)
```
 
### Use of Docker and sources
 
```
Makefile                      → wraps docker compose
secrets/                      → passwords (git-ignored)
srcs/.env                     → non-secret configuration (git-ignored)
srcs/docker-compose.yml       → services, network, volumes, secrets
srcs/requirements/<service>/  → Dockerfile, conf/ (config files), tools/ (entrypoint scripts)
```
 
No ready-made images are pulled except the `debian:bookworm` base. Every image is tagged with its service name and an explicit version (no `latest`).
 
### Main design choices
 
- **Debian bookworm**: penultimate stable Debian, as the subject requires.
- **Correct PID 1**: every container runs its daemon in the foreground via exec-form `ENTRYPOINT` or a final `exec` in the entrypoint script (`nginx -g "daemon off;"`, `php-fpm -F`, `mariadbd`). No `tail -f`, `sleep infinity` or loops, so signals reach the real process.
- **Idempotent init scripts**: MariaDB and WordPress only initialise when their volume is empty, so restarts never reset data.
- **Readiness**: MariaDB has a compose `healthcheck`; WordPress waits for it with `depends_on: condition: service_healthy`.
- **Cross-container listening**: MariaDB `bind-address=0.0.0.0` and php-fpm `listen = 9000`, because their defaults only accept loopback connections.
- **Self-signed certificate** generated at build time for `ayel-bou.42.fr`.
***

### Virtual Machines vs Docker
 
A VM emulates hardware and boots a full guest kernel, which costs RAM, CPU and boot time. A container is just an isolated process on the host kernel (namespaces + cgroups): it starts in milliseconds and uses only what its processes use. Trade-off: weaker isolation, since all containers share one kernel.
 
### Secrets vs Environment Variables
 
Environment variables are visible through `docker inspect`, `/proc/<pid>/environ` and child processes, so they hold only non-sensitive config (domain, usernames). Passwords are **Docker secrets**: mounted as read-only files in `/run/secrets/` inside only the containers that need them, never in the image or the environment.
 
### Docker Network vs Host Network
 
A user-defined bridge network gives each container its own network namespace and lets containers reach each other by name (`mariadb`, `wordpress`) through Docker's DNS. Only port 443 is published. `network: host` removes the network namespace entirely: the container shares the host's interfaces and ports, so there is no isolation (and it is forbidden by the subject).
 
### Docker Volumes vs Bind Mounts
 
A bind mount maps any host path straight into a container, and its lifecycle is unmanaged by Docker. A named volume is a Docker-managed object (`docker volume ls/inspect`), with a driver, a name and a lifecycle, and it is populated from the image on first use. Here the named volumes use the `local` driver with `driver_opts` so their data is stored in `/home/ayel-bou/data`, while staying named volumes as the subject requires.
 
## Useful Resrources

* dotScale 2013 - Solomon Hykes - Why we built Docker | (https://youtu.be/3N3n9FzebAA)

* Inside the Docker Kernel: A Deep Dive into Container Magic… | (https://medium.com/@fernando.harsha2016/inside-the-docker-kernel-a-deep-dive-into-container-magic-277510bf1b87)

* Asymmetric Encryption | (https://www.ibm.com/think/topics/asymmetric-encryption)

* TLSv1.2 Vs TLSv1.3 | (https://www.a10networks.com/glossary/key-differences-between-tls-1-2-and-tls-1-3/)

* Docker Network | (https://docs.docker.com/engine/network/)

* Docker secrets | (https://docs.docker.com/compose/how-tos/use-secrets/)

* Docker Env Variables | (https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/)

* Docker volumes | (https://therahulsarkar.medium.com/understanding-docker-volumes-a-comprehensive-guide-46339aa9ac53)
***


**AI usage**: Claude was used as a tutor throughout the project, to explain concepts (namespaces, cgroups, OverlayFS, PID 1, FastCGI, TLS), review my Dockerfiles and configuration files, and help debug issues such as MariaDB skipping its init because the image pre-populated the new volume. It also drafted these three documentation files, which I reviewed and adjusted. The Dockerfiles, configs, scripts and Makefile were written and tested by me.
