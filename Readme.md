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
### Security Perspective #1 - Container Escape

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
***