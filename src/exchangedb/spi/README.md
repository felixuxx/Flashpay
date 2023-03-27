                           Server Programming Interface (SPI)


Dependencies:
=============

These are the direct dependencies for running SPI functions :



Step 1:
"postgresql-server-dev-<depends on your postgresql version>"
-- sudo apt-get install libpq-dev postgresql-server-dev-13

Step 2:
To solve gssapi/gssapi.h, use the following command:
apt-get install libkrb5-dev

Step 3:
apt-cache search openssl | grep -- -dev
apt-get install libssl-dev

Compile:
========
gcc -shared -o <file_name>.so <file_name>.c

CALL FUNCTIONS:
===============

psql -c "SELECT <function_name>();" db_name

Structure:
==========

usr/include/postgres/

usr/include/postgres/13/server/

make
make install
psql