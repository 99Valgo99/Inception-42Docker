## MariaDB

### What MariaDB actually is

MariaDb is a **Relational database management system (RDBMS)** -- software that stores structed data in tables (rows/columns), lets us query it with SQL, and enforces relationships/constrains between tables. It's a **fork of MYSQL**, created in 2009 after Oracle acquired MySQL -- a group of the original MySQL developers forket it to keep it fully open-source and community-foverned, worried about Oracle's direction.

### Why it's still essentially a MySQL-compatible drop-in

For most practical purposes -- including WordPress, which was oringally  built against MYSQL -- MariaDB speaks the same **wire protocol**, supports the same **SQL dialect** (with its own extensions added over time), and uses the same client tools/commands (``mysql``, ``mysqldump``, even the binary is oftern just called ``myqsl`` or aliased).
This is precisely why WordPRess can connect to MariaDB without needing any WordPRess-specific code changes -- as far as WordPress's database layer is concerned, it's just talking to "a MySQL-speaking server".

### The client-server model

MariaDB runs as a **server process** (``maradbd``, historically ``mysqld``) that listens on a port (default 3306) and accepts connections from clients -- these could be command-line tools, or, in our case, **WordPress's PHP code itself acting as a client**, opening a connection, sending SQL queries, getting results back. This is a fundamentally different interaction pattern than NGINX/HTTP: it's a persistent, stateful connection with a request/response protocol of its own (not HTTP at all), authenticated at connection time with a username/password.

### Where it fits in our architecture

If we look back at the subject's diagram: MariaDB talks to **WordPress + PHP** only, over port 3306, entirely inside the Docker network -- never directly to NGINX, never exposed outside. This mirrors exactly the "***only NGINX is the entrypoint***" principle.
MariaDB is the most sensitive component (it holds all actual site data -- posts, user credentials, everything), so it sits at the deepest, most isolated layer. If WordPRess's PHP layer is compromised, the attacker still only rearches MariaDB through whatever queries WordPress's own code is willing to execute -- they don't get a direct, unmediated connection to the database from outside.

### Why MariaDB specifically needs a volume

Containers are ephemeral by default -- if we ``docker compose down`` and ``up`` again, we get a **fresh container**, fresh writable layer, and anything written to the container\s own filessystem (not a volume), is gone.
A database is the textbook case where this is catastrophic -- losing all our WordPRess data every restart would make the whole project pointless. This is exactly why the subject mandates a **named volume** for MariaDb's data directory specifically: the actual database files need to live outside the container's disposable layer, on the host, surviving container recreation entirely.

