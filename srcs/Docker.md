## Docker Fundamentals

### **image** vs **Container**

A **Docker Image** is a **read-only template** -- a stack of filesystem layers (**OverlayFS** lower layres) plus metadata (what command to run, what ports are documented, what env vars are default). It does nothing by itself, it's inert, sitting on disk, buildable and shareable.

A **Container** is a **running instance of an image** -- the image's layers mounted read-only, plus one new writable layer on top (the ``upper`` dir built by **OverlayFS**), plus an actual running process (PID 1 inside its own PID namespace), plus its own network namespace, mount namespace, etc...

Analogy that maps cleanly onto this: the image is like a class definition; the container is an instantiated object. We can spin up multiple containers from the same image -- each gets its own writable layer and namespaces, but shares the same read-only image laters underneath (zero duplication).
***

### What ``docker build`` does:

```
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ngnix
COPY conf/ngnix.conf /etc/ngnix/ngnix.conf
```

1. CLI tars the build context, sends it to ``dockerd``.
2. ``dokcerd`` reads the Dockerfile instructions top to bottom
3. ``FROM debian:bookworm-slim`` -- pulls (or reuses if cached) the base image's layers, this is the only pull happening in the whole project, and it's explicitly excluded from the ***"no pulling ready-made images"*** rule
4. Each ``RUN``/``COPY``/**etc**, produces exactly **one new layer**, and ``dockerd`` caches each layer keyed by (previous layer + this instruction + its input). If we rebuild and nothing changed up to a given instruction, that layer is reused instantly instead of recomputed -- this is why instrcution order in a Dockerfile matters (put things that change often like ``COPY``, after things that don't, like ``apt-get install``, so cache hits happen more)
5. The final layer stack + metadata (like what ``ENTRYPOINT`` to run) get tagged with the name we gave it (``ngnix``, pet the subject's ***"image name = service name"*** rule) -- this tag now refers to an **image**. still nothing is running.
***

### What ``docker compose up`` does:

``docker-compose.yml`` describes a desired state: which servvices exist, which images/Dockerfiles they come from, what network(s) they're on, what volumes they mount, what env vars they get. WHen we run ``docker compose up``:

1. Compose reads the YAML, resolves ``${VARIABLES}`` from ``.env``.
2. For each service with a ``build:`` key, it runs the equivalent of ``docker build`` for that service's Dockerfile if the image doesn't exist yet or --build was passed
3. It creates the custom network if it doesn't exist
4. It creates named volumes if they don't exist
5. For each service, it creates a **container** from that image, attaches it to the network (with the service name as its DNS hostname), mounts the volumes, injects the nev vars, and start PID 1 inside it

``docker compose up`` runs ``docker build`` internally, once per servcie that has a ``build:`` **key**, using that service's own **Dockerfile** (found via the path we point it to in ``docker-compose.yml`` e.g ``srcs/requirements/ngnix/Dockerfile``).
Each of those builds produce one image, independently. Once all needed images exist, Compose then create one container from each image, wires them onto the network, attaches volumes, and starts them,

So the sequence for our project, goes on the following order once we hit ``docker compose up``:

* Build ``ngnix`` image from ``srcs/requirements/ngnix/Dockerfile``
* Build ``mariadb`` image from ``srcs/requirements/mariadb/Dockerfile``
* Build ``wordpress`` image from ``srcs/requirements/wordpress/Dockerfile``
* Create the custom network
* Create the named volumes
* Start a container from each of the 3 images, attach to network, mount volimes
***

## Docker Compose

```
services:
    service_name:
        container_name: service_name
        build: ./path
        image: servive_name:1.0
        ports:
            - "portN:portN"
        networks:
            - inception
networks:
    inception:
```

* ``services:`` is the top-level key. Everything under it is one service, and each service becomes one container. Later ``mariadb`` and ``wordpress`` will sit next to ``nginx`` at this same level.

* ``service_name:`` is the service name. It has two jobs:

> the subject requires each image to have the same name as its service, and Compose registers the service name as a **DNS Hostname** on the Docker network. This is how WordPress will reach ``mariadb`` by name.

* ``build: ./path`` is the build context. The path is relative to the compose file's location (``srcs/``), so it resolves to ``srcs/requirements/nginx``. Compose sends that folder to ``dockerd`` and finds the ``Dockerfile`` inside it by default, with no extra flag needed. Then Compose runs ``docker build``.

* ``image: service_name:1.0`` names and tags the image Compose builds. Without this line, Compose auto-names it something like ``srcs-service_name``, which breaks the same-name rule. The explicit tag matters too, otherwise without it it will be implicitly tagged ``latest``, and ``docker images`` would then show ``nginx:latest``, which based on the subject is banned.

* ``container_name: service_name`` it sets the name Docker gives the running container, so we can refer to it by name we chose in CLI as: ``docker exec -it service_name sh``, ``docker logs service_name`` or ``docker stop service_name``. Without it, Compose will generate a name from the project folder and service something as ``srcs-service_name-1``.

* ``ports: "portN:portN"`` the format is ``HOST:CONTAINER``, the left number is the port on our Host Machine, the right number is the port inside the container. Traffic hitting the host on 443 gets forwarded to the container's 443, where NGINX is listening. ``EXPOSE`` in the nginx Dockerfile was merely a documetnation, meanwhile ``ports:`` is what enforces it. we use quotes around the ``"port:port"`` because YAML can interpret unquoted numbers ``xx:yy`` as base-60 numbers in some edge cases, Compose doces recommend always quoting port mappings

* ``networks:`` **at the top level** declares the network itself. ``inception:`` is just the name we are giving it, what we will see when we do ``docker network ls``

* ``netowkrs:`` **inside the service** attaches that container to it. any other container that uses the same name, attaches itself into the same network, and the services can resolve each other by ``service_name``

## Makefile

```
all: up

up: docker compose -f srcs/docker-compose.yml up --build

down: docker compose -f srcs/docker-compose.yml down

clean: down

fclean: down
    docker system prune -af

re: fclean up

.PHOMY: all up down clean fclean re
```

``-f srcs/docker-compose.yml`` -- tells Docker Compose exactly which file to use, since the Makefile sits at the repo root while the compose file lives at ``srcs/`` without the -f, Compose looks for the compose file in the root directory.

``--build`` on ``up`` -- forces Compose to rebuild images before starting rather than silently reusing a stale cached image if we have edited a Dockerfile since the last run. Without it, ``up`` will happily start a container from an old image, and we could sit there confused why our changes aren't showing up.

``down`` -- stops and remove the containers and the network, but not volumes or images by default. That's the correct "***give me a clean slate to restart***" step fro iterating during development.

``fclean`` -- goes further, after tearing down, ``docker system prune -af`` removes all stopped containers, unused networks, and **all images not currently used by a container** (``-a`` includes images with no container at all. ``-f`` skips the confirmation prompt). This is a destructive command -- it prunes Docker-wide on our machine, for each container the image its built upon gets an ID Hash, so prune checks for the image ID if its referenced in the container object, if not it gets deleted, same goes for the network, the network has an ID, if any container is referenced in it, it does not get deleted until that container is down.

``re`` -- full rebuild from scratch: tear everything down, then bring it back up new.

``.PHONY`` -- tells ``make`` that these target names aren't actual files on disk. Without this, if a file literally named ``clean`` or ``up`` even existed in our repo root, ``make`` could get confused about wheter the target is "up to date" and skip running it. Doesnt affect functionality, but worth checking.
***
### How DNS Resolution works -- How its linked to ``/etc/hosts``

#### DNS resolution:

When we want to access a website through the browser the following chain occurs:

1. **Browser checks its own cache** -- has it resolved this domain lately ? if yes, skip everything below and reuse that IP
2. **OS-Level resolver gets asked** -- the browser hands the lookup to the OS networking stack
3. **The OS checks a local hosts file first** -- before ever going out to the network. This is ``/etc/hosts`` on Linux/MacOS (``C:\Windows\System32\drivers\etc\hosts`` on Windows). This file is literally a static, manually-editable list of ``IP <------> domain`` pairs -- the oldest, simpliest form of resoltion, predating DNS itself.
4. **Only if there's no match in ``/etc/hosts`` does the OS actually go out over the network -- asking a configuered DNS resolver (often router..), which recursively queries root servers -> TLD servers -> authoritative servers for that domain, eventually getting back an IP address.
5. That IP gets returned to the browser, which then opens a TCP connection to it.
***

#### Where ``/etc/hosts`` fits in -- and why it short-cirtuits everything

``/etc/hosts`` sits at **step 3 above**, checked before any real DNS query is even attempted. If our entry is there, resolution **stops immediately** the OS never contacts a DNS server at all for that domain. This is previsely why it works for ``ayel-bou.42.fr``, a domain that doesn't exist anywhere in real, public DNS: our machine never even tries ask the internet about it, because it find a local answer first and stops looking.

An entry looks like:

```
127.0.0.1       ayel-bou.42.fr
```

1. we type ``https://ayel-bou.42.fr`` into the browser.
2. Browser asks the OS to resolve ``ayel-bou.42.fr``.
3. OS reads ``/etc/hosts``, finds our line, returns ``127.0.0.1`` immediately -- no real DNS involved at all.
4. Browser now has an IP. it opens a TCP connection to ``127.0.0.1:443`` (443 because of ``https://``)
5. Docker's iptables rules intercept traffic hitting the host on 443 and forward it (DNAT) into the NGINX container's own 443.
6. NGINX receives the TCP connection, and the TLS handshake begins -- Client hello, NGINX responds with its cert, etc...
7. Once the handshake completes. NGINX reads the actual HTTP request, checks the ``Host`` header against ``server_name ayel-bou.42.fr;`` in our config -- since it matches -- serves the response from that ``server {}`` block.
***
### Secrets & Environment Variables

#### ``.env`` -- plain environment variables

These are **not secret at all**, mechanically speaking -- any process with access to the container, or ``docker inspect``, can read them in plaintext. They're meant for **non-sensetive configuration**: things like the database name, the username (not the password), the domain name, Convenient, simple, visible.

#### Docker secrets -- the actual protected mechanism

Docker secrets are fundamentally different in **how they're delivered into the container**. Instead of being envireonment variables (visible via ``docker inspect``, visible to any process that can read the container's environment, potentially logged accidentally), a secret gets mounted as a **file**, at ``/run/secrets/<secret_name>``, inside the container's filesystem -- readable only by processses actually running inside the container, and **not** exposed via ``docker inspect`` or environment listing at all. This is why our script does ``DB_PASS=$(cat /run/secrets/db_password)`` -- reading secrets is a **file read**, not an environment variable access.

#### Why both needed for different things

Non-sensitive config (database name, username) -> ``.env`` is fine, no real risk in it being visible. Actual passwords -> Docker secrets, specifically because environment variables have a real, documented attack surface (process listing, accidental logging, ``docker inspect`` output, crash dumps) that file-base secrets avoid.

#### Setting up the secrets files

Per subject's example the directory structure to store the secrets should go as follows:

```
secrets/
|--------> db_password.txt
|--------> db_root_password.txt
```

Each file contains just the **raw password text**, nothing else -- no ``KEY=value`` format, no quotes, just the password itself on one line.

#### Wiring secrets into ``docker-compose.yml``

Docker secrets need to be declared at the **top level** of the compose file, then referenced per-service:

```
secrets:
    db_password:
        file: ../secrets/db_password.txt
    db_root_password:
        file: ../secrets/db_root_password.txt
```

Then under the ``mariadb`` service:

```
service:
    mariadb:
        secrets:
            - db_password
            - db_root_password
```

This makes DOcker mount those files at ``/run/secrets/db_password`` and ``/run/secrets/db_root_password`` **inside that specific container**, automatically -- no manual volume mounting needed for this, it's dedicated mechanism.

#### Updating the entrypoint script

```
MYSQL_PASSWORD=$(cat /run/secrets/db_password)
MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
```

As for ``$(MYSQL_DATABASE)`` and ``${MYSQL_USER}`` stay as genuine envireonment variables (from ``.env`` passed via compose's ``environment:`` key), since those aren't sensitive.

``.gitignore``

```
secrets/
```