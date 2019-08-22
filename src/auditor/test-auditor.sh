#!/bin/bash
set -eu
DB=taler-auditor-test
dropdb $DB || true
createdb -T template0 $DB || exit 77
psql $DB < ../benchmark/auditor-basedb.sql
MASTER_PUB=`cat ../benchmark/auditor-basedb.mpub`

taler-auditor -c test-auditor.conf -m $MASTER_PUB > test-audit.json

# TODO: check test-audit.json matches expectations

dropdb $DB

