## Inception 42Docker

![Logo](Img/Inception.png)


Inception 42 Docker -- a 1337 (42 Network) school project designed not to only grasp the concepts of how **Docker** works but to practice & implement it in a good architectural way and design.

In this readme, i will go through these concepts from a security researching approach as well.

You can find the explanations of many keywords in this readme just by clicking on them.

Happy reading. and always remember:

***The conecpts written here, might be wrong or inaccurate therefore it's own you to dive deeper and find more accurate information than what can be provided here.***

***
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
***
