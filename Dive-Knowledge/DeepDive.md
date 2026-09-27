# DeepDive

***This readme is dedicated to explain the keywords used in the Base Readme of this project***.
***

### Overhead

In simple words, the **Overhead** are the resources consumed by the infrastructure itself, not the application.

and as an introduction let's take these examples:

* A **VM** is like hiring a moving truck, with a full-time driver, fuel costs, insurance...all that to move and carry a book, the truck exists whether the book is being read or not.

* A **Container** is like putting the book in a padded envelope, the evelope is almost nothing, weights nothing in comparision to the actual book itself.

#### VM Overhead

When we boot a VM, before the app runs a single code, we have already paid the price of:

* The HyperVisor:

A hypervisor (VMware, VirtualBox...) intercepts every hardware call from the guest OS and translates it, every time the guest OS asks "give me memory" or "write to disk" the hypervisor catches that call, validates it, and passes it down, this translation is CPU cycles spent, not on the app.

* The Guest Kernel

A full second linux kernel lives inside the VM, That kernel needs RAM just to exist -- before the app touches a single byte, a minimal linux kernel idle footprint is around 50-100MB just for the kernel itself, then kernel threads, kernel buggers, kernel page tables -- all RAM, which the app does not use.

* Virtual Hardware Emulation

The VM has a fake NIC, a fake disk controller, a fake GPU, the hypervisor pretendsd to be hardware, the guest OS talks to fake hardware which the hypervisor then translates to real hardware calls, two translation layers on every I/O operation.

* Boot time

The guest kernel runs its full booting sequence ``init``, daemons starting, filesystem checks, 30 seconds to 2 minutes minimum, every boot.

* Static Memory Allocation

When we set the VM to get 2GB RAM, those 2GB are reserved -- even when the VM is idle, the host can't use that memory for anything else.

#### Docker/Container Overhead

When a container starts

* No second kernel, the host kernel is reused, zero memeory for a second kernel is used.
* No HyperVisor, system calls from inside the container go directly to the host kernel, just with namespace/cgroup wrappers checked, essentially zero translation overhead.
* No boot sequence, the container starts by executing one process (PID 1), that's it, miliseconds.
* Dynamic memory, the container only holds memory for the processes actually running inside it, no reservation (unless we explicitly set limits with cgroup).

The oeverhead is essentially just the namespaces and cgroup data structures the kernel maintains, measured in kilobytes, not gigabytes.
***

### Namespaces -- Deep Dive

At the kernel level, a namespace is a **struct** -- a data structure -- that wraps a view of a global resource, when a process is created, it inherits the namespaces of its parent, when a new namespace is created (via the ``unshare()`` or ``clone()`` syscall), the process gets its own isolated view of that resource.

The key syscalls:

* ``clone(CLONE_NEW*)``: creates a new process in a new namespace.
* ``unshare(CLONE_NEW*)``: detaches the current process into a new namespace.
* ``setns()``: attaches a process to an existing namespace (this is how ``docker exec`` works -- it joins a running container's namespaces)

#### PID Namespace

Without PID namespaces, all processes on the system share on flat PID, Process 1 is ``init``/``systemd``, Process 2 is something the kernel spawned, and so on.

With a PID namespace, a new independent PID table is created, the first process inside that namespace gets PID 1 -- from its own perspective, but from the host's persepective, that process might be PID 1111.

This is why inside a Docker container, if you run ``ps aux``, you see PID 1 as your process -- ``ngnix``, ``php-fpm``, whatever, but on the host, that process has a completely different PID.

The critical implication: **PID 1** inside the container is special, in a real linux system, PID 1 (``init``/``systemd``) is responsible for reaping orphaned child processes, when a child process dies and the parent does not call ``wait()``, the child becomes a zombie, PID 1 adopts and reaps these, if the container's PID ` does not handle signals properly or does not reap zombies, we accumulate zombie processes inside the container, this is why the project forbids ``tail -f`` as the entrypoint, it's an irresponsible PID 1.

#### Network Namespace (net)

This is the most important one for inception and web security

Each network namespace has its own:

* Network interfaces (including a loopback ``lo``)
* Routing tables
* Firewall Rules (iptables/nftables)
* Socket table -- all open TCP/UDP connections
* Port Bindings

When Docker creates a container, it creates a new network namespace and then create a **veth pair** a virtual ethernet cable with two ends, one end ``eth0`` is placed inside the container's network namespace, the other end is attacher to a **Docker bridge** (``dokcer0`` or our custom bridge) in the host's network namespace.

```
Host network namespace             Container network namespace
┌────────────────────────┐        ┌──────────────────────────┐
│  docker0 (bridge)      │        │  eth0 (container NIC)    │
│  172.17.0.1            │◄──────►│  172.17.0.2              │
│                        │ veth   │                          │
│  iptables rules        │  pair  │  its own routing table   │
│  (port forwarding)     │        │  its own firewall        │
└────────────────────────┘        └──────────────────────────┘
```

Port publishing (e.g ``443:443``) works via iptables NAT rules on the host -- the host's iptables intercepts incoming traffic on port 443 and DNAT's it to the container's IP on port 443.

Why ``network: host`` is catastrophically dangerous:
When you use ``network: host``, Docker skips creating a network namespace entirely, the container process seees the host's network neamespace -- the real NICs, the real routing table, the real iptable, if an attacker compromises ythe containerized app, they can direclty bind to host pots, sniff host network traffic, and modify host firewall rules, the isolation is completely gone, this is why the project forbids it.

#### Mount Namespace (mnt)

This namespace isolates the **Filesystem Tree**, each process inside a container sees its own root filesystem (``/``), which is constructed from the UNion Filesystem layers (OverlayFS, explained below)

The key syscall is ``pivot_root()`` or ``chroot()``, when docker starts a container, it:

* Sets up the layered filesystem as a directory on the host.
* Calls ``pivot_root()`` to make that directory the container's ``/``.
* Creates a new mount namespace so the container's mount points are isolated

The container can mount and unmount filesystems inside the namespace without affecting the host.
***

#### UTS Namespace

UTS stands for UNIX-Time-sharing System, this namespace isolates just two things: **hostname** and **NIS domain name**.

Without this, every container on the host would share the host's hostname, with it, the NGNIX container can have hostname ``ngnix``, the WordPress container can have hostname ``wordpress``.

It's simple but necessary for applications that use the hostname to identify themselves (logging, clustering software...).
***

#### IPC Namespace

IPC: Inter-Process Communication, this namespace isolates:

* System V shared memory segements
* System V semaphores
* System V message queues
* POSIX message queues

These are mechanims that allow processes on the same system to communicate through kernel-managed shared memeory regions, without IPC namespace isolation, a process inside a container could attach to shared memeory segements used by the host processes or containers, reading or corrupting data.
***

###

#### User Namespace

This one is the most powerful and the most complex.

It allows mapping user IDs inside the namespace to different user IDs outside.
Specially: a process can be UID 0 (root) inside the container but map to an unprivileged UID (example: 32424) on the host.

This means, if a process escapes the container, it's an unprivileged user on the host -- not root, this is the ideal security model.

However, historically Docker did not enable user namespaces by default because they interact complexly with other namespaces and capabilities, Docker has a "userns-remap" feature to enable this, most default Docker installs still run containers as root on the host, meaning a container escape equals root on host, this is a massive security concern and an underappreciated fact.
***

#### cgroup Namespace

The newset namespace **(Linux 4.6, 2016)**, it isolates the view of the cgroup hierarchy, without it, a process inside a container could see the host's full cgroup tree -- leaking information about what other containers/processes exist and their resource allocations, with it, the container sees only its own sub-tree, rooted at ``/``.
***

### cgroups -- Resource Control -- Deep Dive

**cgroups** (Control Groups) are a kernel feature for grouping processes and imposing limits and accounting on their resource usage.

#### **The Architecture**

cgroups are exposed to userspace as a **virtual filesystem**, mounted at ``/sys/fs/cgroup``, you configure cgroups by writing to files in this filesystem, it's elegant: the kernel exposes its internal resource accounting as a file tree.

```
/sys/fs/cgroup/
├── memory/
│   ├── docker/
│   │   ├── <container_id>/
│   │   │   ├── memory.limit_in_bytes    ← write a number here to set the limit
│   │   │   ├── memory.usage_in_bytes    ← read this to see current usage
│   │   │   └── tasks                   ← list of PIDs in this cgroup
```

When Docker creates a container, it creates a subdirectory under ``/sys/fs/cgroup`` for each resource controller, writes the container's PID into the ``tasks`` file, and sets the limits.

##### The Controllers (Subsystems)

Each type of resource is managed by a controller:

**memory controller**:

* ``memory.limit_in_bytes`` -- hard RAM limit, if the process tries to allocate beyond this, it gets OOM-Killed (Out Of Memory killed)
* ``memory.soft_limit_in_bytes`` -- soft limit, the kernel will try to reclaim memory under memeory pressure, but won't hard-kill
* ``memory.swappiness`` -- how aggressively to swap to disk
* ``memory.oom_control`` -- configure OOM Killer behavior

**cpu controller**:

* ``cpu.shares`` -- relative weight, if container A has 1024 shares and container B has 512, container A gets twice as much CPU when both are competing.
* ``cpu.cfs_period_us`` and ``cpu.cfs_quota_us`` -- absolute CPU time limit, ``period=100000`` (100ms) and ``quota=50000`` means "max 50% of one CPU core"

**blkio controller**:

* ``blkio.throttle.read_bps_device`` -- limit disk read speed in bytes per second
* ``blkio.throttle.write_bps_device`` -- limit disk write speed

**cpuset controller**:

* ``cpuset.cpus`` -- pin the container to specific CPU cores, example "0.1" means use cores 0 and 1
* ``cpuset.mems -- for NUMA systems, which memory nodes to use

**pids controller**:

* ``pids.max`` -- maximum number of processes/threads, prevents fork bombs
***

### cgroups v1 vs cgroups v2

**cgroups v1** (the original ~ 2008) - Each resource controller is a seperate filesystem hierarchy, you mount ``memory``, ``cpu``, ``blkio`` seperately, a process can be in different groups for different controllers -- its memory might be controlled by group A while its CPU is controlled by groupd B, this became a mess.

**cgroups v2** (Introduced Linux 4.5, ~2016, became default in many distros ~ 2020-2021) - a **univied hierarchy**, one filesystem, all controllers together, a process belongs to exactly one cgroup, and all resources accounting is done there, much cleaner.

Modern Docker (and systemd) primarily use **cgroups v2**, when you run a Docker container on a modern Ubuntu/Debian system, cgroups v2 is what's actually enforcing those resource limits.

**Security perspective** - cgroups escape:

A classic attack vector is a container that has the cgroup filesystem from the host mounted inside it, if an attacker can write to the host's ``release_agent`` cgroup file (a legacy cgroup v1 feature), they can make the host kernel execute an arbitrary command with root privileges when a cgroup becomes empty, this is CVE-2022-0492 and the basis of several container escape techniques, Felix Wihelm's "cgroup container breakout" is a good resource.
***

### AUFS and OverlayFS - Union Filesystem

Docker images are built in layers, we need a filesystem that can:

* Present multiple layers as if they are one unified system
* Allow writes to go to a new layer without modifying the lower read-only layers
* Share read-only layers between multiple containers (no duplication)

This is what a **Union filesystem** does: it takes multiple directories (layers) and presents them as a single merged view
***

### AUFS -- Another Union Filesystem (the original)

AUFS was the original union filesystem Docker used, it was not the mainline Linux kernel -- it was an out-of-tree patch, which is why it's being replaced.

**How AUFS works**

AUFS stacks directories called **branches**, in order from lowest to highest, when we reead a file:

* AUFS searches branches from top to bottom
* Returns the first match it finds

When we write a file that exists in a lower (read-only) branch:

* AUFS copies the file up to the top (writable) branch -- this is called (COW) Copy-on-Write
* Then writes to the copy in the writable branch
* The original in the lower branch is untouched

```
Read "nginx.conf":
┌──────────────────────────┐  ← Container's writable layer (empty)
├──────────────────────────┤  ← nginx config layer (FOUND here, return it)
├──────────────────────────┤  ← nginx binary layer
└──────────────────────────┘  ← Debian base

Write "nginx.conf" (modify it):
┌──────────────────────────┐  ← CoW copy of nginx.conf written HERE
├──────────────────────────┤  ← original nginx.conf (untouched, still here)
├──────────────────────────┤  ← nginx binary layer
└──────────────────────────┘  ← Debian base
```

**Why AUFS was problematic**

* Not in mainline kernel -- required custom kernel patches
* Complex codebase, known performance issues with many layers
* Ubuntu was the main distro that shipped it; most others didn't
***

### OverlayFS -- THe Current Standard

**OverlayFS** was merged into the Linux mainline kernel in version **3.18 (2014)** and became the default Docker storage driver (``overlay2``) on modern systems, this is you are almost certainly running.

OverlayFS's structure is simpler than AUFS -- if merges exactly two directories at a time: a **lower** directory (read-only) and an **upper** directory (writable), preseting them as one **merged** directory.

```
lower dir (read-only) + upper dir (writable) = merged dir (what you see)
```

For Docker's multi-layer images, OverlayFS chains multiple lower directories:

```
lower4 / lower3 / lower2 / lower1 (all read-only image layers)
                                     + upper (writable container layer)
                                     = merged (what the container sees)
```

### The Four Directories in overlay2

When Docker creates a container with ``overlay2``, it creates four directories in ``/var/lib/docker/overlay2/<id>/``:

* ``lower`` - THe merged read-only image layers (actually a chain of layer directoreis)
* ``upper`` - The container wriable layer, all writes go here
* ``work`` - A working directory required by **OverlayFS** for atomic operations (rename, etc...) you never look inside this directly
* ``merged`` - The unified view presented to the container, this is what the container's filesystem root actually is

**Cow (Copy-on-Write) in OverlayFS**

The CoW mechanism is identical in concept to AUFS but implemented differently:

* **Reading a file that exists only in lower layers**: OverlayFS returns it directly from the lower layer -- zero copy, zero overhead

* **Writing to a file for the first time (file exists only in lower)**: OverlayFS copies the entire file from the lower layer to ``upper``, then writes the modification to the ``upper`` copy, the lower layer file is untouched.

* **Deleting a file that exists in a lower layer**: OverlayFS cannot actually delete from the read-only lower layer, instead, it creates a **whiteout file** in ``upper`` -- a special charcter device with device numbers 0,0.
When the merged view is constructed, any file in lower that has a corresponding whiteout in ``upper`` is hidden, the original file remains in the lower layer forever, but it's invisible.

This is a subtle but important detail: **deleted files in Docker layers still take space in the image**, this is why you should chain ``RUN apt-get unstall && rm -rf /var/cache/apt`` in a singel ``RUN`` instruction -- if you split htem into two ``RUN`` commands, the files downloaded by ``apt-get install`` are immortalized in the first layer even after the second ``RUN`` deletes them.

**Performance Characteristics**

OverlayFS has a known performance issue, the **First write to any file is slow**, because of the CoW copy, if we write to a large file (say, a multi-GB database file) for the first time, it gets fully copied from the lower layer to the ``upper`` before the write happens, this is one reason why databases inside containers should use **Volumes** (as ***Inception*** requires)  -- volumes bypass OverlayFS entirely and writes directly to the host filesystem, no CoW, no whiteouts, real disk performance.
This is the actual performance-negineering reason behind the project's volume requirement.
***

### Is ``dockerd`` a Server ?

It is a server, ``dockerd`` is a long-running background process -- a **daemon** -- and it exposes an **HTTP Server** that listens for requests, by default it listens on a Unix socket: ``/var/run/docker.sock``.

A Unix socket is like a network socket, but instead of going over TCP/IP across a network, it's a file on the filesystem that processes use to communicate locally, it's faster than TCP because there's no network stack involved -- it's just the kernel passing data between two processes directly.

So when we type ``docker run ngnix``, here is what actually happens:

```
You type:  docker run nginx
              │
              ▼
Docker CLI reads your command, constructs an HTTP request:

POST /v1.41/containers/create
Content-Type: application/json

{
  "Image": "nginx",
  "HostConfig": { ... },
  ...
}
              │
              ▼
CLI sends that HTTP request to:
  unix:///var/run/docker.sock
              │
              ▼
dockerd is listening on that socket.
It receives the HTTP request, parses it, decides what to do.
              │
              ▼
dockerd responds with HTTP:

HTTP/1.1 201 Created
{"Id": "a3f9b2...", "Warnings": []}
```

The Docker CLI is literally just an **HTTP Client** & the Docker Daemon is just an **HTTP Server**, The "**REST API**" between them is a documented HTTP API -- you can even talk to it using the ``curl`` command:

``curl --unix-socket /var/run/docker.sock http://localhost/v1.41/containers/json``.

That command lists all running containers -- same as ``dokcer ps``, no Docker CLI needed, we are talking directly to ``dockerd``.

```
Docker CLI ──► [REST/JSON over HTTP/1.1 on unix socket] ──► dockerd
                                                             │
                          [gRPC/protobuf over HTTP/2 on]     │
                          [unix socket: /run/containerd/]    ▼
                                                        containerd
                                                             │
                                                    [direct exec()]
                                                             │
                                                             ▼
                                                           runc
                                                    (sets up namespaces,
                                                     cgroups, calls
                                                     pivot_root(),
                                                     executes PID 1)
```

**gRPC**: Google Remote Procedure Call.

REST thinkgs in terms of resources, you GET a resrource, POST to create one, DELETE to remove one, gRPC thinks in terms of procedure calls -- you call a function on a remote process as if it were a local function

gRPC uses:

* HTTP/2 as the transport (not HTTP/1.1 like REST)
* Protocol Buffers for serialization
* a ``.proto`` file that defines the service interface -- the function you can call and thier argument/return types

gRPC is used between ``dokcerd`` and ``containerd`` because of the speed of communication it provides, also since its used as a communication way between internal services instead of a human/client type of relationship as we saw in the case of the REST API between Docker CLI and ``dockerd``.
