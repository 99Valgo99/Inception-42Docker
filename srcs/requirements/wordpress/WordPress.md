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