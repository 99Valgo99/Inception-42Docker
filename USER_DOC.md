# User Documentation
 
### 1. What the stack provides
 
| Service | What it does for you |
|---|---|
| **NGINX** | The web server you talk to. Only reachable over HTTPS on port 443 (TLS 1.2 / 1.3). |
| **WordPress** (php-fpm) | The website and its admin panel. |
| **MariaDB** | Stores the site's content, users and settings. Not reachable from outside. |
 
Data is kept on the host in `/home/ayel-bou/data/`, so it survives restarts.
 
## 2. Start and stop
 
Run from the root of the repository:
 
```sh
make up      # build (if needed) and start everything in the background
make down    # stop and remove the containers (your data is kept)
make re      # rebuild and restart from scratch
```
 
## 3. Access the website
 
1. Make sure the domain points to this machine (one-time):
```sh
   grep ayel-bou.42.fr /etc/hosts || echo "127.0.0.1 ayel-bou.42.fr" | sudo tee -a /etc/hosts
```
2. Open **https://ayel-bou.42.fr**.
   The certificate is self-signed, so the browser shows a warning. Accept it to continue.
3. Admin panel: **https://ayel-bou.42.fr/wp-admin**, then log in with the administrator account.
Note: `http://` (port 80) does not work on purpose. Only HTTPS is served.
 
## 4. Credentials
 
| What | Where |
|---|---|
| Domain, database name, WordPress usernames and emails | `srcs/.env` |
| Database user password | `secrets/db_password.txt` |
| Database root password | `secrets/db_root_password.txt` |
| WordPress admin / user passwords | `secrets/credentials.txt` |
 
To read one:
 
```sh
cat secrets/db_password.txt
grep WP_ srcs/.env
```
 
These files are **never committed to git** (listed in `.gitignore`). Keep them private.
 
**Changing a password:** passwords are applied only the first time the site is installed. To change one afterwards, use the WordPress admin panel (Users → Profile)
 
## 5. Check that everything runs
 
```sh
docker ps
```
You should see `nginx`, `wordpress` and `mariadb` with status `Up` (mariadb shows `(healthy)`).
 
```sh
docker logs nginx          # same for wordpress / mariadb
```
Shows a service's output if something looks wrong.
 
```sh
curl -kI https://ayel-bou.42.fr
```
Should answer `HTTP/1.1 200 OK` (or a `302` redirect). `-k` accepts the self-signed certificate, also that TLS 1.3 is enforeced as ssl protocol.

 
```sh
curl http://ayel-bou.42.fr
```
Should fail with `Connection refused`, because port 80 is not open.