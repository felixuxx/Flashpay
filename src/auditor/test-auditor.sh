#!/bin/bash
# Setup database which was generated from a perfectly normal
# exchange-wallet interaction and run the auditor against it.
#
# Check that the auditor report is as expected.
#
# Requires 'jq' tool and Postgres superuser rights!
set -eu

function exit_skip() {
    echo $1
    exit 77
}

function exit_fail() {
    echo $1
    kill `jobs -p`
    exit 1
}

function run_audit () {
    # Launch bank
    echo "Launching bank"
    taler-bank-manage -c test-auditor.conf serve-http 2>bank.err >bank.log &
    while true
    do
        echo -n "."
        wget http://localhost:8082/ -o /dev/null -O /dev/null >/dev/null && break
        sleep 1
    done
    echo "OK"

    # Run the auditor!
    echo "Running audit(s)"
    taler-auditor -r -c test-auditor.conf -m $MASTER_PUB > test-audit.json || exit_fail "auditor failed"
    
    taler-wire-auditor -r -c test-auditor.conf -m $MASTER_PUB > test-wire-audit.json || exit_fail "wire auditor failed"

    echo "Shutting down services"
    kill `jobs -p`

    echo "TeXing"
    ../../contrib/render.py test-audit.json test-wire-audit.json < ../../contrib/auditor-report.tex.j2 > test-report.tex || exit_fail Renderer failed

    pdflatex test-report.tex >/dev/null || exit_fail pdflatex failed
    pdflatex test-report.tex >/dev/null
}


# test required commands exist
echo "Testing for jq"
jq -h > /dev/null || exit_skip "jq required"
echo "Testing for taler-bank-manage"
taler-bank-manage -h >/dev/null </dev/null || exit_skip "taler-bank-manage required"
echo "Testing for pdflatex"
which pdflatex > /dev/null </dev/null || exit_skip "pdflatex required"

echo "Database setup"
DB=taler-auditor-test
dropdb $DB 2> /dev/null || true
createdb -T template0 $DB || exit_skip "could not create database"

# Import pre-generated database, -q(ietly) using single (-1) transaction
psql $DB -q -1 -f ../benchmark/auditor-basedb.sql > /dev/null
MASTER_PUB=`cat ../benchmark/auditor-basedb.mpub`

echo "===========1: normal run==========="
run_audit

echo "Checking output"
fail=0
# if an emergency was detected, that is a bug and we should fail
echo -n "Test for emergencies... "
jq -e .emergencies[0] < test-audit.json > /dev/null && exit_fail "Unexpected emergency detected in ordinary run" || echo OK

echo -n "Test for wire inconsistencies... "
jq -e .wire_out_amount_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected wire out inconsistency detected in ordinary run"
jq -e .reserve_in_amount_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected reserve in inconsistency detected in ordinary run"
jq -e .missattribution_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected missattribution inconsistency detected in ordinary run"
jq -e .row_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected row inconsistency detected in ordinary run"
jq -e .row_minor_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected minor row inconsistency detected in ordinary run"
jq -e .lag_details[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected lag detected in ordinary run"
jq -e .wire_format_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected wire format inconsistencies detected in ordinary run"

echo OK

echo -n "Test for wire amounts... "
WIRED=`jq -r .total_wire_in_delta_plus < test-wire-audit.json`
if test $WIRED != "TESTKUDOS:0"
then
    exit_fail "Expected total wire delta plus wrong, got $WIRED"
fi
WIRED=`jq -r .total_wire_in_delta_minus < test-wire-audit.json`
if test $WIRED != "TESTKUDOS:0"
then
    exit_fail "Expected total wire delta minus wrong, got $WIRED"
fi
WIRED=`jq -r .total_wire_out_delta_plus < test-wire-audit.json`
if test $WIRED != "TESTKUDOS:0"
then
    exit_fail "Expected total wire delta plus wrong, got $WIRED"
fi
WIRED=`jq -r .total_wire_out_delta_minus < test-wire-audit.json`
if test $WIRED != "TESTKUDOS:0"
then
    exit_fail "Expected total wire delta minus wrong, got $WIRED"
fi
WIRED=`jq -r .total_missattribution_in < test-wire-audit.json`
if test $WIRED != "TESTKUDOS:0"
then
    exit_fail "Expected total missattribution in wrong, got $WIRED"
fi
echo "OK"


echo "===========2: reserves_in inconsitency==========="
# TODO: Add more checks to ensure test-audit.json matches expectations
echo "UPDATE reserves_in SET credit_val=5 WHERE reserve_in_serial_id=1" | psql $DB

run_audit

echo -n "Test for inconsistency detection... "
ROW=`jq .reserve_in_amount_inconsistencies[0].row < test-wire-audit.json`
if test $ROW != 1
then
    exit_fail "Row wrong"
fi
WIRED=`jq -r .reserve_in_amount_inconsistencies[0].amount_wired < test-wire-audit.json`
if test $WIRED != "TESTKUDOS:10"
then
    exit_fail "Amount wrong"
fi
EXPECTED=`jq -r .reserve_in_amount_inconsistencies[0].amount_exchange_expected < test-wire-audit.json`
if test $EXPECTED != "TESTKUDOS:5"
then
    exit_fail "Expected amount wrong"
fi
DELTA=`jq -r .total_wire_in_delta_plus < test-wire-audit.json`
if test $DELTA != "TESTKUDOS:5"
then
    exit_fail "Expected total wire delta plus wrong"
fi
echo OK

# Undo database modification
echo "UPDATE reserves_in SET credit_val=10 WHERE reserve_in_serial_id=1" | psql $DB

# TODO: insert more tests!

echo "Cleanup"
dropdb $DB

exit $fail
