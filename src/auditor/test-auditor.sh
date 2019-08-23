#!/bin/bash
# Setup database which was generated from a perfectly normal
# exchange-wallet interaction and run the auditor against it.
#
# Check that the auditor report is as expected.
#
# Requires 'jq' tool and Postgres superuser rights!
set -eu

# test required commands exist
echo "Testing for jq"
jq -h > /dev/null || exit 77
echo "Testing for taler-bank-manage"
taler-bank-manage -h >/dev/null || exit 77
echo "Testing for pdflatex"
which pdflatex > /dev/null || exit 77

echo "Database setup"
DB=taler-auditor-test
dropdb $DB 2> /dev/null || true
createdb -T template0 $DB || exit 77

# Import pre-generated database, -q(ietly) using single (-1) transaction
psql $DB -q -1 -f ../benchmark/auditor-basedb.sql > /dev/null
MASTER_PUB=`cat ../benchmark/auditor-basedb.mpub`

# Launch bank
echo "Launching bank"
taler-bank-manage -c test-auditor.conf serve-http 2>/dev/null >/dev/null &


# Run the auditor!
echo "Running audit(s)"
taler-auditor -c test-auditor.conf -m $MASTER_PUB > test-audit.json
taler-wire-auditor -c test-auditor.conf -m $MASTER_PUB > test-wire-audit.json

echo "Shutting down services"
kill `jobs -p`


echo "TeXing"
../../contrib/render.py test-audit.json test-wire-audit.json < ../../contrib/auditor-report.tex.j2 > test-report.tex

pdflatex test-report.tex >/dev/null
pdflatex test-report.tex >/dev/null

echo "Checking output"
fail=0
# if an emergency was detected, that is a bug and we should fail
echo -n "Test for emergencies... "
jq -e .emergencies[0] < test-audit.json > /dev/null && (echo Failed; fail=1) || echo OK

# TODO: Add more checks to ensure test-audit.json matches expectations


echo "Cleanup"
dropdb $DB

exit $fail
