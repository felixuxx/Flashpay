#!/bin/bash
# Setup database which was generated from a perfectly normal
# exchange-wallet interaction and run the auditor against it.
#
# Check that the auditor report is as expected.
#
# Requires 'jq' tool and Postgres superuser rights!
set -eu
DB=taler-auditor-test
dropdb $DB 2> /dev/null || true
createdb -T template0 $DB || exit 77
jq -h > /dev/null || exit 77
psql $DB -q -1 -f ../benchmark/auditor-basedb.sql > /dev/null
MASTER_PUB=`cat ../benchmark/auditor-basedb.mpub`

taler-auditor -c test-auditor.conf -m $MASTER_PUB > test-audit.json


fail=0
# if an emergency was detected, that is a bug and we should fail
echo -n "Test for emergencies... "
jq -e .emergencies < test-audit.json > /dev/null && (echo Failed; fail=1) || echo OK

# TODO: Add more checks to ensure test-audit.json matches expectations

dropdb $DB

exit $fail
