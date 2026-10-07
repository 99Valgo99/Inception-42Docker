## WordPress

![Logo](../../../../Img/WordPress.png)
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

RUN curl -O https://raw.githubusercontent.com/wp-cli/gh-pages/phar/wp-cli.phar && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp
```

``php-fpm`` -- The actual **daemon** -- the long running process that does PHP execution, listens on a port for FastCGI requests, and runs **WordPress**'s code when told to. This is the core piece of this entire container, everything else supports it.

``php-mysqli`` -- a **PHP extension** -- not a standalone program, but a module that plugs into the PHP interpreter, giving PHP code the ability to open connections to MySQL/MariaDB server and run queries. Wihtout this, WordPress's PHP code would have no way to actually talk to our MariaDB container at all -- every WordPress operation that touches the database (loading a post, checking a login, serving a comment), ultimately goes through this extension's functions under the hood. ``mysqli`` stand for "***MySQL improved***", it's the modern, standard extension for this (there was an old ``mysql`` extension before, but its depricated/removed in current PHP versions).

``curl`` -- A command-line HTTP client tool -- **not a PHP extension here**, just the plain shell urility, we need this purely as a **build-time tool**, to actually download ``wp-cli``'s ``.phar`` file and the WordPress source archive from the internet in the next Dockerfile steps. It has no role once the container is actually running WordPress.
***

``curl -O <url>`` -- downloads the file from that URL. ``-O`` tells curl to save it using the **same filename as the remove file** (``wp-cli.phar``), rather than needing to specify an output name manually.

**What a ``.phar`` file actually is** -- PHP archive, a singe packaged file bundling an entire PHP application (code, dependencies, everything) into one executable unit -- conceptually similar to a Java ``.jar`` file. ``wp-cli`` shops this way specifically so it can be dropped anywhere and run directly, without needing a seperate install/extraction step.

``chmod +x wp-cli.phar`` -- makes it executable, same reasoning as every other executable.

``mv wp-cli.phar /user/local/bin/wp`` -- two things happening in one line: moves the file to ``/usr/local/bin``, a directory that's **already on the system's ``$PATH`` by Linux concention (this is the standard location ofr locally-installed, user-facing executables, distinct from ``/usr/bin/`` which is reserved for distro-package-managed binaries) -- meaning once it's here, we can just type ``wp`` from anywhere, rather than needing the full path or the ``.phar`` extension. The rename from ``wp-cli.phar`` to ``wp`` is purely for conveniece -- ``wp`` is the conventional, documented command name for this tool.

``wp-cli.phar`` -- is a PHP script, not a self-contained standalone binary

A ``.phar`` file bunldes PHP code together, but it's not compiled machine code -- it's still PHP source code, packaged into one file. To actually execute it, something needs to **interpret** that PHP code -- specifically, the **PHP CLI** binary (``php``, the command-line interpreter), which is a different thing from ``php-fpm`` (the FastCGI daemon used for web requests).

**The two distinct steps ``wp-cli`` breaks into**

1. ``wp core download`` -- fetches WordPress's actual source files (the ``.php`` files, default themes...) and extracts them into a difrectory. This doesn't touch the database at all -- it's purely getting the application code onto disk.

2. ``wp core install`` -- this is the step what actually does the browser wizard normally does: creates WordPress's database tables (inside the ``wordpress_db`` database we already created using MariaDB), and creats the first Wordpress user -- who automatically becomes the site's administrator.

```
wp core download --path=/var/www/html --allow-root

wp config create \
        --path=/var/www/html \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${MYSQL_PASSWORD}" \
        --dbhost=mariadb \
        --allow-root

wp core install \
        --path=/var/www/html \
        --url="https://${DOMAIN_NAME}"\
        --title="Inception" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --allow-root
```

``--path=/var/www/html`` -- tells ``wp-cli`` which directory WordPress's files live in and should be install into. This path matters a lot -- it needs to match exactly what NGINX's ``root`` directive points at and exactly where our second named volume will be mounted, since this is the WordPress website files, the subject requires to be persisted.

``--allow-root`` -- ``wp-cli`` refuses to run as the root user by default, as a safety measure (running web-app tooling as root is generally discouraged, since a compromised WordPress install running as root would have full system access). Since our container's default user is root (no ``USER`` instruction, same situation as MariaDB's script), we need this flag to override that safety check. Worh flagging as a legitimate, deliberate exception, not an oversight.

``wp config create`` -- this is the step that generates WordPress actual ``wp-config.php`` file -- the file containing the database connection details ``--dbhost=mariadb`` is the critical line here: ``mariadb`` is the **Docker service name**, resolved via internal DNS mechanism, not an IP address or ``localhost``.

``--dbname``/``--dbuser``/``--dbpass`` -- pulled from the exact same ``MYSQL_DATABASE``/``MYSQL_USER``/``MYSQL_PASSWORD``.

``wp core install`` -- ``--admin_user``/``--admin_password``/``--admin_email`` create wordpress's first user, who becomes the administrator.
***

#### What ``wp config create`` actually does

This step does not create any database tables at all. It only generates the ``wp-config.php`` file -- a plain PHP file containing the **connection details**: which database name, which user, which password, which host to connect to. Think of it as writing down "***Here is how to reach the database***" -- nothing about the database's actual structure gets touched yet. No tables, no data, nothing -- just a config file sitting on disk.

#### What ``wp core install`` actually does

This is the step that does the real database work: it **connects** to the database (using the connection details ``wp config create`` just wrote into ``wp-config.php``), and **creates all of WordPress's actual tables** inside it (``wp_posts, ``wp_users``, ``wp_options``...) -- this is WordPress's entire internal schema, created fresh. It's aslo the step that creates the **first user account**, who becomes the site administrator.

#### Defining Two WordPress Users

**User1** -- the administrator, created via ``wp core install`` automatically, and that user is always the site's administrator. The username comes from ``--admin_user``

```
--admin_user="${WP_ADMIN_USER}"
```

**The compliance constraint applies directly here** -- ``WP_ADMIN_USER``'s value must **not** contain ``admin``, ``Admin``, ``administrator``...or anything like this as substring. Something like ``xoris_root`` would satisfy this.

**User2** -- a second, separate user, created via a different ``wp-cli`` command

``wp core install`` only ever creates one account. For the second user, we need a **seperate command**, runs after the installation:


```
wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --user_pass="${WP_USER_PASSWORD}" \
        --role=author \
        --path=/var/www/html \
        --allow-root
```

**Breaking it down**:

``wp user create <username> <email>`` -- a distinct ``wp-cli`` command (not ``core install``), specifically for addming additional user accounts to an already-installed WordPress site. Tales username and email as positional arguments.

``--user_pass`` -- sets the password explicitly, rather than letting ``wp-cli`` auto-generate one (which it does by default it omitted -- useful for interactive use, but we need a known, deterministic password for our automated setup, pulled from a secret).

``--role=author`` -- this is a genuinly new WordPress concept worht understanding: WordPRess has a built-in **role system**, controlling what a user account is permitted to do. Common built-in roels, from least to most privileged: ``subscriber`` (read-only, can comment), ``contributor`` (can write but not publish), ``author`` (can write and publish their own posts), ``editor`` (can manage all posts, not just their own), ``administrator`` (full site control -- this is what ``core install``'s user automatically gets). The subject just requires a second user, with no specific role mandated -- ``author`` is a reasonable, genuinly non-admin choice, clearly satisying "***two users, one admin***" by making the scond one unambiguously not an admin.

### Why this second command needs to run after ``core install``, not alongside it

``wp user create`` operates on an **already-functioning WordPRess database** -- it needs the ``wp_users`` table (and WordPress's whole schema) to already exist, which only happens once ``core install`` has run, Same as the sequence chain of ``config create`` -> ``core install`` ordering.
***

### php-fpm Configuration + Entrypoint Script

#### Part A - php-fpm's listening configuration

By default, php-fpm listens on a **Unix Socket**, not a TCP port -- but we established that NGINX and php-fpm, being separate containers, **must** communicate over TCP, not a socket (sockets can't cross container boundaries). This means we need to override php-fpm's default pool config.

php-fpm's config lives in a **pool** file -- on Debian, typically at ``/etc/php/8.2/fpm/pool.d/www.conf`` (the exact PHP version number matters here; we will confirm it once we built). They key line we need to change:

```
listen = 127.0.0.1:9000
```

Debian's default binds php-fpm to ``127.0.0.1:9000`` -- loopback only, same exact problem we hit with MariaDB's default bind-address, we need it listening on all interfaces instead:

```
listen = 9000
```

Worth nothing the syntax difference from MariaDB's fix: php-fpm's ``listen`` directive, when given just a bare port number (no IP prexi), means "***listen on all interfaces, this port***" -- functionally equivalent to ``MariaDb's ``0.0.0.0``, just a different config syntax convention for this particular piece of software.

Like NGINX's ``conf.d`` and MariaDB's ``mariadb.conf.d``, this file gets ``COPY``'d inot the image at the correct path, overriding the specific line we need changed.

#### Part B -- The entrypoint script

```
#!/bin/sh

set -e

WP_PATH="/var/www/html"

MYSQL_PASSWORD="$(cat /run/secrets/db_password)"
WP_ADMIN_PASSWORD="$(cat /run/secrets/wp_admin_password)"
WP_USER_PASSWORD="$(cat /run/secrets/wp_user_password)"

if [ ! -f "$WP_PATH/wp-config.php"]; then
        wp core download --path="$WP_PATH" -- allow-root

        wp config create \
        --path="$WP_PATH" \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${MYSQL_PASSWORD}" \
        --dbhost=mariadb \
        --allow-root

        wp core install \
        --path="$WP_PATH" \
        --url="https://${DOMAIN_NAME}"
        --title="Inception" \
        --admin_user="${WP_ADMIN_USER}"
        --admin_password="${WP_ADMIN_PASSWORD}"
        --admin_email="${WP_ADMIN_EMAUL}" \
        --allow-root

        wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --user_pass="${WP_USER_PASSWORD}" \
        --role=author \
        --path="$WP_PATH" \
        --allow-root
fi

exec php-fpm8.2 -F
```

First we check if the file ``wp-config.php`` exists and present in the **WP_PATH** dir, if it does exist, we skip the other commands, if it exists and we ran the commands all over again, ``wp core download`` would try to re download and potentially overwrite WordPress's own core filse (probably harmless on its own, since it's just re-fetching the same core code), but ``wp config create`` would likely fail or refuse to overwrite an existing ``wp-config.php`` (or worse, silently overwrite it -- depends on the flags), and ``wp core install``/``wp user create`` would almost certanly error out, trying to install over an already-installed site and create users that already exist, at minimum, we will get a container that fails to start cleanly on every restart after the first; at worst, partial/inconsistent state.

``exec php-fpm8.2 -F`` -- ``-F`` without it, php-fpm -- like NGINX before applying our fix -- **daemonizes by default**: forks into the background, and the original foreground process exits. if that happened after out ``exec`` already made the script becomes php-fpm, the forking behavior would still cause PID 1 to exit immediately once it hands off to its background child, reproduciton the same bahavior as "***Container dies seconds after starting***" failure. ``-F`` tells php-fpm explicitly: **stay in the foreground, don't fork, don't daemonize** -- be w well-behaved PID 1.
***

```
RUN sed -i 's|listen = /run/php/php8.2-fpm.sock|listen = 9000|g' /etc/php/8.2/fpm/pool.d/www.conf
```

``sed`` -- "stream editor" a Unix tool for performing text transfomrations on a file. line by line, without needing to open it in an interactive editor.

``-i`` -- "In place" -- modifies the actual file directly, rather than showing the transformed result to stdout without touching the actual file.

``'s|old|new|g`` -- this is ``sed``'s substitute command:

* ``s`` -- the substitute operation itself.
* ``|old|new|`` -- the ``|`` charachters here are delimiters -- ``sed`` uses ''/'' as the delimiters, but since our our old text itself is using ``/`` as a dir, we are using ``|`` instread.
* ``g`` -- "global" -- replace every occurence on each matching line, not just hte first one found.
***