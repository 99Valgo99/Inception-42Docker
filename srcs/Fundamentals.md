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

### Docker Compose

```
services:
    service_name:
        container_name: service_name
        build: ./path
        image: servive_name:1.0
```

* ``services:`` is the top-level key. Everything under it is one service, and each service becomes one container. Later ``mariadb`` and ``wordpress`` will sit next to ``nginx`` at this same level.

* ``service_name:`` is the service name. It has two jobs:

> the subject requires each image to have the same name as its service, and Compose registers the service name as a **DNS Hostname** on the Docker network. This is how WordPress will reach ``mariadb`` by name.

* ``build: ./path`` is the build context. The path is relative to the compose file's location (``srcs/``), so it resolves to ``srcs/requirements/nginx``. Compose sends that folder to ``dockerd`` and finds the ``Dockerfile`` inside it by default, with no extra flag needed. Then Compose runs ``docker build``.

* ``image: service_name:1.0`` names and tags the image Compose builds. Without this line, Compose auto-names it something like ``srcs-service_name``, which breaks the same-name rule. The explicit tag matters too, otherwise without it it will be implicitly tagged ``latest``, and ``docker images`` would then show ``nginx:latest``, which based on the subject is banned.

* ``container_name: service_name`` it sets the name Docker gives the running container, so we can refer to it by name we chose in CLI as: ``docker exec -it service_name sh``, ``docker logs service_name`` or ``docker stop service_name``. Without it, Compose will generate a name from the project folder and service something as ``srcs-service_name-1``.