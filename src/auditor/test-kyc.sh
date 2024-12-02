#!/bin/bash
#
#  This file is part of TALER
#  Copyright (C) 2014-2023 Taler Systems SA
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
#
# shellcheck disable=SC2317
# shellcheck disable=SC1091
#
#
# Setup database which was generated from a perfectly normal
# exchange-wallet interaction with KYC enabled and transactions
# blocked due to KYC and run the auditor against it.
#
# Check that the auditor report is as expected.
#
# Requires 'jq' tool and Postgres superuser rights!
#
set -eu
#set -x

# Set of numbers for all the testcases.
# When adding new tests, increase the last number:
ALL_TESTS=$(seq 0 1)

# $TESTS determines which tests we should run.
# This construction is used to make it easy to
# only run a subset of the tests. To only run a subset,
# pass the numbers of the tests to run as the FIRST
# argument to test-kyc.sh, i.e.:
#
# $ test-kyc.sh "1 3"
#
# to run tests 1 and 3 only.  By default, all tests are run.
#
TESTS=${1:-$ALL_TESTS}

# Global variable to run the auditor processes under valgrind
# VALGRIND=valgrind
VALGRIND=""

# Number of seconds to let libeuifn background
# tasks apply a cycle of payment submission and
# history request.
LIBEUFIN_SETTLE_TIME=1

. setup.sh


# Cleanup exchange and libeufin between runs.
function cleanup()
{
    if test ! -z "${EPID:-}"
    then
        echo -n "Stopping exchange $EPID..."
        kill -TERM "$EPID"
        wait "$EPID" || true
        echo "DONE"
        unset EPID
    fi
    stop_libeufin
}

# Cleanup to run whenever we exit
function exit_cleanup()
{
    echo "Running exit-cleanup"
    if test ! -z "${POSTGRES_PATH:-}"
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
    wait || true
    echo "DONE"
}

# Install cleanup handler (except for kill -9)
trap exit_cleanup EXIT



# Operations to run before the actual audit
function pre_audit () {
    # Launch bank
    echo -n "Launching bank"
    launch_libeufin
    for n in $(seq 1 80)
    do
        echo -n "."
        sleep 0.1
        OK=1
        wget http://localhost:18082/ \
             -o /dev/null \
             -O /dev/null \
             >/dev/null \
            && break
        OK=0
    done
    if [ 1 != "$OK" ]
    then
        exit_skip "Failed to launch Sandbox"
    fi
    sleep "$LIBEUFIN_SETTLE_TIME"
    for n in $(seq 1 80)
    do
        echo -n "."
        sleep 0.1
        OK=1
        wget http://localhost:8082/ \
             -o /dev/null \
             -O /dev/null \
             >/dev/null \
            && break
        OK=0
    done
    if [ 1 != "$OK" ]
    then
        exit_skip "Failed to launch Nexus"
    fi
    echo " DONE"
    if test "${1:-no}" = "aggregator"
    then
        echo -n "Running exchange aggregator ..."
        taler-exchange-aggregator \
            -y \
            -L "INFO" \
            -t \
            -c "$CONF" \
            2> "${MY_TMP_DIR}/aggregator.log" \
            || exit_fail "FAIL"
        echo " DONE"
        echo -n "Running exchange closer ..."
        taler-exchange-closer \
            -L "INFO" \
            -t \
            -c "$CONF" \
            2> "${MY_TMP_DIR}/closer.log" \
            || exit_fail "FAIL"
        echo " DONE"
        echo -n "Running exchange transfer ..."
        taler-exchange-transfer \
            -L "INFO" \
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
    echo -n "Running audit(s) ..."

    # Restart so that first run is always fresh, and second one is incremental
    taler-auditor-dbinit \
        -r \
        -c "$CONF"
    $VALGRIND taler-helper-auditor-aggregation \
              -L DEBUG \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-aggregation.json \
              2> "${MY_TMP_DIR}/test-audit-aggregation.log" \
        || exit_fail "aggregation audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-aggregation \
              -L DEBUG \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-aggregation-inc.json \
              2> "${MY_TMP_DIR}/test-audit-aggregation-inc.log" \
        || exit_fail "incremental aggregation audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-coins \
              -L DEBUG \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-coins.json \
              2> "${MY_TMP_DIR}/test-audit-coins.log" \
        || exit_fail "coin audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-coins \
              -L DEBUG  \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-coins-inc.json \
              2> "${MY_TMP_DIR}/test-audit-coins-inc.log" \
        || exit_fail "incremental coin audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-deposits \
              -L DEBUG \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-deposits.json \
              2> "${MY_TMP_DIR}/test-audit-deposits.log" \
        || exit_fail "deposits audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-deposits \
              -L DEBUG \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-deposits-inc.json \
              2> "${MY_TMP_DIR}/test-audit-deposits-inc.log" \
        || exit_fail "incremental deposits audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-reserves \
              -i \
              -L DEBUG \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-reserves.json \
              2> "${MY_TMP_DIR}/test-audit-reserves.log" \
        || exit_fail "reserves audit failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-reserves \
              -i \
              -L DEBUG \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-reserves-inc.json \
              2> "${MY_TMP_DIR}/test-audit-reserves-inc.log" \
        || exit_fail "incremental reserves audit failed"
    echo -n "."
    rm -f "${MY_TMP_DIR}/test-wire-audit.log"
    thaw() {
        $VALGRIND taler-helper-auditor-wire \
                  -i \
                  -L DEBUG \
                  -c "$CONF" \
                  -m "$MASTER_PUB" \
                  > test-audit-wire.json \
                  2>> "${MY_TMP_DIR}/test-wire-audit.log"
    }
    thaw || ( echo -e " FIRST CALL TO taler-helper-auditor-wire FAILED,\nRETRY AFTER TWO SECONDS..." | tee -a "${MY_TMP_DIR}/test-wire-audit.log"
	      sleep 2
	      thaw || exit_fail "wire audit failed" )
    echo -n "."
    $VALGRIND taler-helper-auditor-wire \
              -i \
              -L DEBUG \
              -c "$CONF" \
              -m "$MASTER_PUB" \
              > test-audit-wire-inc.json \
              2> "${MY_TMP_DIR}/test-wire-audit-inc.log" \
        || exit_fail "wire audit inc failed"
    echo -n "."

    echo " DONE"
}


# Cleanup to run after the auditor
function post_audit () {
    taler-exchange-dbinit \
        -c "$CONF" \
        -g \
        || exit_fail "exchange DB GC failed"
    cleanup
    echo " DONE"
}


# Run audit process on current database, including report
# generation.  Pass "aggregator" as $1 to run
# $ taler-exchange-aggregator
# before auditor (to trigger pending wire transfers).
# Pass "drain" as $2 to run a drain operation as well.
function run_audit () {
    pre_audit "${1:-no}"
    if test "${2:-no}" = "drain"
    then
        echo -n "Starting exchange..."
        taler-exchange-httpd \
            -c "${CONF}" \
            -L INFO \
            2> "${MY_TMP_DIR}/exchange-httpd-drain.err" &
        EPID=$!

        # Wait for all services to be available
        for n in $(seq 1 50)
        do
            echo -n "."
            sleep 0.1
            OK=0
            # exchange
            wget "http://localhost:8081/seed" \
                 -o /dev/null \
                 -O /dev/null \
                 >/dev/null \
                || continue
            OK=1
            break
        done
        echo "... DONE."
        export CONF

        echo -n "Running taler-exchange-offline drain "

        taler-exchange-offline \
            -L DEBUG \
            -c "${CONF}" \
            drain TESTKUDOS:0.1 \
            exchange-account-1 payto://iban/DE360679?receiver-name=Exchange+Drain \
            upload \
            2> "${MY_TMP_DIR}/taler-exchange-offline-drain.log" \
            || exit_fail "offline draining failed"
        kill -TERM "$EPID"
        wait "$EPID" || true
        unset EPID
        echo -n "Running taler-exchange-drain ..."
        printf "\n" | taler-exchange-drain \
                        -L DEBUG \
                        -c "$CONF" \
                        2> "${MY_TMP_DIR}/taler-exchange-drain.log" \
            || exit_fail "FAIL"
        echo " DONE"
   fi
    echo -n "Running taler-exchange-transfer ..."
    taler-exchange-transfer \
        -L INFO \
        -t \
        -c "$CONF" \
        2> "${MY_TMP_DIR}/drain-transfer.log" \
        || exit_fail "FAIL"
    echo " DONE"

    audit_only
    post_audit
}


# Do a full reload of the (original) database
function full_reload()
{
    echo -n "Doing full reload of the database (loading ${BASEDB}.sql into $DB at $PGHOST)... "
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
    # Technically, this call shouldn't be needed as libeufin should already be stopped here...
    stop_libeufin
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

    jq -e .amount_arithmetic_inconsistencies[0] < test-audit-aggregation.json > /dev/null && exit_fail "Unexpected arithmetic inconsistencies from aggregations detected in ordinary run"
    jq -e .amount_arithmetic_inconsistencies[0] < test-audit-coins.json > /dev/null && exit_fail "Unexpected arithmetic inconsistencies from coins detected in ordinary run"
    jq -e .amount_arithmetic_inconsistencies[0] < test-audit-reserves.json > /dev/null && exit_fail "Unexpected arithmetic inconsistencies from reserves detected in ordinary run"
    echo "PASS"

    echo -n "Checking for unexpected wire out differences "
    jq -e .wire_out_inconsistencies[0] < test-audit-aggregation.json > /dev/null && exit_fail "Unexpected wire out inconsistencies detected in ordinary run"
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
        && exit_fail "Unexpected emergency detected in ordinary run";
    echo "PASS"
    echo -n "Test for emergencies by count... "
    jq -e .emergencies_by_count[0] \
       < test-audit-coins.json \
       > /dev/null \
        && exit_fail "Unexpected emergency by count detected in ordinary run"
    echo "PASS"

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

    echo -n "Check for lag detection... "

    # Check wire transfer lag reported (no aggregator!)
    # NOTE: This test is EXPECTED to fail for ~1h after
    # re-generating the test database as we do not
    # report lag of less than 1h (see GRACE_PERIOD in
    # taler-helper-auditor-wire.c)
    jq -e .lag_details[0] \
       < test-audit-wire.json \
       > /dev/null \
        || exit_fail "Lag not detected in run without aggregator"

    LAG=$(jq -r .total_amount_lag < test-audit-wire.json)
    if [ "$LAG" = "TESTKUDOS:0" ]
    then
        exit_fail "Expected total lag to be non-zero"
    fi
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



# *************** Main test loop starts here **************


# Run all the tests against the database given in $1.
# Sets $fail to 0 on success, non-zero on failure.
function check_with_database()
{
    BASEDB="$1"
    CONF="$1.conf"
    echo "Running test suite with database $BASEDB using configuration $CONF"
    MASTER_PRIV_FILE="${BASEDB}.mpriv"
    taler-exchange-config \
        -f \
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
        if test 0 != $fail
        then
            break
        fi
    done
    echo "Cleanup (disabled, leaving database $DB behind)"
    # dropdb $DB
}




# *************** Main logic starts here **************

# ####### Setup globals ######
# Postgres database to use (must match configuration file)
export DB="auditor-basedb"

# test required commands exist
echo "Testing for jq"
jq -h > /dev/null || exit_skip "jq required"
echo "Testing for faketime"
faketime -h > /dev/null || exit_skip "faketime required"
# NOTE: really check for all three libeufin commands?
echo "Testing for libeufin-bank"
libeufin-bank --help >/dev/null 2> /dev/null </dev/null || exit_skip "libeufin-bank required"
echo "Testing for taler-wallet-cli"
taler-wallet-cli -h >/dev/null </dev/null 2>/dev/null || exit_skip "taler-wallet-cli required"


echo -n "Testing for Postgres"
# Available directly in path?
INITDB_BIN=$(command -v initdb) || true
if [[ -n "$INITDB_BIN" ]]; then
  echo " FOUND (in path) at $INITDB_BIN"
else
    HAVE_INITDB=$(find /usr -name "initdb" | head -1 2> /dev/null | grep postgres) \
        || exit_skip " MISSING"
  echo " FOUND at $(dirname "$HAVE_INITDB")"
  INITDB_BIN=$(echo "$HAVE_INITDB" | grep bin/initdb | grep postgres | sort -n | tail -n1)
fi
POSTGRES_PATH=$(dirname "$INITDB_BIN")

MY_TMP_DIR=$(mktemp -d /tmp/taler-auditor-basedbXXXXXX)
echo "Using $MY_TMP_DIR for logging and temporary data"
TMPDIR="$MY_TMP_DIR/postgres"
mkdir -p "$TMPDIR"
echo -n "Setting up Postgres DB at $TMPDIR ..."
$INITDB_BIN \
    --no-sync \
    --auth=trust \
    -D "${TMPDIR}" \
    > "${MY_TMP_DIR}/postgres-dbinit.log" \
    2> "${MY_TMP_DIR}/postgres-dbinit.err"
echo "DONE"
SOCKETDIR="${TMPDIR}/sockets"
mkdir "${SOCKETDIR}"
echo -n "Launching Postgres service"
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

MYDIR="${MY_TMP_DIR}/basedb"
mkdir -p "${MYDIR}"
echo "Generating fresh database at $MYDIR"
if faketime -f '-1 d' ./generate-auditor-basedb.sh \
            -c generate-kyc-basedb.conf \
            -d "$MYDIR/$DB"
then
    echo -n "Reset 'auditor-basedb' database at $PGHOST ..."
    dropdb "auditor-basedb" >/dev/null 2>/dev/null || true
    createdb "auditor-basedb" || exit_skip "Could not create database '$BASEDB' at $PGHOST"
    echo " DONE"
    check_with_database "$MYDIR/$DB"
    if [ "$fail" != "0" ]
    then
        exit "$fail"
    fi
else
    echo "Generation failed"
    exit 1
fi

exit 0
