## Nginx

### What NGINX actually is

NGINX is a **web server** -- a program whose job is to accept incoming network connections (usually HTTP/HTTPS) and respond to them. But it's more specifically known as a **reverse proxy** in setups like this one, and that distinction matters for understanding why it's in our architecture at all.

#### Web server vs reverse proxy -- the difference

A plain web server serves files directly: request comes in for ``/index.html``, it reads that file off disk, sends it back. Simple.

A **reverse proxy** sits in front of other servers/processes and forwards requests to them on the client's behalf, then relays the response back -- the client only ever talks to the proxy, never directly to whatever's actually doing the work behind it.
"Reverse" (as opposed to a regular/forward proxy) because it's ying on behalf of the server side, hiding backend infrastructure from the client, not proxying outbound request on behalf of a client

#### Why NGINX specifically has this role in inception

Look back at the architecture diagram from the subject: NGINX is the **only** container exposed to the outside world, on port 443, WordPress+php-fpm and MariaDB are not directly reachable from outside -- they only exist inside the private Docker network.

So NGINX job here is:

1. Terminate TLS (accept the HTTPS connection, decrypt it) -- this is why NGINX, not php-fpm, handle the TLSv1.2/1.3 requirement

2. For requests that need PHP execution (basically all WordPress requests), **forward the request internally** to the php-fpm container over the network, using the FastCGI protocol
3. Take php-fpm's response and relay it back to the actual browser over the TLS connection

This is why the subject insists ***"NGINX must be the only entrypoint"*** -- it's real security architecture pattern, not arbitraty rule. Our database and application logic are never directly reachable from the internet; only the hardened, TLS-terminating proxy is. If someone attacks our infra from the outside, they only ever get to talk to NGINX.

#### Where NGINX's config comes in

NGINX's behavior is driven almost entirely by its config file (``nginx.conf`` or files it includes) -- this isn't a compiled decision, it's declarative directives like:

```
listen 443 ssl;
ssl_protocols TLSv1.2 TLSv1.3;
```

**Mental Model** to hold: **NGINX is a gatekeeper + traffic router**, not the thing that generates the WordPress page content -- php-fpm/WordPress does that; NGINX decides whether and how to get a request there, and enforces the TLS boundary on the way in

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

