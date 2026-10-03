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

