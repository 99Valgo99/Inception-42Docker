## WordPress

![Logo](../../../Img/WordPress.png)
***

Wordpress is a **PHP application** -- not a server, not a daemon, just a large collection of ``.php`` files (plus themes, plugins, updoaded media) that, when executed by a PHP interpreter in response to an HTTP request, generate an HTML page dynamically.
Unlike NGINX or MAriaDB, WordPress has no process of its own that "runs" -- it's inert code sitting on disk until something executes it.

This is a fundamentally different kind of thing that the previous two containers.

#### What php-fpm actually is

**php-fpm** stands for **PHP FastCGI Process Manager**. It's a real, standalone daemon -- a long-running process, the same category of things as ``mariadbd`` -- whose entire job: is **recieve a request for a specifc ``.php`` file, execute that PHP code, and return the generated output**. It's the thing that actually runs WordPRess's PHP files; WordPress itself is just the code php-fpm executes.

#### Why can't just NGINX execute PHP itself

NGINX is fundamentally a **web server** / **reverse proxy** -- its native competency is handling HTTP connections, serving static files directly from disk, and routing requests. It has no **PHP interpreter built into it** -- it doesn't know how to execute a ``.php`` file's code, only how to read nad server raw file bytes. If NGINX tried to serve ``wp-login.php`` the same way it serves ``index.html``, it would just send the raw, unexected PHP source code as plaintext to the browser -- not run it.

Php-fpm handles **PHP execution** and **WordPress** is the code being executed.

The structure now becomes:

```
Browser -> NGINX (TLS, port 443)

        |       (the request is for a .php file)
        ▼
        php-fpm (execute the PHP code)
        
        |       (this code needs data from the database)
        ▼
        
        MariaDb (answers)
```

NGINX decides whether a request needs PHP execution (Based on the URL -- anything ending it ``.php``) and, if so, hands it off to **php-fpm** rather than trying to server it as static file. **php-fpm** then loads and executes the relevant WordPress ``.php`` file, which in trun may query MariaDB for data (post content, user accounts, settings), assembles the final HTML, and sends it back through the chain to the browser.

#### Why does Wordpress doesnt need a web server of its own ?

**Php-fpm** doesn't listen for raw HTTP requests from browsers -- it listens for different protocol entirely, spojen only between it and NGINX, over the Docker network. It has no conecpt of TLS< no concept of being a "sole entrypoint" -- it's purely a backedn execution engine, reachable only internally.

### FastCGI

NGINX and php-fpm are **two seperate processes, running in two seperate containers**, with no shared memeory, no direct function calls between them, When NGINX decies "***this request need PHP execution***", it needs some way to **hand off** the request to php-fpm and get back the generated response -- across a process boundary, potenitally across a network. FastCGI is the protocol that defines exactly how that handoff happens.

#### CGI -> FastCGI: a brief, useful bit of history

The older ancestor of this idea is **CGI** **Common Gateway interface** -- the original way web servers ran dynamic code: for every single incoming request, the web server would start a brand new process from scratch, run the script, capture its output, then kill the process from scratch, this worked, but was brutally slow at scale -- spawning a fresh process, for every single request is expensive, especially multipied across thousands of concurrent users.

**FastCGI** fixes this by keeping a **pool of long running worker processes** (this is literally what the **Process Manager** refers to) permanently alive, ready to handle request after request without the overhead of starting a new process each time. NGINX just sends each new request to an ***already-running php-fpm worker**, rather than spawning anything fresh.

#### What actually gets sent over FastCGI

When NGINX hands a request to php-fpm, it doesn't just forward the raw HTTP request -- it translates the request into a specific set of **FastCGI parameteres**:

The script's filesystem path ``SCRIPT_FILENAME``, the request method, query string, headers, and so on...php-fpm receives these parameters, locates and executes the corresponding ``.php`` file with that context available to it (this is how PHP's ``$_GET``, ``$_POST``, ``$_SERVER`` supergloabals get populated -- they are built from these passed-through parameters), and sends back the generated output (headers + HTML Body) in the FastCGI response format, which NGINX then repackages into a normal HTTP response for the browser.

FastCGI needs an actual communication channel between NGINX and php-fpm. Two options exist:

**Unix socket** -- a local-filesystem-based connection, same as MariaDB's ``/run/mysqld/mysqld.sock``, but only works when both processes can see the same filesystem path -- meaning both would need to be in the same **container** or share a mounted volume for that socket file.

**TCP** -- a standard network connection, using an IP address (or in our case **Docker**'s internal DNS -- the service name ``wordpress``) send a port **9000** for php-fpm, works perfectly across seperate containers on the same Docker network.

Since NGINX and php are **deliberately seperate containers**, we must use **TCP**, not a Unix Socket -- a socket file can't be shared across container boundaries the way it could within one container. This is the mechanism visible in the subject architecture, the ``9000`` lable on the arrow between WordPress+PHP container and the NGINX container is exactly this FastCGI-over-TCO connection

**Both NGINX and WordPress/php-fpm** need access to the same WordPress files on disk -- but for two different reasons:

* **php_fpm** needs them to actually execute the ``.php`` files (via ``SCRIPT_FILENAME``).

* **NGINX** needs them to directly serve the static assets (images, CSS, JS, uploaded media) without ever involving php-fpm at all.

Since these are two seperate containers, each with its own isolated filesystem, the only way both can see the identical files is exactly a **shared named volume**, mounted into both containers at the same path (or at least, into both at a path each can correctly use).
***

### WordPress Dockerfile: Base + Install

```
FROM debian:bookworm
```

Same reasoning as NGINX and MariaDB -- consistency across all hree services, no justificaion needed for a different choice here.

#### What packages does this container actually need?

WordPress + php-fpm budles together a few genuinely distinc pieces:

* **php-fpm** itself -- the actual daemon. On Debian, this is typically the ``php-fpm`` package (or a version-specific one like ``php8.2-fpm``, depending on what's in Debian bookworm's repos)

* **PHP extension WordPress actually requires** -- PHP's core doesn't include everything WordPress needs by default.
WordPress specifically requires, at minimum: ``php-mysqli`` (or ``php-mysql``) for talking to MariaDB, and commonly also needs things like ``php-curl``, ``php-gd``, ``php-xml``, ``php-mbstring`` -- the exact list depends on which WordPress features we want working correctly.

* ``wp-cli`` -- this is the tool we will use to install/configure WordPress **non-interactively**. It's not a Debian Package -- it's a standalone PHP-based command-line tool, typically downloaded directly as a ``.phar`` file from WordPress's own project, then made executable.

* **WordPress Itself** -- the actual application files (``wp-admin/``, ``wp-content/``, ``wp-login.php``, etc..). This isn't an apt package at all -- it's a ``.zip``/``.tar.gz`` archive downloaded from wordpress.org, which ``wp-cli`` can fetch and extract for us.

* ``curl`` or ``wget`` -- needed as a build-time tool to actually download ``wp-cli`` and WordPress itself, if they're not already present in a minimal Debian image.
***
### Dockerfile

```
RUN apt-get update && apt-get install -y --no-install-recommends php-fpm php-mysqli curl && rm -rf /var/lib/apt/lists/*

RUN curl -O https://raw.githubusercontent.com/wp-cli/gh-pages/ && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp
```

``php-fpm`` -- The actual **daemon** -- the long running process that does PHP execution, listens on a port for FastCGI requests, and runs **WordPress**'s code when told to. This is the core piece of this entire container, everything else supports it.

``php-mysqli`` -- a **PHP extension** -- not a standalone program, but a module that plugs into the PHP interpreter, giving PHP code the ability to open connections to MySQL/MariaDB server and run queries. Wihtout this, WordPress's PHP code would have no way to actually talk to our MariaDB container at all -- every WordPress operation that touches the database (loading a post, checking a login, serving a comment), ultimately goes through this extension's functions under the hood. ``mysqli`` stand for "***MySQL improved***", it's the modern, standard extension for this (there was an old ``mysql`` extension before, but its depricated/removed in current PHP versions).

``curl`` -- A command-line HTTP client tool -- **not a PHP extension here**, just the plain shell urility, we need this purely as a **build-time tool**, to actually download ``wp-cli``'s ``.phar`` file and the WordPress source archive from the internet in the next Dockerfile steps. It has no role once the container is actually running WordPress.
***

``curl -O <url>`` -- downloads the file from that URL. ``-O`` tells curl to save it using the **same filename as the remove file** (``wp-cli.phar``), rather than needing to specify an output name manually.

**What a ``.phar`` file actually is** -- PHP archive, a singe packaged file bundling an entire PHP application (code, dependencies, everything) into one executable unit -- conceptually similar to a Java ``.jar`` file. ``wp-cli`` shops this way specifically so it can be dropped anywhere and run directly, without needing a seperate install/extraction step.

``chmod +x wp-cli.phar`` -- makes it executable, same reasoning as every other executable.

``mv wp-cli.phar /user/local/bin/wp`` -- two things happening in one line: moves the file to ``/usr/local/bin``, a directory that's **already on the system's ``$PATH`` by Linux concention (this is the standard location ofr locally-installed, user-facing executables, distinct from ``/usr/bin/`` which is reserved for distro-package-managed binaries) -- meaning once it's here, we can just type ``wp`` from anywhere, rather than needing the full path or the ``.phar`` extension. The rename from ``wp-cli.phar`` to ``wp`` is purely for conveniece -- ``wp`` is the conventional, documented command name for this tool.