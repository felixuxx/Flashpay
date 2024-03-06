#!/bin/sh
# This file is in the public domain.
set -eu
psql talercheck < /dev/null || exit 77
echo "Initializing DB"
taler-exchange-dbinit -r -c test-exchange-db-postgres.conf
echo "Re-initializing DB"
taler-exchange-dbinit -c test-exchange-db-postgres.conf
echo "Re-loading procedures"
psql talercheck < procedures.sql
echo "Test PASSED"
exit 0
