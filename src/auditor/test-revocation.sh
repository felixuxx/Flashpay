#!/bin/bash
#
#  This file is part of TALER
#  Copyright (C) 2014-2022 Taler Systems SA
#
#  TALER is free software; you can redistribute it and/or modify it under the
#  terms of the GNU General Public License as published by the Free Software
#  Foundation; either version 3, or (at your option) any later version.
#
#  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
#  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
#  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License along with
#  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/license>
#
# Setup database which was generated from a exchange-wallet interaction
# with revocations and run the auditor against it.
#
# Check that the auditor report is as expected.
#
# shellcheck disable=SC2317
#
# Requires 'jq' tool and Postgres superuser rights!
set -eu
# set -x

# Set of numbers for all the testcases.
# When adding new tests, increase the last number:
ALL_TESTS=$(seq 0 4)

# $TESTS determines which tests we should run.
# This construction is used to make it easy to
# only run a subset of the tests. To only run a subset,
# pass the numbers of the tests to run as the FIRST
# argument to test-auditor.sh, i.e.:
#
# $ test-revocation.sh "1 3"
#
# to run tests 1 and 3 only.  By default, all tests are run.
#
TESTS=${1:-$ALL_TESTS}

# Global variable to run the auditor processes under valgrind
# VALGRIND=valgrind
VALGRIND=""
LOGLEVEL="INFO"

. setup.sh

# Cleanup to run whenever we exit
function cleanup()
{
    if [ ! -z "${EPID:-}" ]
    then
        echo -n "Stopping exchange $EPID..."
        kill -TERM "$EPID"
        wait "$EPID"
        echo " DONE"
        unset EPID
    fi
    stop_libeufin
}

# Cleanup to run whenever we exit
function exit_cleanup()
{
    echo "Running exit-cleanup"
    if [ ! -z "${POSTGRES_PATH:-}" ]
    then
        echo "Stopping Postgres at ${POSTGRES_PATH}"
        "${POSTGRES_PATH}/pg_ctl" \
            -D "$TMPDIR" \
            -l /dev/null \
            stop \
            &> /dev/null \
            || true
    fi
    cleanup
    for n in $(jobs -p)
    do
        kill "$n" 2> /dev/null || true
    done
    wait
    echo "DONE"
}

# Install cleanup handler (except for kill -9)
trap exit_cleanup EXIT


# Operations to run before the actual audit
function pre_audit () {
    # Launch bank
    echo -n "Launching bank "
    launch_libeufin
    for n in $(seq 1 80)
    do
        echo -n "."
        sleep 0.1
        OK=1
        wget http://localhost:18082/ \
             -o /dev/null \
             -O /dev/null \
             >/dev/null && break
        OK=0
    done
    if [ 1 != "$OK" ]
    then
        exit_skip "Failed to launch Sandbox"
    fi
    for n in $(seq 1 80)
    do
        echo -n "."
        sleep 0.1
        OK=1
        wget http://localhost:8082/ \
             -o /dev/null \
             -O /dev/null \
             >/dev/null && break
        OK=0
    done
    if [ 1 != "$OK" ]
    then
        exit_skip "Failed to launch Nexus"
    fi
    echo " DONE"
    if [ "${1:-no}" = "aggregator" ]
    then
        export CONF
	    echo -n "Running exchange aggregator ... (config: $CONF)"
        taler-exchange-aggregator \
            -L "$LOGLEVEL" \
            -t \
            -c "$CONF" \
            -y \
            2> "${MY_TMP_DIR}/aggregator.log" \
            || exit_fail "FAIL"
        echo " DONE"
        echo -n "Running exchange closer ..."
        taler-exchange-closer \
            -L "$LOGLEVEL" \
            -t \
            -c "$CONF" \
            2> "${MY_TMP_DIR}/closer.log" \
            || exit_fail "FAIL"
        echo " DONE"
        echo -n "Running exchange transfer ..."
        taler-exchange-transfer \
            -L "$LOGLEVEL" \
            -t \
            -c "$CONF" \
            2> "${MY_TMP_DIR}/transfer.log" \
            || exit_fail "FAIL"
        echo " DONE"
    fi
}

# actual audit run
function audit_only () {
    # Run the auditor!
    echo -n "Running audit(s) ... (conf is $CONF)"

    # Restart so that first run is always fresh, and second one is incremental
    taler-auditor-dbinit \
        -r \
        -c "$CONF"
    $VALGRIND taler-helper-auditor-aggregation \
              -L "$LOGLEVEL" \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-aggregation.json \
              2> test-audit-aggregation.log \
        || exit_fail "aggregation audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-aggregation \
              -L "$LOGLEVEL" \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-aggregation-inc.json \
              2> test-audit-aggregation-inc.log \
        || exit_fail "incremental aggregation audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-coins \
              -L "$LOGLEVEL" \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-coins.json \
              2> test-audit-coins.log \
        || exit_fail "coin audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-coins \
              -L "$LOGLEVEL" \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-coins-inc.json \
              2> test-audit-coins-inc.log \
        || exit_fail "incremental coin audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-deposits \
              -L "$LOGLEVEL" \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-deposits.json \
              2> test-audit-deposits.log \
        || exit_fail "deposits audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-deposits \
              -L "$LOGLEVEL" \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-deposits-inc.json \
              2> test-audit-deposits-inc.log \
        || exit_fail "incremental deposits audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-reserves \
              -i \
              -L "$LOGLEVEL" \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-reserves.json \
              2> test-audit-reserves.log \
        || exit_fail "reserves audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-reserves \
              -i \
              -L "$LOGLEVEL" \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-reserves-inc.json \
              2> test-audit-reserves-inc.log \
        || exit_fail "incremental reserves audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-wire \
              -i \
              -L "$LOGLEVEL" \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-wire.json \
              2> test-wire-audit.log \
        || exit_fail "wire audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-wire \
              -i \
              -L "$LOGLEVEL" \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-wire-inc.json \
              2> test-wire-audit-inc.log \
        || exit_fail "wire audit failed"
    echo -n "."
    echo " DONE"
}


# Cleanup to run after the auditor
function post_audit () {
    cleanup
    echo -n "TeXing ."
    taler-helper-auditor-render.py \
        test-audit-aggregation.json \
        test-audit-coins.json \
        test-audit-deposits.json \
        test-audit-reserves.json \
        test-audit-wire.json \
        < ../../contrib/auditor-report.tex.j2 \
        > test-report.tex \
        || exit_fail "Renderer failed"
    echo -n "."
    timeout 10 pdflatex test-report.tex \
            >/dev/null \
        || exit_fail "pdflatex failed"
    echo -n "."
    timeout 10 pdflatex test-report.tex \
            >/dev/null
    echo " DONE"
}


# Run audit process on current database, including report
# generation.  Pass "aggregator" as $1 to run
# $ taler-exchange-aggregator
# before auditor (to trigger pending wire transfers).
function run_audit () {
    pre_audit "${1:-no}"
    audit_only
    post_audit
}


# Do a full reload of the (original) database
function full_reload()
{
    echo -n "Doing full reload of the database... "
    dropdb "$DB" 2> /dev/null || true
    createdb -T template0 "$DB" \
        || exit_skip "could not create database $DB (at $PGHOST)"
    # Import pre-generated database, -q(ietly) using single (-1) transaction
    psql -Aqt "$DB" \
         -q \
         -1 \
         -f "${BASEDB}.sql" \
         > /dev/null \
        || exit_skip "Failed to load database $DB from ${BASEDB}.sql"
    echo "DONE"
}


function test_0() {
    echo "===========0: normal run with aggregator==========="
    run_audit aggregator

    echo "Checking output"
    # if an emergency was detected, that is a bug and we should fail
    echo -n "Test for emergencies... "
    jq -e .emergencies[0] < test-audit-coins.json > /dev/null && exit_fail "Unexpected emergency detected in ordinary run" || echo PASS
    echo -n "Test for deposit confirmation emergencies... "
    jq -e .deposit_confirmation_inconsistencies[0] < test-audit-deposits.json > /dev/null && exit_fail "Unexpected deposit confirmation inconsistency detected" || echo PASS
    echo -n "Test for emergencies by count... "
    jq -e .emergencies_by_count[0] < test-audit-coins.json > /dev/null && exit_fail "Unexpected emergency by count detected in ordinary run" || echo PASS

    echo -n "Test for wire inconsistencies... "
    jq -e .wire_out_amount_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected wire out inconsistency detected in ordinary run"
    jq -e .reserve_in_amount_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected reserve in inconsistency detected in ordinary run"
    jq -e .misattribution_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected misattribution inconsistency detected in ordinary run"
    jq -e .row_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected row inconsistency detected in ordinary run"
    jq -e .denomination_key_validity_withdraw_inconsistencies[0] < test-audit-reserves.json > /dev/null && exit_fail "Unexpected denomination key withdraw inconsistency detected in ordinary run"
    jq -e .row_minor_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected minor row inconsistency detected in ordinary run"
    jq -e .lag_details[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected lag detected in ordinary run"
    jq -e .wire_format_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected wire format inconsistencies detected in ordinary run"


    # TODO: check operation balances are correct (once we have all transaction types and wallet is deterministic)
    # TODO: check revenue summaries are correct (once we have all transaction types and wallet is deterministic)

    echo PASS

    LOSS=$(jq -r .total_bad_sig_loss < test-audit-aggregation.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong total bad sig loss from aggregation, got unexpected loss of $LOSS"
    fi
    LOSS=$(jq -r .irregular_loss < test-audit-coins.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong total bad sig loss from coins, got unexpected loss of $LOSS"
    fi
    LOSS=$(jq -r .total_bad_sig_loss < test-audit-reserves.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong total bad sig loss from reserves, got unexpected loss of $LOSS"
    fi

    echo -n "Test for wire amounts... "
    WIRED=$(jq -r .total_wire_in_delta_plus < test-audit-wire.json)
    if [ "$WIRED" != "TESTKUDOS:0" ]
    then
        exit_fail "Expected total wire delta plus wrong, got $WIRED"
    fi
    WIRED=$(jq -r .total_wire_in_delta_minus < test-audit-wire.json)
    if [ "$WIRED" != "TESTKUDOS:0" ]
    then
        exit_fail "Expected total wire delta minus wrong, got $WIRED"
    fi
    WIRED=$(jq -r .total_wire_out_delta_plus < test-audit-wire.json)
    if [ "$WIRED" != "TESTKUDOS:0" ]
    then
        exit_fail "Expected total wire delta plus wrong, got $WIRED"
    fi
    WIRED=$(jq -r .total_wire_out_delta_minus < test-audit-wire.json)
    if [ "$WIRED" != "TESTKUDOS:0" ]
    then
        exit_fail "Expected total wire delta minus wrong, got $WIRED"
    fi
    WIRED=$(jq -r .total_misattribution_in < test-audit-wire.json)
    if [ "$WIRED" != "TESTKUDOS:0" ]
    then
        exit_fail "Expected total misattribution in wrong, got $WIRED"
    fi
    echo "PASS"

    echo -n "Checking for unexpected arithmetic differences "
    LOSS=$(jq -r .total_arithmetic_delta_plus < test-audit-aggregation.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from aggregations, got unexpected plus of $LOSS"
    fi
    LOSS=$(jq -r .total_arithmetic_delta_minus < test-audit-aggregation.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from aggregation, got unexpected minus of $LOSS"
    fi
    LOSS=$(jq -r .total_arithmetic_delta_plus < test-audit-coins.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from coins, got unexpected plus of $LOSS"
    fi
    LOSS=$(jq -r .total_arithmetic_delta_minus < test-audit-coins.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from coins, got unexpected minus of $LOSS"
    fi
    LOSS=$(jq -r .total_arithmetic_delta_plus < test-audit-reserves.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from reserves, got unexpected plus of $LOSS"
    fi
    LOSS=$(jq -r .total_arithmetic_delta_minus < test-audit-reserves.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from reserves, got unexpected minus of $LOSS"
    fi

    jq -e .amount_arithmetic_inconsistencies[0] \
       < test-audit-aggregation.json \
       > /dev/null \
        && exit_fail "Unexpected arithmetic inconsistencies from aggregations detected in ordinary run"
    jq -e .amount_arithmetic_inconsistencies[0] \
       < test-audit-coins.json \
       > /dev/null \
        && exit_fail "Unexpected arithmetic inconsistencies from coins detected in ordinary run"
    jq -e .amount_arithmetic_inconsistencies[0] \
       < test-audit-reserves.json \
       > /dev/null \
        && exit_fail "Unexpected arithmetic inconsistencies from reserves detected in ordinary run"
    echo "PASS"

    echo -n "Checking for unexpected wire out differences "
    jq -e .wire_out_inconsistencies[0] \
       < test-audit-aggregation.json \
       > /dev/null \
        && exit_fail "Unexpected wire out inconsistencies detected in ordinary run"
    echo "PASS"

    # cannot easily undo aggregator, hence full reload
    full_reload
}


# Run without aggregator, hence auditor should detect wire
# transfer lag!
function test_1() {

    echo "===========1: normal run==========="
    run_audit

    echo "Checking output"
    # if an emergency was detected, that is a bug and we should fail
    echo -n "Test for emergencies... "
    jq -e .emergencies[0] \
       < test-audit-coins.json \
       > /dev/null \
        && exit_fail "Unexpected emergency detected in ordinary run" \
        || echo "PASS"
    echo -n "Test for emergencies by count... "
    jq -e .emergencies_by_count[0] \
       < test-audit-coins.json \
       > /dev/null \
        && exit_fail "Unexpected emergency by count detected in ordinary run" \
        || echo "PASS"

    echo -n "Test for wire inconsistencies... "
    jq -e .wire_out_amount_inconsistencies[0] \
       < test-audit-wire.json \
       > /dev/null \
        && exit_fail "Unexpected wire out inconsistency detected in ordinary run"
    jq -e .reserve_in_amount_inconsistencies[0] \
       < test-audit-wire.json \
       > /dev/null \
        && exit_fail "Unexpected reserve in inconsistency detected in ordinary run"
    jq -e .misattribution_inconsistencies[0] \
       < test-audit-wire.json \
       > /dev/null \
        && exit_fail "Unexpected misattribution inconsistency detected in ordinary run"
    jq -e .row_inconsistencies[0] \
       < test-audit-wire.json \
       > /dev/null \
        && exit_fail "Unexpected row inconsistency detected in ordinary run"
    jq -e .row_minor_inconsistencies[0] \
       < test-audit-wire.json \
       > /dev/null \
        && exit_fail "Unexpected minor row inconsistency detected in ordinary run"
    jq -e .wire_format_inconsistencies[0] \
       < test-audit-wire.json \
       > /dev/null \
        && exit_fail "Unexpected wire format inconsistencies detected in ordinary run"

    # TODO: check operation balances are correct (once we have all transaction types and wallet is deterministic)
    # TODO: check revenue summaries are correct (once we have all transaction types and wallet is deterministic)

    echo "PASS"

    echo -n "Test for wire amounts... "
    WIRED=$(jq -r .total_wire_in_delta_plus < test-audit-wire.json)
    if [ "$WIRED" != "TESTKUDOS:0" ]
    then
        exit_fail "Expected total wire delta plus wrong, got $WIRED"
    fi
    WIRED=$(jq -r .total_wire_in_delta_minus < test-audit-wire.json)
    if [ "$WIRED" != "TESTKUDOS:0" ]
    then
        exit_fail "Expected total wire delta minus wrong, got $WIRED"
    fi
    WIRED=$(jq -r .total_wire_out_delta_plus < test-audit-wire.json)
    if [ "$WIRED" != "TESTKUDOS:0" ]
    then
        exit_fail "Expected total wire delta plus wrong, got $WIRED"
    fi
    WIRED=$(jq -r .total_wire_out_delta_minus < test-audit-wire.json)
    if [ "$WIRED" != "TESTKUDOS:0" ]
    then
        exit_fail "Expected total wire delta minus wrong, got $WIRED"
    fi
    WIRED=$(jq -r .total_misattribution_in < test-audit-wire.json)
    if [ "$WIRED" != "TESTKUDOS:0" ]
    then
        exit_fail "Expected total misattribution in wrong, got $WIRED"
    fi

    # Database was unmodified, no need to undo
    echo "OK"
}



# Change recoup amount
function test_2() {

    echo "===========2: recoup amount inconsistency==========="
    echo "UPDATE exchange.recoup SET amount_val=5 WHERE recoup_uuid=1" | psql -Aqt "$DB"

    run_audit

    # Reserve balance is now wrong
    echo -n "Testing inconsistency detection... "
    AMOUNT=$(jq -r .reserve_balance_summary_wrong_inconsistencies[0].auditor < test-audit-reserves.json)
    if [ "$AMOUNT" != "TESTKUDOS:3" ]
    then
        exit_fail "Reserve auditor amount $AMOUNT is wrong"
    fi
    AMOUNT=$(jq -r .reserve_balance_summary_wrong_inconsistencies[0].exchange < test-audit-reserves.json)
    if [ "$AMOUNT" != "TESTKUDOS:0" ]
    then
        exit_fail "Reserve exchange amount $AMOUNT is wrong"
    fi
    # Coin spent exceeded coin's value
    AMOUNT=$(jq -r .amount_arithmetic_inconsistencies[0].auditor < test-audit-coins.json)
    if [ "$AMOUNT" != "TESTKUDOS:2" ]
    then
        exit_fail "Coin auditor amount $AMOUNT is wrong"
    fi
    AMOUNT=$(jq -r .amount_arithmetic_inconsistencies[0].exchange < test-audit-coins.json)
    if [ "$AMOUNT" != "TESTKUDOS:5" ]
    then
        exit_fail "Coin exchange amount $AMOUNT is wrong"
    fi
    echo "OK"

    # Undo database modification
    echo "UPDATE exchange.recoup SET amount_val=2 WHERE recoup_uuid=1" | psql -Aqt "$DB"

}


# Change recoup-refresh amount
function test_3() {

    echo "===========3: recoup-refresh amount inconsistency==========="
    echo "UPDATE exchange.recoup_refresh SET amount_val=5 WHERE recoup_refresh_uuid=1" | psql -Aqt "$DB"

    run_audit

    echo -n "Testing inconsistency detection... "
    # Coin spent exceeded coin's value
    AMOUNT=$(jq -r .total_arithmetic_delta_minus < test-audit-coins.json)
    if [ "$AMOUNT" != "TESTKUDOS:5" ]
    then
        exit_fail "Arithmetic delta minus amount $AMOUNT is wrong"
    fi
    AMOUNT=$(jq -r .total_arithmetic_delta_plus < test-audit-coins.json)
    if [ "$AMOUNT" != "TESTKUDOS:0" ]
    then
        exit_fail "Arithmetic delta plus amount $AMOUNT is wrong"
    fi
    echo "OK"

    # Undo database modification
    echo "UPDATE exchange.recoup_refresh SET amount_val=0 WHERE recoup_refresh_uuid=1" | psql -Aqt "$DB"

}


# Void recoup-refresh entry by 'unrevoking' denomination
function test_4() {

    echo "===========4: invalid recoup==========="
    echo "DELETE FROM exchange.denomination_revocations;" | psql -Aqt "$DB"

    run_audit

    echo -n "Testing inconsistency detection... "
    # Coin spent exceeded coin's value
    jq -e .bad_sig_losses[0] \
       < test-audit-coins.json \
       > /dev/null \
        || exit_fail "Bad recoup not detected"
    AMOUNT=$(jq -r .irregular_loss < test-audit-coins.json)
    if [ "$AMOUNT" == "TESTKUDOS:0" ]
    then
        exit_fail "Total bad sig losses are wrong"
    fi
    TAB=$(jq -r .row_inconsistencies[0].table < test-audit-reserves.json)
    if [ "$TAB" != "recoup" ]
    then
        exit_fail "Wrong table for row inconsistency, got $TAB"
    fi
    echo "OK"

    # Undo database modification (can't easily undo DELETE, so full reload)
    full_reload
}




# *************** Main test loop starts here **************


# Run all the tests against the database given in $1.
# Sets $fail to 0 on success, non-zero on failure.
function check_with_database()
{
    BASEDB="$1"
    # Configuration file to use
    CONF="$1.conf"
    echo "Running test suite with database $BASEDB using configuration $CONF"

    MASTER_PRIV_FILE="${BASEDB}.mpriv"
    taler-exchange-config -f \
                          -c "${CONF}" \
                          -s exchange-offline \
                          -o MASTER_PRIV_FILE \
                          -V "${MASTER_PRIV_FILE}"
    MASTER_PUB=$(gnunet-ecc -p "$MASTER_PRIV_FILE")

    echo "MASTER PUB is ${MASTER_PUB} using file ${MASTER_PRIV_FILE}"

    # Load database
    full_reload
    # Run test suite
    fail=0
    for i in $TESTS
    do
        "test_$i"
        if [ 0 != "$fail" ]
        then
            break
        fi
    done
    # echo "Cleanup (disabled, leaving database $DB behind)"
    dropdb "$DB"
}



# *************** Main logic starts here **************

# ####### Setup globals ######
# Postgres database to use
DB=revoke-basedb


# test required commands exist
echo "Testing for jq"
jq -h > /dev/null || exit_skip "jq required"
echo "Testing for faketime"
faketime -h > /dev/null \
    || exit_skip "faketime required"
echo "Testing for libeufin-bank"
libeufin-bank --help \
             >/dev/null \
             2> /dev/null \
             </dev/null \
    || exit_skip "libeufin-bank required"
echo "Testing for pdflatex"
which pdflatex > /dev/null </dev/null || exit_skip "pdflatex required"
echo "Testing for taler-wallet-cli"
taler-wallet-cli -h \
                 >/dev/null \
                 </dev/null \
                 2>/dev/null \
    || exit_skip "taler-wallet-cli required"

echo -n "Testing for Postgres "
# Available directly in path?
INITDB_BIN=$(command -v initdb) || true
if [[ -n "$INITDB_BIN" ]]; then
  echo "FOUND (in path) at $INITDB_BIN"
else
  HAVE_INITDB=$(find /usr -name "initdb" | head -1 2> /dev/null | grep postgres) || exit_skip " MISSING"
  echo "FOUND at " "$(dirname "$HAVE_INITDB")"
  INITDB_BIN=$(echo "$HAVE_INITDB" | grep bin/initdb | grep postgres | sort -n | tail -n1)
fi
echo -n "Setting up Postgres DB"
POSTGRES_PATH=$(dirname "$INITDB_BIN")
MY_TMP_DIR=$(mktemp -d /tmp/taler-auditor-basedbXXXXXX)
TMPDIR="${MY_TMP_DIR}/postgres/"
mkdir -p "$TMPDIR"
echo -n "Setting up Postgres DB at $TMPDIR ..."
"$INITDB_BIN" \
    --no-sync \
    --auth=trust \
    -D "${TMPDIR}" \
    > "${MY_TMP_DIR}/postgres-dbinit.log" \
    2> "${MY_TMP_DIR}/postgres-dbinit.err"
echo " DONE"
mkdir "${TMPDIR}/sockets"
echo -n "Launching Postgres service at $POSTGRES_PATH"
cat - >> "$TMPDIR/postgresql.conf" <<EOF
unix_socket_directories='${TMPDIR}/sockets'
fsync=off
max_wal_senders=0
synchronous_commit=off
wal_level=minimal
listen_addresses=''
EOF
grep -v host \
     < "$TMPDIR/pg_hba.conf" \
     > "$TMPDIR/pg_hba.conf.new"
mv "$TMPDIR/pg_hba.conf.new" "$TMPDIR/pg_hba.conf"
"${POSTGRES_PATH}/pg_ctl" \
    -D "$TMPDIR" \
    -l /dev/null \
    start \
    > "${MY_TMP_DIR}/postgres-start.log" \
    2> "${MY_TMP_DIR}/postgres-start.err"
echo " DONE"
PGHOST="$TMPDIR/sockets"
export PGHOST

echo "Generating fresh database at $MY_TMP_DIR"
if faketime -f '-1 d' ./generate-revoke-basedb.sh "$MY_TMP_DIR/$DB"
then
    check_with_database "$MY_TMP_DIR/$DB"
    if [ "x$fail" != "x0" ]
    then
        exit "$fail"
    else
        echo "Cleaning up $MY_TMP_DIR..."
        rm -rf "$MY_TMP_DIR" || echo "Removing $MY_TMP_DIR failed"
    fi
else
    echo "Generation failed"
fi

exit 0
