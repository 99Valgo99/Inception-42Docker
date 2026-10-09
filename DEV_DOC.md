# Developer Documentation
 
### 1. Set up the environment from scratch
 
### Prerequisites
 
- A Linux VM with **Docker Engine** and the **Compose plugin** (`docker compose version` must work).
- `make`, `git`, and your user in the `docker` group (`sudo usermod -aG docker $USER`, then log out and back in).
- The domain mapped to the VM:
```sh
  echo "127.0.0.1 ayel-bou.42.fr" | sudo tee -a /etc/hosts
```
 
### Configuration files (not in git, create them yourself)
 
**`srcs/.env`**: non-secret configuration:
 
```env
DOMAIN_NAME=yourLogin.42.fr
 
# MariaDB
MYSQL_DATABASE=wordpress
MYSQL_USER=<db_user>
 
# WordPress
WP_ADMIN_USER=<must not contain "admin" / "administrator">
WP_ADMIN_EMAIL=<email>
WP_USER=<second_user>
WP_USER_EMAIL=<email>
```
 
**`secrets/`**: one password per file, mounted into containers at `/run/secrets/<name>`:
 
```sh
mkdir secrets
echo "<password>" > secrets/db_password.txt
echo "<password>" > secrets/db_root_password.txt
echo "<password>" > secrets/wp_admin_password.txt
echo "<password>" > secrets/wp_user_password.txt 
```
 
### Host data directories
 
The named volumes store their data here, so these folders must exist before the first start:
 
```sh
/home/ayel-bou/data/mariadb /home/ayel-bou/data/wordpress
```

 they get created via the Makefile first run:

 ```
DATA_DIR := /home/$(LOGIN)/data

up: $(DATA_DIR)/mariadb $(DATA_DIR)/wordpress
	docker compose -f srcs/docker-compose.yml up --build

$(DATA_DIR)/mariadb:
	sudo mkdir -p $(DATA_DIR)/mariadb

$(DATA_DIR)/wordpress:
	sudo mkdir -p $(DATA_DIR)/wordpress
 ```

## 2. Build and launch
 
| Command | What it does |
|---|---|
| `make up` | `docker compose -f srcs/docker-compose.yml up -d --build`: builds the 3 images and starts the containers |
| `make down` | Stops and removes containers and network. **Volumes and data are kept.** |
| `make clean` | Cleans up the project's containers/images |
| `make fclean` | `docker system prune -af`: removes **all** unused images, containers and networks on the machine, then sudo rm -rf volumes removing all mounted volumes|
| `make re` | `fclean` + `up` |
 
Start order is handled by Compose: `mariadb` starts first. `wordpress` waits until mariadb's healthcheck passes. `nginx` starts after `wordpress`.
 
First start takes longer, because MariaDB initialises the database and WordPress downloads and installs itself with WP-CLI. Later starts skip both steps because the volumes are already populated.
 
## 3. Manage containers
 
```sh
docker ps                                   # running containers + status/health
docker logs -f wordpress                    # follow a service's logs
docker exec -it mariadb sh                  # shell inside a container
docker images                               # nginx:1.0, wordpress:1.0, mariadb:1.0
```
 
**Check PID 1** (must be the daemon itself, not a shell):
 
```sh
> docker exec -it service_name sh
> top

logs showing that the service as PID 1
```
 
**Inspect the database and WordPress users:**
 
```sh
docker exec -it mariadb mariadb -u root -p      # password: secrets/db_root_password.txt
#   SHOW DATABASES;
#   SELECT user, host FROM mysql.user;
#   USE wordpress_db;
#   SELECT * FROM wp_user;
```
 
**Network:**
 
```sh
docker network ls                      # srcs_inception (bridge)
docker network inspect srcs_inception  # the 3 containers and their IPs
```
 
Compose prefixes networks and volumes with the project name (`srcs`, the folder of the compose file).
 
## 4. Volumes and data persistence
 
```sh
docker volume ls
docker volume inspect srcs_mariadb_volume
```
 
In `inspect`, `Options` shows `type: none, o: bind, device: /home/ayel-bou/data/mariadb`. The volume is a Docker-managed **named volume** whose data lives in that host folder.
 
```sh
ls -la /home/ayel-bou/data/mariadb      # database files (mysql/, wordpress/, ...)
ls -la /home/ayel-bou/data/wordpress    # wp-config.php, wp-content/, ...
```
 
| Data | Container path | Host path |
|---|---|---|
| Database | `/var/lib/mysql` | `/home/ayel-bou/data/mariadb` |
| Website files (shared by nginx + wordpress) | `/var/www/html` | `/home/ayel-bou/data/wordpress` |
 
**Persistence test:**
 
```sh
# 1. Create a post or comment on the site
make down && make up
# 2. Reload the site: the post is still there
```
 