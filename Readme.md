# Inception 42Docker

![Logo](Img/Inception.png)


Inception 42 Docker -- a 1337 (42 Network) school project designed not to only grasp the concepts of how **Docker** works but to practice & implement it in a good architectural way and design.

In this readme, i will go through these concepts from a security researching approach as well.

You can find the explanations of many keywords in this readme just by clicking on them.

Happy reading. and always remember:

***The conecpts written here, might be wrong or inaccurate therefore it's own you to dive deeper and find more accurate information than what can be provided here.***


## Part One

When a programmer write an appliaction, the application depends on these several factos:

* A specific OS Version
* Specific libraries (glibc, openssl...)
* Specefic language runtime (Python 3.9, Node 18, PHP 8.1...)
* Specefic environment variables and config files
* Specific filesystem paths

When the programmer hands the application to another machine (colleague's laptop, staging server, a production VM...) -- something was always different.
A library mismatch, a missing dependency, a different kernel behavior, the breaks and nobody knows why.

The traditional solution was a **Virtual Machine**.
The programmer ships the whole OS alongside the app, it works -- but it's heavy, a VM carries an entire OS kernel, its own memeory management, its own hardware abstraction layer, spinning up a VM takes minutes and eats gigabytes of RAM just for overhead.

**Docker** came and said: ***What if we could isolate applications without the overhead of a full VM ?***

### The Origin Story

Docker was created by **Solomon Hykes** and released in **2013** as an open-source project by a company called **dotCLoud** (which later renamed itself to Docker Inc.).

THe timing wasn't accedental, three Linux kernel features had quierly matured by then that made Docker possible:

* **Namespaces** (2002, matured ~ 2006)
* **cgroups** -- Control Groups (Google engineers, merged into kernal 2.6.24 in 2008)
* **Uniion filesystems** -- specifically AUFS, later OVerlayFS

Docker didn't invent containerization, it packaged these existing kernel primitives into something developers could actually use, that was the **Genius**.

### Containers vs Virtual Machines

This distinction is fundamental and we need to get it as clear as a crystal.

```
VIRTUAL MACHINE                     CONTAINER
┌─────────────────────┐             ┌─────────────────────┐
│      Your App       │             │      Your App       │
├─────────────────────┤             ├─────────────────────┤
│   Guest OS Kernel   │             │  Container Runtime  │
├─────────────────────┤             ├─────────────────────┤
│    Hypervisor       │             │   Host OS Kernel    │
├─────────────────────┤             ├─────────────────────┤
│   Host OS Kernel    │             │      Hardware       │
├─────────────────────┤             └─────────────────────┘
│      Hardware       │
└─────────────────────┘
```

The critical difference: **Containers share the host kernel**, there is no second OS, the isolation is achieved through kernel features, not hardware emulation.

This means:

* Containers start in **miliseconds**, not minutes.
* A container uses **megabytes** of overhead, not gigabytes.
* But -- and this is where it gets interesting for secuity researchers, **The attack surface is different**.
***
### Security Perspective - Container Escape

Because containers share the host kernel, a vilnerability in the kernel or a misconfiguration in the container runtime can allow **container escape** -- an attacker inside a container breaking out to the host system.

Real Examples:

* CVE-2019-5736 (runc vulenrability) - Overwriting the host runc binary from inside a container
* Dirty COW (CVE-2016-5195) - Kernel exploit usable from inside containers
* Priveleged containers - running a container with ``--privileged`` basically disables isolation

In our project **Inception**, this is exactly why the project forbids ``network: host`` -- it removes network namespace isolation entirely, meaning a process inside the container sees the host's network stack directly, that's a security disaster.
***

### The Three Linux Kernel Primitives

Let's go one level deeper because understanding these will make everything else click.

#### Namespaces -- isolation

A namespace wraps a global system resource and makes it appear to processes inside the namespace as if they have their own isolated instance of that resource.

Docker uses 7 types of namespaces

Each Namespace and what it **isolates**
* ``pid``: Process IDs -- container processes can't see host processes
* ``net``: Network interface, routing tables, firewall rules
* ``mnt``: Filesystem mount points
* ``uts``: Hostname and domain name
* ``ipc``: Inter-process communication (shared memory, semaphores)
* ``user``: User and group IDs
* ``cgroups``: cgroup root directory

When **NGNIX** container runs, it thinks it's the only process on the machine, it has its own PID 1, it has its own network interface, it has own filesystem root.
This is all namespaces at work.

#### cgroups -- Resource Control

Control Group limit, account for, and isolate the resouce usage of process group. CPU, memory, disk I/O, network bandwidth

Without cgroups, one container could consume all the host's memory and crash everything else, cgroups are what allow Docker to say "***This container gets max 512MB RAM and 0.5 CPU cores***".

In your project, this is relevant because if MariaDB container has a memory leak, cgroups prevent it from killing the NGNIX container.

#### Union Filesystems -- Layered Images

This is the clever part that makes Docker images efficient.

A Docker image is built in **layers**, each instruction in a ``Dockerfile`` creates a new layer, layers are **read-only** and **shared** between containers.

```
┌─────────────────────────┐  ← Your app code (read-write layer, per container)
├─────────────────────────┤  ← php-fpm config (read-only layer)
├─────────────────────────┤  ← PHP installed (read-only layer)
├─────────────────────────┤  ← Debian base (read-only layer)
└─────────────────────────┘
```

When you run a container, Docker adds a thin **wriable layer** on top.
if two containers use the same base image, they share those read-only layers -- no duplication, this is OverlayFS doing the work.

This also means: **Dockerfile layer order matters**, put things that change rarely (base OS, package installs) early, Put things that change often (app config) late, this makes rebuilds fast because Docker caches unchanged layers.

## Part Two

### Docker Architecture -- The Three Players

When we type ``docker run ngnix`` in the terminal, we are not directly creating a container, we are talking to a system made of three distinct layers, each with a specific responsibility.

Most people think Docker is one thing, it's not, it's a **Client-server architecture**.

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│  Docker CLI  │ ──────► │Docker Daemon │ ──────► │  containerd  │
│  (client)    │  REST   │  (dockerd)   │  gRPC   │  + runc      │
└──────────────┘   API   └──────────────┘         └──────────────┘
   You type here      Receives & decides          Actually creates
                      what to do                  the container
```

#### **The Docker CLI**

This is just a **Command line client**, when we type ``docker run``, the CLI translates that into an **HTTP Request** and sends it to the Docker Daemon over a REST API, the CLI itself has zero power -- it's just a messenger.

#### **The Docker Daemon**

This is the **Brain**, it's a background process that listens for requests from the CLI, manages images, networks, volumes, and tells the container runtime what to create, it's what's actually running when Docker is "running" on the machine.

#### **containerd + runc**

These are the **hands**, containerd manages the container lifecycle (start, stop, pause), runc is the low level tool that actually calls the Linux kernel -- it sets up the namespaces, the cgroups, the filesystem layers we mentioned in the **Part One**, and spawns the process.

This is why **CVE-2019-5736** was so devastating -- **runc** is the piece touching the kernel directly, exploiting it meant escaping to the host.

### Images vs Containers -- The Precise Difference

Most people say "an image is a blueprint, a container is a running instance" and stop there, that's correct but shallow...

#### WHat is a Docker image ?

An image is a **read-only, layered filesystem snapshot** plus some metadata.

That's it, There is no process running, There is no "life" in it, it just sits there on disk as a stack of layers we mentioned in **Part One** -- **OverlayFS** layers, each one a diff on top of the previous.

When we build this Dockerfile

```
FROM debian:bulleye-slim        # Layer 1 - base filesystem
RUN apt-get install -y ngnix        # Layer 2 - ngnix added on top
COPY ngnix.conf /etc/ngnix/         # Layer 3 - your config added on top 
```

We get an image with **3 layers**, all read-only, all stored on disk, No process, No network, Nothing alive.

#### What is a Container ?

A container is what happend when Docker **takes an image and brings it to life**.

Specifically Docker does three things:

```
        Image (read-only layers)
                    +
  Writable layer (new, empty, per container)
                    +
Linux Kernel primitives (namespaces + cgroups)
                    =
                Container
```

The writable layer is critical -- it's why **two containers from the same image are completely independent**. They share the read-only layers underneath (no duplication on disk), but each has its own writable layer on top. One container can't touch the other's writes.

#### The Lifecycle

```
Dockerfile -- build --> Image --run --> Conatiner
                          |                 |
                    stored on disk    alive, has PID 1
                    no process         has network
                    shareable        has writable layer
                    on DockerHub   dies when PID 1 dies
```

THat last point is crucial for the **Inception** Project -- **a container lives and dies with its PID 1**. The moment PID 1 exits, the container stops, this is exactly why ``tail -f`` and ``sleep infinity`` are forbidden hacks -- they keey PID 1 alive artificially without actually running the service properly.
***

#### How is this connceted to the Inception Projcet

In the project, we will have to create **3 Dockerfiles** producing **3 Images** producing **3 containers**:

* ``ngnix`` image -> ``ngnix`` container
* ``wordpress`` image -> ``wordpress`` container
* ``mariadb`` image -> ``mariadb`` container

Each container gets its won writable layer, its own namespaces, its own PID 1 that must be a **real daemon** running in the foreground.
***

### The Docker Socket -- ``/var/run/docker.sock``

#### What is it ?
When the Docker Daemon (``dockerd``) starts, it creates a **UNIX sokcet** at ``/var/run/dokcer.sock/``.

A Unix socket is just a file that acts as a communication endpoint -- instead of talking over network, processes talk to each other through a file on disk.

Remember from the architecture: the Docker CLI talks to Daemon via a REST API, that REST API travels through this socket file.

so essentially:
``Docker CLI ----- HTTP Requests -----> /var/run/docker.sock -----> dockerd``

#### Why Does it Exist ?

Because the Daemon needs to receive commands from somewhere, the socket is the **front door** to the Docker Daemon, Whover can write to that socket can tell the Daemon to do anything -- Creates containers, Delete Containers, pull images, inspcet running containers.

Anything.

From a **Security StandPoint**, mounting the **Docker Socket** inside of a container, is a critical vulenrability, it will give the attacker the power to talk directly to the Docker Daemon ``dockerd`` through that socket, Create **new container**, and mount the **entire host filesystem at ``/host`` and then the attacker will have full read/write access to the host filesystem from inside that new container.

**That's a full container escape**. Game over, Root on the host.

#### The Privilege Reality

The Docker Daemon runs as **root**, the socket is owned by root, Therefore:

``Access to docker.sock = root on host``.

This is why from a security research POV, finding a web application that has access to the Docker Socket -- even indirectly -- is **critical severity finding**, it's essentially instant root.

#### How this Connects to Inception Project

The inception project does not expose the Docker Socket to containers -- and now we know and understand exactly why that would be insane.

But more importantly, our NGNIX container is the **only entrypoint** on port 443, think about what happens if someone finds an SSRF vulenrabilty in our WordPress container:

``Attacker ---> Wordpress SSRF --> Internal DOcker network --> MariaDB directly``

The Docker network isolation is our second line of defense, this is why the project forces us to use a **custom bridge network** -- containers can only talk to each other through defined paths, not freely across the host network.

## Part Three

### Docker Networking -- How Containers Find Each Other

Most people think networking is just "***containers talk to each other***", the reality is more interesting -- and more security-relevant.

#### The Problem Without Docker Networking

Remember from **Part One** -- each container gets its own **Network Namespace**, its own network interfaces, its own routing table and its own firewall rules.

This means by default, **containers are completely blind to each other**, NGNIX can't reach WordPress, WordPress can't reach MariaDB, They're isolated islands.

Docker Networking is the solution -- it's how you build **controlled bridges** between those islands.

#### The Bridge Network

When Docker installs, it creates a default network called ``docker0`` -- a **Virtual Bridge** on the host.

Think of a bridge network like a **virtual switch** inside the machine:

```
Host Machine
┌─────────────────────────────────────────────────┐
│                                                 │
│         docker0 (virtual switch)                │
│         172.17.0.1                              │
│        /          \          \                  │
│   eth0(nginx)  eth0(wp)  eth0(mariadb)          │
│   172.17.0.2   172.17.0.3  172.17.0.4           │
│                                                 │
└─────────────────────────────────────────────────┘
```

Each container gets a virtual network interface connected to this bridge, they can now talk to each other through it.

#### Default vs Custom Bridge -- This is Critical

Docker gives you a default bridge network automatically, but in the **Inception** Project, we are **forced to create a custom one** in our ``docker-compose.yml`` file, since with the custom one, we are able to configure our DNS to container names meanwhile the Default one uses IPs only, and in terms of isolation, all containers join the default one, while we can set a defined containers to join our custom network bridge.
Also, the security is much stronger.

The big one is **DNS**, on a custom bridge network, Docker runs an internal DNS Server, this means NGNIX continer can reach WordPress simply by using ``wordpress`` as the hostname -- Docker resolves it automatically to the right IP.

In terms of ``docker-compose.yml`` file, this would look like:

```
networks:
    inception_network:
        driver: bridge
```

And every service declares it belongs to the network and Docker handles the rest.

#### How The Traffic Actually Flows in **Inception**

```
    Internet
        │
        ▼
    Port 443 (host)
        │
        ▼ iptables NAT rule (Docker creates this automatically)
        │
        ▼
    NGINX container (only public entrypoint)
        │
        ▼ internal network (wordpress:9000)
        │
        ▼
    WordPress + php-fpm container
        │
        ▼ internal network (mariadb:3306)
        │
        ▼
    MariaDB container
```

Notice -- only NGNIX is reachable from the outside, WordPress and MariaDB are **completely invisble** to the internet, they only speak to each other over the internal Docker network.

### Docker Volumes -- How Data Persists

Remember the writable layer from **Part One** ? The thin layer on top of the read-only image layers that each container gets ?

The problem with it -- **it dies with the container**.

When a container stops or gets removed, its writable layer is gone, forever.
For stateless apps like **NGNIX** -- That's fine, the config is baked into the image, nothing needs to persist.

But for **MariaDB**? The entire WordPress Database lives in that writable layer, every post, every user, every setting, container restarts, data is gone, that's catastrophic.

Docker **Volumes** solve this.

#### What is Volume ?

A volume is **a directory that lives on the host filesystem**, completely outside the container's lifecycle, Docker manage it, mounts it into the container at a specific path, and it **persists regardless of what happens to the container**.

```
Host filesystem                    Container
┌─────────────────────┐           ┌─────────────────────┐
│ /var/lib/docker/    │           │                     │
│ volumes/            │           │  /var/lib/mysql/    │
│ wp_database_volume/ │◄─────────►│  (MariaDB data)     │
│ _data/              │  mounted  │                     │
└─────────────────────┘           └─────────────────────┘
```

The container writes to ``/var/lib/mysql/`` thinking it's writing locally -- but it's actually writing to the host, container dies, data persists and stays.

#### Three Types of Storage in Docker

```
---------------------------------------------------------------------------------------------------
Type                  | What it is                      | Persists ?                | Inception ? |
---------------------------------------------------------------------------------------------------
* Writable Layer      | Per-container temp storage      | Dies with the container   |  No         |
---------------------------------------------------------------------------------------------------
* Named Volume        | Docker-managed host directory   | Yes                       | Required    |
---------------------------------------------------------------------------------------------------
* Bind Mount          | Direct host path mounted in     | yes                       | Forbidden   |
---------------------------------------------------------------------------------------------------
```

#### Named Volumes vs Bind Mounts -- Why **Inception** Forbids Bind Mounts

**Bind mount** -- you specify an exact host path:

```
volumes:
    - /home/user/data:/var/lib/myswl    # bind mount
```

**Named Volume** -- Docker manages the path:

```
volumes:
    - wp_database_volume:/var/lib/myswl     # named volume
```

The difference:

* Bind mounts give the container direct access to the host filesystem -- security risk, portability risk.
* Named Volumes are Docker-managed -- isolated, portable and safer.

This is exactly why inception forbids bind mounts, a misconfigured bind mount could expose sensitive host directories directly into a container.

#### Our Two **Inception** Volumes

```
volumes:
    wp_database_volume:     # MariaDB data lives here
    wp_website_files_volumes:       # WordPress files live here
```

Both physically stored on the host at ``/home/<login>/data/`` -- but accessed through Docker's volume management layer, not directly.

This also means WordPress and NGNIX share ``wp_website_files_volume`` -- NGNIX needs to serve statis files that WordPress generates, Two containers, one volume, both have access.

### docker-compose -- Orchestrating Everything Together

We understand that:

* **Namespaces + cgroups** -- How isolation works
* **Images + containers** -- What runs and how
* **Networking** -- How containers find each other
* **Volumes** -- How data persists.

**docker-compose is where all of it comes together in one file.**

#### What is dokcer-compose ?

It's a tool that reads a ``docker-compose.yml`` file and:

* Builds all the images from their Dockerfiles
* Creates the network
* Creates the volumes
* Starts all containers in the right order with the right configuration

Instead of typing 10 ``docker run`` commands with 15 flags each -- one command does everything

``dokcer-compose up --build``

#### The anatomy of a docker-compose.yml

Let's read a simplifed version of what the **Inception** file will look like, section by section

```
version: '3.8'

services:                                   # The containers
    ngnix:
        build: ./requirements/ngnix         # path to Dockerfile
        container_name: ngnix
        ports:
            - "443:443"                     # host:container
        volumes:
            -wp_website_files_volume:/var/www/html
        networks:
            -inception_network
        restart: always                     # crash policy

    wordpress:
        build: ./requirements/wordpress
        container_name: wordpress
        volumes:
            - wp_website_files_volume:/var/www/html
        networks:
            - inception_network
        restart: always
        depends_on:
            - mariadb                       # start order

networks:                                   # define the custom network bridge
    inception_network:
        driver: bridge

volumes:                                    # declare named volumes
    wp_database_volume:
        driver: lovcl
        driver_opts:
            type: none
            o: bind
            device: /home/<login>/data/mysql
    wp_webstie_files_volume:
        driver: local
        drivre_opts:
            type: none
            o: bind
            device: /home/<login>/data/wordpress
```

#### Breaking Down The Key Directives

* ``build`` -- points to the directory countaining the Dockerfile, docker-compose builds the image from scratch, no DockerHub
* ``ports`` -- maps host port to container port via iptable NAT rules we discussed in networking, Only NGNIX exposes a port -- WordPress and MariaDB have no port mapping, they're invisible to the outside world.
* ``restart: alwasy`` -- tells Docker to restart the container automatically if it crashes, this is how **Inception** satisfies the crash policy requirement, under the hood Docker monitors PID 1 -- if PID 1 exits, Docker restart the container.
* ``depends_on`` -- controls start order, WordPress depend on MariaDB being up before it starts, NGNIX depends on WordPress.
* ``networks`` -- every service declares membership in ``inception_network``, this is what enables container name DNS resolution -- ``wordpress`` resolves to the WordPress container's IP automatically.
* ``volumes`` -- mounts the named volumes into the container at the specified path.

## Part Four

### Dockerfile Internals -- Every Instruction Explained

A Dockerfile is a **sequential list of instructions** that Docker executes top to bottom to build an image. each instruction creates a new layer.

#### The instructions

``FROM``

```
FROM debian:bullseye-slim
```

This is always the first instruction, it defines the **base layer** -- the starting filesystem the image builds on top of.

Every subsequent instruction adds a lyer on top of this base.

This is why inceotion forbids ``:latest``, since it is a floating tag that changes silently, ``bullseye-slim`` is pinned, you know exactly what you're getting every single build.

``slim`` variants strip out unnecessary packages, smaller attack surface, smaller image size.

* ``RUN``

```
RUN apt-get update && apt-get install -y mariadb-server
```

Execute a shell command during the build and commits the result as a new layer.

Two critical things:

**Why the use of ``&&`` chaining matters:

```
# Bad - two seperate layers
RUN apt-get update
RUN apt-get install -y mariadb-server

# Good - one layer
RUN apt-get update && apt-get install -y mariadb-server
```

Each ``RUN`` is a layer, if we update one layer and install in the next, Docker can cache the update layer and use a stale package list, chain then -- One ``RUN`` layer, always fresh.

``-y`` flag -- auto-confirms prompts, without it the build hangs waiting for user input that never comes.

* ``COPY``

```
COPY conf/my.cnf /etc/mysql/my.cnf
```

Copies files from the **build context** (the project directory) into the image layer.

This is how the configuration files get baked into the image -- the custom MariaDB config, NGNIX config, php-fpm config.

* ``ENV``

```
ENV MYSQL_DATABASE=wordpress
```

Sets an **envuronment variable** that persists into the running container.

But -- and this is critical for the project, we should never put passwords in ENV inside a Dockerfile, ENV values are baked into the image layer and visible to anyone who runs ``docker inspect`` on the image

```
docker inspect myimage | grep PASSWORD
# exposes the password to anyone with Docker access
```

Secrets come from outside the imgae -- through ``.env`` files and Docker secrets, we will cover that later.

* ``EXPOSE``

```
EXPOSE 3306
```

Documents which port the container listens on, that's all it does -- it's metadata, not an actual firewall rule on port mapping.

The actual port publishing happens in ``docker-compose.yml`` with the ``ports:`` directive, EXPOSE is just a signal to whoever reads the Dockerfile.

* ``ENTRYPOINT`` vs ``CMD``

This is where most people get confused -- these two work together and the distinction metters deeply for the PID 1 understanding.

```
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["mysqld"]
```

``ENTRYPOINT`` -- the executable that always runs, cannot be overridden easily, this is the initialization script.

``CMD`` -- the default argument passed to ENTRYPOINT, can be overridden at runtime.

So the above means: always run ``dokcer-entrypoint.sh``, and pass ``mysqld`` as the argument to it.

The entrypoint script initialize the database, then calls ``exec mysqld`` -- handing off the real MariaDB daemon as PID 1.

Which brings us to the most important rule:

#### The PID 1 Rule -- ``exec`` form vs ``shell`` form

There are two ways to write ENTRYPOINT and CMD:

```
# shell form -- WRONG for PID 1
ENTRYPOINT docker-entrypoint.sh

# Exec form -- CORRECT for PID 1
ENTRYPOINT ["docker-entrypoint.sh"]
```

**Shell form** spawns ``/bin/sh -c`` as PID 1, which then spawns our process as a child.
Our actual process is PID 2, singals like ``SIGTERM`` sent to PID 1 never reach our process -- graceful shutdown is impossible.
**Exec form** runs our process directly as PID 1, signals reach it correctly, this is always what we want.

#### Layer Order -- Why it Matters for Build Speed

```
FROM debian:bullseye-slim           # changes never -> bottom
RUN apt-get install -y mariadb      # changes rarely -> early
COPY conf/my.cnf /etc/mysql/        # changes sometimes -> middle
COPY tools/entrypoint.sh /          # changes often -> late
```

Docker caches every layer, if layer 3 changes, layers 1 and 2 are served from cache instantly -- only layers 3 and beyond rebuild

Put stable things early, volatile things late, this is the difference between a 30 second rebuild and a 5 minute rebuild.

***
### MariaDB Container -- Building the Database Foundation

MariaDB is the first container we build because everything depends on it, WordPress needs a running database before it can do anything, we build bottom up.

#### What the MariaDB Container Needs to Do

Before we write a single line, let's think about what this container is respobsible for:

* Install MariaDB server
* Initize the database on first run
* Create the WordPress database
* Create two users -- one admin, one regular WordPress user
* Secure the installation
* Start MariaDB daemon as PID 1
***

#### The Dockerfile

```
FROM debian:bullseye-slim

# Install MariaDB
RUN apt-get update && apt-get install -y mariadb && rm -rf /var/lib/apt/lists/*

# Copy custom MariaDB config
COPY conf/my.cnf /etc/myswl/my.cnf

# Copy entrypoint script
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Document the port
EXPOSE 3306

ENTRYPOINT ["/entrypoint.sh"]
CMD ["mysqld"]
```

Note: ``rm -rf /var/lib/apt/lists/*`` -- deletes the package manager cache after installing, this is a layer cleanup technique -- apt downloads package lists to know what's available, we don't need them after installation, removing them shrinks the image layer.

**No Password anywhere** -- the Dockerfile is clean, Creds come from the outside.
***

#### The Configuration File -- ``conf/my.cnf``

```
[mysqld]
user                = mysql
datadir             = /run/mysqld/
socket              = /run/mysqld/mysqld.sock
bind-address        = 0.0.0.0
port                = 3306

[client]
socket              = /run/mysqld/mysqld.sock
```

``bind-address = 0.0.0.0`` -- tells MariaDB to accept connections on all network interfaces inside the container, without this it only listens on localhost -- WordPress couldn't reach it.

``socket`` -- the Unix socket file MariaDB uses for local connections, both ``[mysqld]`` and ``[client]`` must agree on the path.
***

#### Credentials -- How Secrets Work in Inception

This is where Inception's security model becomes concrete.

We have three files in our ``secrets/`` directory:

```
secrets/
-- db_password.txt           <-- WordPress user password
-- db_root_password.txt      <-- MariaDB root password
```

in ``dokcer-compose.yml`` we declare them:

```
secrets:
    db_password:
        file: ../secrets/db_password.txt
    db_root_password:
        files: ../secrets/db_root_password.txt

services
    mariadb:
        secrets:
            - db_password
            - db_root_password
        environment:
            MYSQL_DATABASE: ${MYSQL_DATABSE}
            MYSQL_USER: ${MYSQL_USER}
```

Docker mounts secrets as **files** inside the container at ``/run/secrets/``

```
/run/secrets/db_password
/run/secrtes/db_root_password
```

Our entrypoint script **reads** the password from the file:

```
DB_PASSWORD=$(cat /run/secrets/db_password)
```

This means passwords **never exist as environment vairables**, never appear in ``docker inspect``, never get logged, they exist only as files readable by the process that needs them.
***

#### The Entrypoint Script

This is where everything we've learned comes together, the entrypoint script is the **brain of the container** -- it runs first, sets everything up, then hands control to the real daemon as PID 1.

* What it needs to do :

```
1. Read credentials from /run/secrets/
2. Start MariaDb temporarily (for initialization)
3. Create the datababase
4. Create the users
5. Set passwords
6. Shut down the temporary MariaDB instance
7. Hand off to the real mysqld as PID 1
```

#### The Script

```
#!/bin/sh

# Read credentials from Docker secrets
DB_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)
DB_PASSWORD=$(cat /run/secrets/db_password)

# Create the socket directory
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld
chown -R mysql:mysql /var/lib/mysql

# Initialize the database directory if first run
if [ ! -d "/var/lib/mysql/mysql" ]; then
    mysql_install_db --user=mysql --datadir=/var/lib/mysql
fi

# Start MariaDB temporarily in background for setup
mysqld --user=mysql &
TEMP_PID=$!

# Wait for MariaDB to be ready
until mysqladmin ping --silent; do
    sleep 1
done

# Run setup queries
mysql -u root << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PREVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
DELETE FROM mysql.user WHERE USER='';
DROP DATABASE IF EXISTS test;
FLUSH PREVILEGES;
EOF

# Shut down the temporary instance
kill $TEMP_PID
wait $TEMP_PID

# Hand off to the real daemon as PID 1
exec "$@"
```

#### Script -- Step by Step Explanation

* ``#!/bin/sh``

This is a **shebang**, when the kernel executes a script file, it reads the first two bytes, if they're ``#!``, the kernel reads the rest of the line as the interpreter to use, then calls that interpreter with the script as its argument

for example when Docker runs ``/init.sh`` the kernel actually executes ``/bin/sh /init.sh``, and ``/bin/sh`` is chosen over ``/bin/bash`` deliberately -- Alpine Linux doesn't ship bash by default yet ``sh`` is always present, portable scripts use ``sh``.
***

* Socket Directory Setup

```
mkdir -p /run/mysql
chown -R mysql:mysql /run/mysqld
chown -R mysql:mysql /var/lib/mysql
```

``mkdir -p /run/mysql`` -- creates the directory if it doesn't exist, ``-p`` means "No error if it already exists, create parent directories as needed."

MariaDB communicates locally via Unix Socket file at ``/run/mysqld/mysqld.sock``, before MariaDB create that file, the directory must exist.

``chown -R mysql:mysql`` -- changes ownership recursively, ``mysql:mysql`` means user ``mysql``, MariaDB runds as the ``mysql`` user (not root) for security -- a compromised MariaDB process should not have root privileges on the container filesystem, but it needs to own its socket directory and data directory to read/write them.

The ``-R`` flag means revursive -- applies to everything inside ``/var/lib/mysql/`` too, where the actual databse files live

**Security Angle**: Running a daemon as a non-root user inside a container is defense in depth, if MariaDb is exploited, the attacker has UID ``mysql`` inside the container -- not root, combined with the mount namespace, they still can't touch the host filesystem.

* First-Run Initialization