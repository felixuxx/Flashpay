#!/bin/sh
# This file is in the public domain.
set -eu
echo "Initializing DB"
taler-exchange-dbinit -r test-exchange-db-postgres.conf
echo "Re-initializing DB"
taler-exchange-dbinit test-exchange-db-postgres.conf
echo "Re-loading procedures"
psql talercheck < procedures.sql
echo "Test PASSED"
exit 0
