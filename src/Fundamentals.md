## Docker Fundamentals

### **image** vs **Container**

A **Docker Image** is a **read-only template** -- a stack of filesystem layers (**OverlayFS** lower layres) plus metadata (what command to run, what ports are documented, what env vars are default). It does nothing by itself, it's inert, sitting on disk, buildable and shareable.

(So docker image is the build of all components of the docker file, the image of the component, ports, vars... ?)

A **Container** is a **running instance of an image** -- the image's layers mounted read-only, plus one new writable layer on top (the ``upper`` dir built by **OverlayFS**), plus an actual running process (PID 1 inside its own PID namespace), plus its own network namespace, mount namespace, etc...

Analogy that maps cleanly onto this: the image is like a class definition; the container is an instantiated object. We can spin up multiple containers from the same image -- each gets its own writable layer and namespaces, but shares the same read-only image laters underneath (zero duplication).

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

