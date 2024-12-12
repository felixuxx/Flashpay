#!/bin/bash
set -evux

export PGPORT=5432
sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl \
    start -D /etc/postgresql/15/main -o "-h localhost -p $PGPORT"
sudo -u postgres createuser -p $PGPORT root -s -w
sudo -u postgres createdb -p $PGPORT -O root talercheck

