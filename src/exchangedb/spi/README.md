                Server Programming Interface (SPI)


Overview
========

This folder contains results from an experiment by Joseph Xu
to use the Postgres SPI. They are not currently used at all
by the GNU Taler exchange.


Dependencies
============

These are the direct dependencies for compiling the code:

# apt-get install libpq-dev postgresql-server-dev-13
# apt-get install libkrb5-dev
# apt-get install libssl-dev


Compilation
===========

$ make

Loading functions
=================

# make install
$ psql "$DB_NAME" < own_test.sql


Calling functions
==================

$ psql -c "SELECT $FUNCTION_NAME($ARGS);" "$DB_NAME"
