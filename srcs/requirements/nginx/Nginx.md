## Nginx

### What NGINX actually is

NGINX is a **web server** -- a program whose job is to accept incoming network connections (usually HTTP/HTTPS) and respond to them. But it's more specifically known as a **reverse proxy** in setups like this one, and that distinction matters for understanding why it's in our architecture at all.

#### Web server vs reverse proxy -- the difference

A plain web server serves files directly: request comes in for ``/index.html``, it reads that file off disk, sends it back. Simple.

A **reverse proxy** sits in front of other servers/processes and forwards requests to them on the client's behalf, then relays the response back -- the client only ever talks to the proxy, never directly to whatever's actually doing the work behind it.
"Reverse" (as opposed to a regular/forward proxy) because it's ying on behalf of the server side, hiding backend infrastructure from the client, not proxying outbound request on behalf of a client
***

#### Why NGINX specifically has this role in inception

Look back at the architecture diagram from the subject: NGINX is the **only** container exposed to the outside world, on port 443, WordPress+php-fpm and MariaDB are not directly reachable from outside -- they only exist inside the private Docker network.

So NGINX job here is:

1. Terminate TLS (accept the HTTPS connection, decrypt it) -- this is why NGINX, not php-fpm, handle the TLSv1.2/1.3 requirement

2. For requests that need PHP execution (basically all WordPress requests), **forward the request internally** to the php-fpm container over the network, using the FastCGI protocol
3. Take php-fpm's response and relay it back to the actual browser over the TLS connection

This is why the subject insists ***"NGINX must be the only entrypoint"*** -- it's real security architecture pattern, not arbitraty rule. Our database and application logic are never directly reachable from the internet; only the hardened, TLS-terminating proxy is. If someone attacks our infra from the outside, they only ever get to talk to NGINX.
***

#### Where NGINX's config comes in

NGINX's behavior is driven almost entirely by its config file (``nginx.conf`` or files it includes) -- this isn't a compiled decision, it's declarative directives like:

```
listen 443 ssl;
ssl_protocols TLSv1.2 TLSv1.3;
```

**Mental Model** to hold: **NGINX is a gatekeeper + traffic router**, not the thing that generates the WordPress page content -- php-fpm/WordPress does that; NGINX decides whether and how to get a request there, and enforces the TLS boundary on the way in
***

### TLS - Transport Layer Security

#### What problem TLS solves

Plain HTTP sends everything in cleartest -- anyone on the network path (our ISP, a malicious router, someone on the same WIFI) can read or modify traffic. TLS wraps that traffic so it's:

* Encrypted
* Authenticated -- The client can verify it's actually talking to who it thinks it is
* Tamper-evident -- any modification in transit is detectable

HTTPS is just HTTP reunning inside a TLS tunnel

#### The handshake -- what actually happens on the wire

1. **Client Hello** -- client connects, says ***"here is the TLS versions and cipher suites i support"***
2. **Server Hello** -- server (NGINX, in our case) picks a TLS version + cipher suite from what's offered, and sends back its **certificate** (contains its public key + identity info).
3. **Key Exchange** -- client and server use asymmetric crypto (public/private key math) to agree on **shared secret**, without ever transmitting that secret itself in a way no one can reconstruct it.
4. Switch to symmetric encryption -- asymmetric crypto is slow, so once both sides have the shared secret, they derive a **symmetric session key** from it and use that for the actual bulk data encryption from here on (more fast)
5. **Application data flows**, ecrypted, over this now-established session.

#### Certificate -- what is actually is

A certificate is a file containing: a **public key**, an **identity claim** (***"I am xoris.42.fr"***) and normally a **signature from a trusted Certificate Authority (CA)** vouching that the identity claim is legitimate.

#### Why do we use a self-signed certificate here

Normally a CA (like ``Let's Encrypt``) signs our cert after verifying we actually control that domain. But ``login.42.fr`` isn't a real, internet-routable domain -- it's fake entry we are adding to ``/etc/hosts`` pointing to our local machine. No real CA would ever sign a cert for a domain like that. So instead, **we generate a cerificate and sign it ourselves** (via ``openssl``), which cryptographically still does the encryption/tamer-evidence job perfectly -- it just fails the CA part, which is why our browser will show a ***"Not Trusted"*** warning. That's expected and fine for this project; it's not a real production deployment reachable by the the public internet.
***

### NGINX Dockerfile

```
FROM debian:bookworm-slim
```

``debian`` -- the official Debian image, maintained by Debian project itself and published on Docker Hub (***Docker Hub is a cloud-hosted registry service provided by Docker that enables you to find, share, and manage container images***), this is the one pull allowed by the subject (Base OS images are explicitly excluded from the rule of not pulling ready-made images).

``bookworm`` -- this is the codename for Debian 12, the current stable release as of now. Debian names releases after Toy Story characters (Bookworm, bulleye, Buster...).
Using the codename instead of a generic tag, pings us to a specific, knwon release -- its package versions, its behavior, security patch, if Debian releases Debian 13 by tomorrow, an image tagged ``bookworm`` doesn't silently change underneath.

``--slim`` -- a variant of the image with non-essential packages stipped out (docs, some locale files...) -- smaller image size, smaller attack surface, since we are installing exactly what we need ourselves anyway (nginx, openssl) rather than relying on a fuller base.

#### Why not ``debian:latest``

``latest`` is a **moving target**. It typically points to whatever the newest stable release is at pull time, so a build today and a build six months from now could silently resolve to enirely different Debian versions, with different package behavior. That breaks reproducibility, which is the whole point of pinning a version in the first place.
***

```
RUN apt-get update && apt-get install -y --no-install-recommends nginx openssl && rm -rf /var/lib/apt/lists/*
```

* ``apt-get update`` -- refeshes the local package index (the list of what packages/versions are available and from where URLs) inside the image. Debian base images don't ship with a pre-populated fresh index, so this always needs to run before installing anything.

* ``apt-get install -y nginx openssl`` -- installs the two packages we actually need: ``nginx`` (the web server itself) and ``openssl`` (the toolkit we will use to generate the self-signed cert).

* ``--no-install-recommends`` -- apt distinguishes between **"depends"** (mandatory requirments) and **"recommends"** (extra packages that are often useful but not strictly necessary). This flag skips the recommends tier, keeping the image leaner -- nginx doesn't need much beyond its hard dependencies to function correctly.

* Why ``update`` and ``install`` are chained with && in one ``RUN`` -- This is the point of **Caching**, Docker caches each ``RUN`` as a layer keyed on the instruction text. If ``apt-get update`` were its own seperate ``RUN`` layer, a rebuild days later could reuse that stale cached layer (with an outdated package index) while still running a fresh ``install` against it -- silently installing older/wrong package versions that what's actually current. Chaining them forces both to always execute together as one atomic unit, so the index is always feshly matched to the install step

* ``rm -rf /var/lib/apt/lists/*`` in the same instruction -- after ``apt-get update``, Debian caches the downloaded package index files on dick. They are only useful during the install itself; keeping them afterward just waste image space. Doing the cleanup in the same ``RUN`` (not a later one) means thise files never get commited into a seperate layer at all -- if we deleted them in a later ``RUN``, the earlier layer still physically caontains them.

