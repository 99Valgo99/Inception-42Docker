### Why do databases exist at all ?

Software needs to remember things across runs -- a user's account, a blog post, a session. The naive answer is "***write to a file***", that breaks down fast: concurrent writes corrupt files, searching through flat files is slow at scale, and there's no way to enforce that data stays consistent (e.g. a comment poiniting to a post that no longer exists)

A **database** is a piece of software whose entire job is solving this well:

Store data persistently, let multiple processes read/write it safely at once, let us query subsets of it efficently, and enforce rules about what shape the data is allowed to take. Eveything below is really just different strategies for doing that.
***

#### ***How should data be shaped ?***

**Relational vs. Non-Relational** Databases:

**Relational Model**: Data lives in **tables** -- fixed colimns, each row the same shape. Relationships between different kinds of data (a user has posts) aren't stored as nested blobs; they're expressed by one table refrencing another table's identifier. The model trades flexibility for strong guarantees: every row in a table is shaped the same way, and the database itself can enforce that a reference actually points to something real.

**Non-Relational ("***NoSQL***") models**: No fixed cross-record shape required.

* Document stores (MongoDB) --> each record is a flexible nested blob (JSON-like)
* Key-value stores (Redis) -- just id -> value, no query language needed
* Graph, wide-column, etc... -- optimized for specific access patterns

Neither is "better" -- it's a tradeoff.
Relational wins when our data has clear, stable structure and the relationships betweem pieces of data matter (which is exactly **WordPress**'s situation: a post belongs to a user, has comments, has metadata -- all cleanly tabular). Non-Relational wins when the shapre of data vaies widly record-to-record, or we need somthing simpler/faster for one specific pattern.

#### Language vs. The Software that Speaks It

As we previoulsy know, HTTP is a protocol/language, NGINX is a software that implements it. Same pattern here.

**SQL (Structured Query Language)** is not software. It's a standardized language for interacting with relational databases -- ``SELECT``, ``INSERT``, ``CREATE TABLE``, ``GRANT``. Any relational database engine that wants to be usable implements some dialect of it.

Learning SQL doesn't mean learning a product; it means learning a vocabulary that mostly transfers across products.

an **RDBMS** (Relation Database Management System) is the actual software -- the endinge that parses SQL, enfores the relational rules, manages storage, handles concurrent access. Postgres, Oracle DB, SQLite, MySQL/MariaDB are all **RDBMS** implementations, different engines, same underlying languae (with dialect differences).

#### Specifics

Names --> Layers:

* **SQL** -> The language -- not tied to any vendor.

* **MySQL** -> A specific RDBMS product implementing **SQL**, originally MySQL AB, now owned by Oracle

* **MariaDB** -> A **fork** of MySQL, created in 2009 by MySQL's original creatos when Oracle acquired it. Same SQL dialect, same wire protocol, same client tools -- a drop-in replacement

* **mysqld/mariadbd** -> The actual **daemon binary** -- the long-running background process that listens on port, accepts connections, and executes queries. The ``d`` suffix = daemon, same naming pattern as ``dockerd``, ``sshd``...

So concretly: we write SQL -> MariaDB is the engine that understands and executes it -> ``mariadbd/mysqld`` is the literal running process doing that work, the thing our container's ``ENTRYPOINT`` ultimately launches as PID1.

#### Client-server shape

Like ``dockerd``, the database engine runs as a persistent daemon that clients connect to -- not somthing invoked fresh per-query:

```
client (WordPress's PHP code, via a DB driver)

| TCP connection, port 3306
▼

mysqld/mariadbd - listens, authenticate, parses SQL, executes

|
▼

storage (InnoDB) - actually reads/writes rows to disk
```

This is why, in our compose setup, MariaDB exposes 3306 only inside the custom Docker network -- WordPress's PHP is a TCP client to it, same relationship shape as browser -> NGINX, just different protocol.

MariaDB itse;f is a query processor sitting on top of a **storage engine** (default: InnoDB), which is the part that actually owns how rows hit disk, transactions, crash recovery. That's why the data directory (``/var/lib/mysql``) is what we point the named volume at -- that's where **InnoDB**'s real files live. The elegance of ``CREATE DATABASE`` means nothing if that directory isn't persisted.
