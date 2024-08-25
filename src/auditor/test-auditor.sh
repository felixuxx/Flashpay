#!/bin/bash
#
#  This file is part of TALER
#  Copyright (C) 2014-2024 Taler Systems SA
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
# exchange-wallet interaction and run the auditor against it.
#
# Check that the auditor report is as expected.
#
# Requires 'jq' tool and Postgres superuser rights!
set -eu
#set -x

# Set of numbers for all the testcases.
# When adding new tests, increase the last number:
ALL_TESTS=$(seq 0 33)

# $TESTS determines which tests we should run.
# This construction is used to make it easy to
# only run a subset of the tests. To only run a subset,
# pass the numbers of the tests to run as the FIRST
# argument to test-auditor.sh, i.e.:
#
# $ test-auditor.sh "1 3"
#
# to run tests 1 and 3 only.  By default, all tests are run.
#
TESTS=${1:-$ALL_TESTS}

export TALER_AUDITOR_TOKEN="secret-token:D4CST1Z6AHN3RT03M0T9NSTF2QGHTB5ZD2D3RYZB4HAWG8SX0JEFWBXCKXZHMB7Y3Z7KVFW0B3XPXD5BHCFP8EB0R6CNH2KAWDWVET0"
export TALER_AUDITOR_SALT="64S36D1N6RVKGC9J6CT3ADHQ70RK4CSM6MV3EE1H68SK8D9P6WW32CHK6GTKCDSR64S36D1N6RVKGC9J6CT3ADHQ70RK4CSM6MV3EE0"

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
    if [ ! -z "${EPID:-}" ]
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
    wait || true
    echo "DONE"
}

# Install cleanup handler (except for kill -9)
trap exit_cleanup EXIT


# Operations to run before the actual audit
function pre_audit () {
    # Launch bank
    echo -n "Launching libeufin-bank"
    export CONF
    export MY_TMP_DIR
    launch_libeufin
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
        exit_skip "Failed to launch libeufin-bank"
    fi
    echo " DONE"
    if [ "${1:-no}" = "aggregator" ]
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
              -t \
              > "${MY_TMP_DIR}/test-audit-aggregation.out" \
              2> "${MY_TMP_DIR}/test-audit-aggregation.err" \
        || exit_fail "aggregation audit failed (see ${MY_TMP_DIR}/test-audit-aggregation.*)"
    echo -n "."
    $VALGRIND taler-helper-auditor-aggregation \
              -L DEBUG \
              -c "$CONF" \
              -t \
              > "${MY_TMP_DIR}/test-audit-aggregation-inc.out" \
              2> "${MY_TMP_DIR}/test-audit-aggregation-inc.err" \
        || exit_fail "incremental aggregation audit failed (see ${MY_TMP_DIR}/test-audit-aggregation-inc.*)"
    echo -n "."
    $VALGRIND taler-helper-auditor-coins \
              -L DEBUG \
              -c "$CONF" \
              -t \
              > "${MY_TMP_DIR}/test-audit-coins.out" \
              2> "${MY_TMP_DIR}/test-audit-coins.err" \
        || exit_fail "coin audit failed (see ${MY_TMP_DIR}/test-audit-coins.*)"
    echo -n "."
    $VALGRIND taler-helper-auditor-coins \
              -L DEBUG  \
              -c "$CONF" \
              -t \
              > "${MY_TMP_DIR}/test-audit-coins-inc.out" \
              2> "${MY_TMP_DIR}/test-audit-coins-inc.err" \
        || exit_fail "incremental coin audit failed (see ${MY_TMP_DIR}/test-audit-coins-inc.*)"
    echo -n "."
    $VALGRIND taler-helper-auditor-deposits \
              -L DEBUG \
              -c "$CONF" \
              -t \
              > "${MY_TMP_DIR}/test-audit-deposits.out" \
              2> "${MY_TMP_DIR}/test-audit-deposits.err" \
        || exit_fail "deposits audit failed (see ${MY_TMP_DIR}/test-audit-deposits.*)"
    echo -n "."
    $VALGRIND taler-helper-auditor-deposits \
              -L DEBUG \
              -c "$CONF" \
              -t \
              > "${MY_TMP_DIR}/test-audit-deposits-inc.out" \
              2> "${MY_TMP_DIR}/test-audit-deposits-inc.err" \
        || exit_fail "incremental deposits audit failed (see ${MY_TMP_DIR}/test-audit-deposits-inc.*)"
    echo -n "."
    $VALGRIND taler-helper-auditor-reserves \
              -i \
              -L DEBUG \
              -c "$CONF" \
              -t \
              > "${MY_TMP_DIR}/test-audit-reserves.out" \
              2> "${MY_TMP_DIR}/test-audit-reserves.err" \
        || exit_fail "reserves audit failed (see ${MY_TMP_DIR}/test-audit-reserves.*)"
    echo -n "."
    $VALGRIND taler-helper-auditor-reserves \
              -i \
              -L DEBUG \
              -c "$CONF" \
              -t \
              > "${MY_TMP_DIR}/test-audit-reserves-inc.out" \
              2> "${MY_TMP_DIR}/test-audit-reserves-inc.err" \
        || exit_fail "incremental reserves audit failed (see ${MY_TMP_DIR}/test-audit-reserves-inc.*)"
    echo -n "."
    #$VALGRIND taler-helper-auditor-wire \
    #          -i \
    #          -L DEBUG \
    #          -c "$CONF" \
    #          -t \
    #          > "${MY_TMP_DIR}/test-audit-wire.out" \
    #          2> "${MY_TMP_DIR}/test-audit-wire.err" \
    #    || exit_fail "wire audit failed (see ${MY_TMP_DIR}/test-audit-wire.*)"
    #echo -n "."
    #$VALGRIND taler-helper-auditor-wire \
    #          -i \
    #          -L DEBUG \
    #          -c "$CONF" \
    #          -t \
    #          > "${MY_TMP_DIR}/test-audit-wire-inc.out" \
    #          2> "${MY_TMP_DIR}/test-audit-wire-inc.err" \
    #    || exit_fail "wire audit inc failed (see ${MY_TMP_DIR}/test-audit-wire-inc.*)"
    #echo -n "."
    $VALGRIND taler-helper-auditor-purses \
             -i \
             -L DEBUG \
             -c "$CONF" \
             -t \
             > "${MY_TMP_DIR}/test-audit-purses.out" \
             2> "${MY_TMP_DIR}/test-audit-purses.err" \
       || exit_fail "audit purses failed"
    echo -n "."
    $VALGRIND taler-helper-auditor-purses \
              -i \
              -L DEBUG \
              -c "$CONF" \
              -t \
              > "${MY_TMP_DIR}/test-audit-purses-inc.out" \
              2> "${MY_TMP_DIR}/test-audit-purses-inc.err" \
        || exit_fail "audit purses inc failed"
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
    if [ "${2:-no}" = "drain" ]
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
            exchange-account-1 payto://iban/SANDBOXX/DE360679?receiver-name=Exchange+Drain \
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

        echo -n "Running taler-exchange-transfer ..."
        taler-exchange-transfer \
            -L INFO \
            -t \
            -c "$CONF" \
            2> "${MY_TMP_DIR}/drain-transfer.log" \
            || exit_fail "FAIL"
        echo " DONE"
    fi
    audit_only
    post_audit
}


# Do a full reload of the (original) database
function full_reload()
{
    echo -n "Doing full reload of the database (loading ${BASEDB}.sql into $DB at $PGHOST)... "
    dropdb -f "$DB" 2> /dev/null || true
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

function run_auditor_httpd() {
  echo -n "Starting auditor..."
              taler-auditor-httpd \
                  -c "${CONF}" \
                  -L INFO \
                  2> "${MY_TMP_DIR}/auditor-httpd-drain.err" &
              APID=$!

              # Wait for all services to be available
              for n in $(seq 1 50)
              do
                  echo -n "."
                  sleep 0.1
                  OK=0
                  # exchange
                  wget "http://localhost:8083/seed" \
                       -o /dev/null \
                       -O /dev/null \
                       >/dev/null \
                      || continue
                  OK=1
                  break
              done
              echo "... DONE."
              export CONF
}

function stop_auditor_httpd() {
if [ ! -z "${APID:-}" ]
    then
        echo -n "Stopping auditor $APID..."
        kill -TERM "$APID"
        wait "$APID" || true
        echo "DONE"
        unset APID
    fi
}

function check_auditor_running() {
  ARUNSTATUS=$(curl -Is http://localhost:8083/config | head -1)
  if [ ! -z "${ARUNSTATUS:-}" ]
    then
      echo "Auditor running"
    else
      echo "Auditor not running, starting it"
      run_auditor_httpd
  fi
  unset ARUNSTATUS
}

function call_endpoint() {
  if [ ! -z ${2+x} ]
   then
     curl -s -H "Accept: application/json" -H "Authorization: Bearer ${TALER_AUDITOR_TOKEN}" -o "${MY_TMP_DIR}/${2}.json" "localhost:8083/monitoring/${1}?limit=50&balance_key=${2}"
   else
     curl -s -H "Accept: application/json" -H "Authorization: Bearer ${TALER_AUDITOR_TOKEN}" -o "${MY_TMP_DIR}/${1}.json" "localhost:8083/monitoring/${1}?limit=50"
   fi
}

function test_0() {

    echo "===========0: normal run with aggregator==========="
    run_audit aggregator
    check_auditor_running

    echo "Checking output"

    # if an emergency was detected, that is a bug and we should fail
    echo -n "Test for emergencies... "
    call_endpoint "emergency"
    jq -e .emergency[0] < ${MY_TMP_DIR}/emergency.json > /dev/null && exit_fail "Unexpected emergency detected in ordinary run"
    echo "PASS"
    echo -n "Test for deposit confirmation emergencies... "
    call_endpoint "deposit-confirmation"
    jq -e .deposit_confirmation[0] < ${MY_TMP_DIR}/deposit-confirmation.json > /dev/null && exit_fail "Unexpected deposit confirmation inconsistency detected"
    echo "PASS"
    echo -n "Test for emergencies by count... "
    call_endpoint "emergency-by-count"
    jq -e .emergency_by_count[0] < ${MY_TMP_DIR}/emergency-by-count.json > /dev/null && exit_fail "Unexpected emergency by count detected in ordinary run"
    echo "PASS"

    echo -n "Test for wire inconsistencies... "
    call_endpoint "denomination-key-validity-withdraw-inconsistency"
    jq -e .denomination_key_validity_withdraw_inconsistency[0] < ${MY_TMP_DIR}/denomination-key-validity-withdraw-inconsistency.json > /dev/null && exit_fail "Unexpected denomination key withdraw inconsistency detected in ordinary run"
    echo "PASS"

    # Just to test the endpoint and for logging ...
    call_endpoint "balances"

    call_endpoint "balances" "aggregation_total_bad_sig_loss"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/aggregation_total_bad_sig_loss.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong total bad sig loss from aggregation, got unexpected loss of '$LOSS'"
    fi

    call_endpoint "balances" "coin_irregular_loss"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/coin_irregular_loss.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong total bad sig loss from coins, got unexpected loss of '$LOSS'"
    fi

    call_endpoint "balances" "reserves_total_bad_sig_loss"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/reserves_total_bad_sig_loss.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong total bad sig loss from reserves, got unexpected loss of '$LOSS'"
    fi

    #echo -n "Test for wire amounts... "
    #WIRED=$(jq -r .total_wire_in_delta_plus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total wire delta plus wrong, got $WIRED"
    #fi
    #WIRED=$(jq -r .total_wire_in_delta_minus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total wire delta minus wrong, got $WIRED"
    #fi
    #WIRED=$(jq -r .total_wire_out_delta_plus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total wire delta plus wrong, got $WIRED"
    #fi
    #WIRED=$(jq -r .total_wire_out_delta_minus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total wire delta minus wrong, got $WIRED"
    #fi
    #WIRED=$(jq -r .total_misattribution_in < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total misattribution in wrong, got $WIRED"
    #fi
    #echo "PASS"

    echo -n "Checking for unexpected arithmetic differences "
    call_endpoint "balances" "aggregation_total_arithmetic_delta_plus"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/aggregation_total_arithmetic_delta_plus.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from aggregations, got unexpected plus of '$LOSS'"
    fi
    call_endpoint "balances" "aggregation_total_arithmetic_delta_minus"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/aggregation_total_arithmetic_delta_minus.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from aggregation, got unexpected minus of '$LOSS'"
    fi
    call_endpoint "balances" "coins_total_arithmetic_delta_plus"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/coins_total_arithmetic_delta_plus.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from coins, got unexpected plus of $LOSS"
    fi
    call_endpoint "balances" "coins_total_arithmetic_delta_minus"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/coins_total_arithmetic_delta_minus.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from coins, got unexpected minus of $LOSS"
    fi
    call_endpoint "balances" "reserves_total_arithmetic_delta_plus"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/reserves_total_arithmetic_delta_plus.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from reserves, got unexpected plus of $LOSS"
    fi
    call_endpoint "balances" "reserves_total_arithmetic_delta_minus"

    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/reserves_total_arithmetic_delta_minus.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from reserves, got unexpected minus of $LOSS"
    fi

    jq -e .amount_arithmetic_inconsistency[0] < ${MY_TMP_DIR}/test-audit-aggregation.out > /dev/null && exit_fail "Unexpected arithmetic inconsistencies from aggregations detected in ordinary run"
    jq -e .amount_arithmetic_inconsistency[0] < ${MY_TMP_DIR}/test-audit-coins.out > /dev/null && exit_fail "Unexpected arithmetic inconsistencies from coins detected in ordinary run"
    jq -e .amount_arithmetic_inconsistency[0] < ${MY_TMP_DIR}/test-audit-reserves.out > /dev/null && exit_fail "Unexpected arithmetic inconsistencies from reserves detected in ordinary run"
    echo "PASS"

    echo -n "Checking for unexpected wire out differences "
    call_endpoint "wire-out-inconsistency"
    jq -e .wire_out_inconsistency[0] < "${MY_TMP_DIR}/wire-out-inconsistency.json" > /dev/null && exit_fail "Unexpected wire out inconsistencies detected in ordinary run"
    echo "PASS"

    # cannot easily undo aggregator, hence full reload
    full_reload
    cleanup
}


# Run without aggregator, hence auditor should detect wire
# transfer lag!
function test_1() {

    echo "===========1: normal run==========="
    run_audit
    check_auditor_running

    echo "Checking output"
    # if an emergency was detected, that is a bug and we should fail

    call_endpoint "emergency"
    call_endpoint "emergency-by-count"

    echo -n "Test for emergencies... "
    jq -e .emergency[0] \
        < ${MY_TMP_DIR}/emergency.json \
        > /dev/null && exit_fail "Unexpected emergency detected in ordinary run" || echo PASS

    echo -n "Test for emergencies by count... "
    jq -e .emergency_by_count[0] \
        < ${MY_TMP_DIR}/emergency-by-count.json \
        > /dev/null && exit_fail "Unexpected emergency by count detected in ordinary run" || echo PASS

    #echo -n "Test for wire inconsistencies... "
    #jq -e .wire_out_amount_inconsistencies[0] \
    #   < test-audit-wire.json \
    #   > /dev/null \
    #    && exit_fail "Unexpected wire out inconsistency detected in ordinary run"
    #jq -e .reserve_in_amount_inconsistencies[0] \
    #   < test-audit-wire.json \
    #   > /dev/null \
    #    && exit_fail "Unexpected reserve in inconsistency detected in ordinary run"
    #jq -e .misattribution_inconsistencies[0] \
    #   < test-audit-wire.json \
    #   > /dev/null \
    #    && exit_fail "Unexpected misattribution inconsistency detected in ordinary run"
    #jq -e .row_inconsistencies[0] \
    #   < test-audit-wire.json \
    #   > /dev/null \
    #    && exit_fail "Unexpected row inconsistency detected in ordinary run"
    #jq -e .row_minor_inconsistencies[0] \
    #   < test-audit-wire.json \
    #   > /dev/null \
    #    && exit_fail "Unexpected minor row inconsistency detected in ordinary run"
    #jq -e .wire_format_inconsistencies[0] \
    #   < test-audit-wire.json \
    #   > /dev/null \
    #    && exit_fail "Unexpected wire format inconsistencies detected in ordinary run"

    # TODO: check operation balances are correct (once we have all transaction types and wallet is deterministic)
    # TODO: check revenue summaries are correct (once we have all transaction types and wallet is deterministic)

    echo "PASS"

    echo -n "Check for lag detection... "

    # Check wire transfer lag reported (no aggregator!)
    # NOTE: This test is EXPECTED to fail for ~1h after
    # re-generating the test database as we do not
    # report lag of less than 1h (see GRACE_PERIOD in
    # taler-helper-auditor-wire.c)
    #jq -e .lag_details[0] \
    #   < test-audit-wire.json \
    #   > /dev/null \
    #    || exit_fail "Lag not detected in run without aggregator"
#
    #LAG=$(jq -r .total_amount_lag < test-audit-wire.json)
    #if [ "$LAG" = "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total lag to be non-zero"
    #fi
    echo "PASS"
#
#
    #echo -n "Test for wire amounts... "
    #WIRED=$(jq -r .total_wire_in_delta_plus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total wire delta plus wrong, got $WIRED"
    #fi
    #WIRED=$(jq -r .total_wire_in_delta_minus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total wire delta minus wrong, got $WIRED"
    #fi
    #WIRED=$(jq -r .total_wire_out_delta_plus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total wire delta plus wrong, got $WIRED"
    #fi
    #WIRED=$(jq -r .total_wire_out_delta_minus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total wire delta minus wrong, got $WIRED"
    #fi
    #WIRED=$(jq -r .total_misattribution_in < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total misattribution in wrong, got $WIRED"
    #fi
    # Database was unmodified, no need to undo
}


# Change amount of wire transfer reported by exchange
function test_2() {

    echo "===========2: reserves_in inconsistency ==========="
    echo "UPDATE exchange.reserves_in SET credit.val=5 WHERE reserve_in_serial_id=1" \
        | psql -At "$DB"

    run_audit
    check_auditor_running

    #echo -n "Testing inconsistency detection... "
    #ROW=$(jq .reserve_in_amount_inconsistencies[0].row < test-audit-wire.json)
    #if [ "$ROW" != 1 ]
    #then
    #    exit_fail "Row $ROW is wrong"
    #fi
    #WIRED=$(jq -r .reserve_in_amount_inconsistencies[0].amount_wired < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:10" ]
    #then
    #    exit_fail "Amount wrong"
    #fi
    #EXPECTED=$(jq -r .reserve_in_amount_inconsistencies[0].amount_exchange_expected < test-audit-wire.json)
    #if [ "$EXPECTED" != "TESTKUDOS:5" ]
    #then
    #    exit_fail "Expected amount wrong"
    #fi
#
    #WIRED=$(jq -r .total_wire_in_delta_minus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Wrong total wire_in_delta_minus, got $WIRED"
    #fi
    #DELTA=$(jq -r .total_wire_in_delta_plus < test-audit-wire.json)
    #if [ "$DELTA" != "TESTKUDOS:5" ]
    #then
    #    exit_fail "Expected total wire delta plus wrong, got $DELTA"
    #fi
    #echo "PASS"

    # Undo database modification
    echo "UPDATE exchange.reserves_in SET credit.val=10 WHERE reserve_in_serial_id=1" \
        | psql -Aqt "$DB"
    stop_auditor_httpd
    full_reload
    cleanup
}


# Check for incoming wire transfer amount given being
# lower than what exchange claims to have received.
function test_3() {

    echo "===========3: reserves_in inconsistency==========="
    echo "UPDATE exchange.reserves_in SET credit.val=15 WHERE reserve_in_serial_id=1" \
        | psql -Aqt "$DB"

    run_audit
    check_auditor_running

    call_endpoint "reserve-balance-summary-wrong-inconsistency"
    EXPECTED=$(jq -e .reserve_balance_summary_wrong_inconsistency[0].auditor_amount \
                       < ${MY_TMP_DIR}/reserve-balance-summary-wrong-inconsistency.json)
    if [ $EXPECTED != '"TESTKUDOS:5.01"' ]
    then
        exit_fail "Expected reserve balance summary amount wrong, got $EXPECTED (auditor)"
    fi

    EXPECTED=$(jq -e .reserve_balance_summary_wrong_inconsistency[0].exchange_amount \
                           < ${MY_TMP_DIR}/reserve-balance-summary-wrong-inconsistency.json)
    if [ $EXPECTED != '"TESTKUDOS:0.01"' ]
    then
        exit_fail "Expected reserve balance summary amount wrong, got $EXPECTED (exchange)"
    fi

    #TODO: we receive 22.96 instead of 0 - check what it should be
    #call_endpoint "balances" "reserves_reserve_loss"
    #WIRED=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/reserves_reserve_loss.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Wrong total loss from insufficient balance, got $WIRED"
    #fi
    #TODO: fix helper wire
    #ROW=$(jq -e .reserve_in_amount_inconsistencies[0].row < test-audit-wire.json)
    #if [ "$ROW" != 1 ]
    #then
    #    exit_fail "Row wrong, got $ROW"
    #fi

    #WIRED=$(jq -r .reserve_in_amount_inconsistencies[0].amount_exchange_expected < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:15" ]
    #then
    #    exit_fail "Wrong amount_exchange_expected, got $WIRED"
    #fi

    #WIRED=$(jq -r .reserve_in_amount_inconsistencies[0].amount_wired < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:10" ]
    #then
    #    exit_fail "Wrong amount_wired, got $WIRED"
    #fi

    #WIRED=$(jq -r .total_wire_in_delta_minus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:5" ]
    #then
    #    exit_fail "Wrong total wire_in_delta_minus, got $WIRED"
    #fi

    #WIRED=$(jq -r .total_wire_in_delta_plus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Wrong total wire_in_delta_plus, got $WIRED"
    #fi

    # Undo database modification
    echo "UPDATE exchange.reserves_in SET credit.val=10 WHERE reserve_in_serial_id=1" | psql -Aqt "$DB"
    stop_auditor_httpd
    full_reload
    cleanup
}


# Check for incoming wire transfer amount given being
# lower than what exchange claims to have received.
function test_4() {
# TODO : may need to be restructured, as db seems to have done
    echo "===========4: deposit wire target wrong================="
#    # Original target bank account was 43, changing to 44
#    # TODO: ask grothoff check if I correctly chose table coin_deposit
#
#    SERIALE=$(echo "SELECT coin_deposit_serial_id FROM exchange.coin_deposits WHERE (amount_with_fee).val=3 ORDER BY coin_deposit_serial_id LIMIT 1;" | psql "$DB" -Aqt)
#
#    #SERIAL=$(echo "SELECT coin_deposit_serial_id FROM exchange.coin_deposits WHERE (amount_with_fee).val=3 AND (amount_with_fee).frac=0 ORDER BY coin_deposit_serial_id LIMIT 1;" | psql "$DB" -Aqt)
#    echo $SERIALE
#    OLD_WIRE_ID=$(echo "SELECT coin_sig FROM exchange.coin_deposits WHERE coin_deposit_serial_id=${SERIALE};"  | psql "$DB" -Aqt)
#    #OLD_WIRE_ID=$(echo "SELECT wire_target_h_payto FROM exchange.deposits WHERE deposit_serial_id=${SERIAL};"  | psql "$DB" -Aqt)
## shellcheck disable=SC2028
#    echo "INSERT INTO exchange.wire_targets (payto_uri, wire_target_h_payto) VALUES ('payto://x-taler-bank/localhost/testuser-xxlargtp', '\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660b');" \
#        | psql "$DB" \
#               -Aqt \
#               > /dev/null
## shellcheck disable=SC2028
#    #echo "UPDATE exchange.deposits SET wire_target_h_payto='\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660b' WHERE deposit_serial_id=${SERIAL}" \
#     #   | psql -Aqt "$DB"
#    echo "UPDATE exchange.coin_deposits SET coin_sig='\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660b' WHERE coin_deposit_serial_id=${SERIALE}" \
#        | psql -Aqt "$DB"
#
#    run_audit
#    check_auditor_running
#
#    echo -n "Testing inconsistency detection... "
#
#    call_endpoint "bad-sig-losses"
#    jq -e .bad_sig_losses[0] < ${MY_TMP_DIR}/bad-sig-losses.json > /dev/null || exit_fail "Bad signature not detected"
#
#    ROW=$(jq -e .bad_sig_losses[0].row < ${MY_TMP_DIR}/bad-sig-losses.json)
#    if [ $ROW != "${SERIALE}" ]
#    then
#        exit_fail "Row wrong, got $ROW"
#    fi
#
#    LOSS=$(jq -r .bad_sig_losses[0].loss < ${MY_TMP_DIR}/bad-sig-losses.json)
#    if [ $LOSS != '"TESTKUDOS:3"' ]
#    then
#        exit_fail "Wrong deposit bad signature loss, got $LOSS"
#    fi
#
#    OP=$(jq -r .bad_sig_losses[0].operation < ${MY_TMP_DIR}/bad-sig-losses.json)
#    if [ $OP != "deposit" ]
#    then
#        exit_fail "Wrong operation, got $OP"
#    fi
#
#    #LOSS=$(jq -r .irregular_loss < test-audit-coins.json)
#    #if [ "$LOSS" != "TESTKUDOS:3" ]
#    #then
#    #    exit_fail "Wrong total bad sig loss, got $LOSS"
#    #fi
#
#    echo PASS
#    # Undo:
#    #echo "UPDATE exchange.deposits SET wire_target_h_payto='$OLD_WIRE_ID' WHERE deposit_serial_id=${SERIAL}" | psql -Aqt "$DB"
#    echo "UPDATE exchange.deposits SET coin_sig='$OLD_WIRE_ID' WHERE coin_deposit_serial_id=${SERIALE}" | psql -Aqt "$DB"
#
#    stop_auditor_httpd
#    full_reload
#    cleanup
}


# Test where h_contract_terms in the deposit table is wrong
# (=> bad signature)
function test_5() {
    echo "===========5: deposit contract hash wrong================="
    # TODO: may need to be restructured
    # Modify h_wire hash, so it is inconsistent with 'wire'
#    SERIAL=$(echo "SELECT deposit_serial_id FROM exchange.deposits WHERE amount_with_fee_val=3 AND amount_with_fee_frac=0 ORDER BY deposit_serial_id LIMIT 1" | psql "$DB" -Aqt)
#    OLD_H=$(echo "SELECT h_contract_terms FROM exchange.deposits WHERE deposit_serial_id=$SERIAL;" | psql "$DB" -Aqt)
## shellcheck disable=SC2028
#    echo "UPDATE exchange.deposits SET h_contract_terms='\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d5' WHERE deposit_serial_id=$SERIAL" \
#        | psql -Aqt "$DB"
#
#    run_audit
#
#    echo -n "Checking bad signature detection... "
#    ROW=$(jq -e .bad_sig_losses[0].row < test-audit-coins.json)
#    if [ "$ROW" != "$SERIAL" ]
#    then
#        exit_fail "Row wrong, got $ROW"
#    fi
#
#    LOSS=$(jq -r .bad_sig_losses[0].loss < test-audit-coins.json)
#    if [ "$LOSS" != "TESTKUDOS:3" ]
#    then
#        exit_fail "Wrong deposit bad signature loss, got $LOSS"
#    fi
#
#    OP=$(jq -r .bad_sig_losses[0].operation < test-audit-coins.json)
#    if [ "$OP" != "deposit" ]
#    then
#        exit_fail "Wrong operation, got $OP"
#    fi
#
#    LOSS=$(jq -r .irregular_loss < test-audit-coins.json)
#    if [ "$LOSS" != "TESTKUDOS:3" ]
#    then
#        exit_fail "Wrong total bad sig loss, got $LOSS"
#    fi
#    echo PASS
#
#    # Undo:
#    echo "UPDATE exchange.deposits SET h_contract_terms='${OLD_H}' WHERE deposit_serial_id=$SERIAL" | psql -Aqt "$DB"

}


# Test where denom_sig in known_coins table is wrong
# (=> bad signature)
function test_6() {
    echo "===========6: known_coins signature wrong================="
    # Modify denom_sig, so it is wrong
    OLD_SIG=$(echo 'SELECT denom_sig FROM exchange.known_coins LIMIT 1;' | psql "$DB" -Aqt)
    COIN_PUB=$(echo "SELECT coin_pub FROM exchange.known_coins WHERE denom_sig='$OLD_SIG';"  | psql "$DB" -Aqt)
# shellcheck disable=SC2028
    echo "UPDATE exchange.known_coins SET denom_sig='\x0000000100000000287369672d76616c200a2028727361200a2020287320233542383731423743393036444643303442424430453039353246413642464132463537303139374131313437353746324632323332394644443146324643333445393939413336363430334233413133324444464239413833353833464536354442374335434445304441453035374438363336434541423834463843323843344446304144363030343430413038353435363039373833434431333239393736423642433437313041324632414132414435413833303432434346314139464635394244434346374436323238344143354544364131373739463430353032323241373838423837363535453434423145443831364244353638303232413123290a2020290a20290b' WHERE coin_pub='$COIN_PUB'" \
        | psql -Aqt "$DB"

    run_audit
    check_auditor_running

    call_endpoint "bad-sig-losses"
    ROW=$(jq -e .bad_sig_losses[0].row_id < ${MY_TMP_DIR}/bad-sig-losses.json)
    if [ "$ROW" != "1" ]
    then
        exit_fail "Row wrong, got $ROW"
    fi

    LOSS=$(jq -r .bad_sig_losses[0].loss < ${MY_TMP_DIR}/bad-sig-losses.json)
    if [ "$LOSS" == "TESTKUDOS:0" ]
    then
        exit_fail "Wrong deposit bad signature loss, got $LOSS"
    fi

    OP=$(jq -r .bad_sig_losses[0].operation < ${MY_TMP_DIR}/bad-sig-losses.json)
    if [ "$OP" != "melt" ]
    then
        exit_fail "Wrong operation, got $OP"
    fi

    call_endpoint "balances" "coin_irregular_loss"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/coin_irregular_loss.json)
    if [ "$LOSS" == "TESTKUDOS:0" ]
    then
        exit_fail "Wrong total bad sig loss, got $LOSS"
    fi

     #Undo
    echo "UPDATE exchange.known_coins SET denom_sig='$OLD_SIG' WHERE coin_pub='$COIN_PUB'" | psql -Aqt "$DB"
    stop_auditor_httpd
    full_reload
    cleanup

}


# Test where h_wire in the deposit table is wrong
function test_7() {
    echo "===========7: reserves_out signature wrong================="
    # Modify reserve_sig, so it is bogus
    HBE=$(echo 'SELECT h_blind_ev FROM exchange.reserves_out LIMIT 1;' | psql "$DB" -Aqt)
    OLD_SIG=$(echo "SELECT reserve_sig FROM exchange.reserves_out WHERE h_blind_ev='$HBE';" | psql "$DB" -Aqt)
    A_VAL=$(echo "SELECT (amount_with_fee).val FROM exchange.reserves_out WHERE h_blind_ev='$HBE';" | psql "$DB" -Aqt)
    A_FRAC=$(echo "SELECT (amount_with_fee).frac FROM exchange.reserves_out WHERE h_blind_ev='$HBE';" | psql "$DB" -Aqt)
    # Normalize, we only deal with cents in this test-case
    A_FRAC=$(( A_FRAC / 1000000))
    # shellcheck disable=SC2028
    echo "UPDATE exchange.reserves_out SET reserve_sig='\x9ef381a84aff252646a157d88eded50f708b2c52b7120d5a232a5b628f9ced6d497e6652d986b581188fb014ca857fd5e765a8ccc4eb7e2ce9edcde39accaa4b' WHERE h_blind_ev='$HBE'" \
        | psql -Aqt "$DB"

    run_audit
    check_auditor_running

    call_endpoint "bad-sig-losses"
    OP=$(jq -r .bad_sig_losses[0].operation < ${MY_TMP_DIR}/bad-sig-losses.json)
    if [ "$OP" != "withdraw" ]
    then
        exit_fail "Wrong operation, got $OP"
    fi

    call_endpoint "balances" "reserves_total_bad_sig_loss"
    LOSS=$(jq -r .bad_sig_losses[0].loss < ${MY_TMP_DIR}/bad-sig-losses.json)
    LOSS_TOTAL=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/reserves_total_bad_sig_loss.json)
    if [ "$LOSS" != "$LOSS_TOTAL" ]
    then
        exit_fail "Expected loss $LOSS and total loss $LOSS_TOTAL do not match"
    fi
    if [ "$A_FRAC" != 0 ]
    then
        if [ "$A_FRAC" -lt 10 ]
        then
            A_PREV="0"
        else
            A_PREV=""
        fi
        if [ "$LOSS" != "TESTKUDOS:$A_VAL.$A_PREV$A_FRAC" ]
        then
            exit_fail "Expected loss TESTKUDOS:$A_VAL.$A_PREV$A_FRAC but got $LOSS"
        fi
    else
        if [ "$LOSS" != "TESTKUDOS:$A_VAL" ]
        then
            exit_fail "Expected loss TESTKUDOS:$A_VAL but got $LOSS"
        fi
    fi

    # Undo:
    echo "UPDATE exchange.reserves_out SET reserve_sig='$OLD_SIG' WHERE h_blind_ev='$HBE'" | psql -Aqt "$DB"
    stop_auditor_httpd
    full_reload
    cleanup
}


# Test wire transfer subject disagreement!
function test_8() {

    echo "===========8: wire-transfer-subject disagreement==========="
    # Technically, this call shouldn't be needed, as libeufin should already be stopped here.
    stop_libeufin
    #TODO: see fixme
    echo "FIXME: test needs update to new libeufin-bank schema"
    #exit 0
    #OLD_ID=$(echo "SELECT id FROM NexusBankTransactions WHERE amount='10' AND currency='TESTKUDOS' ORDER BY id LIMIT 1;" | psql "${DB}" -Aqt) \
    #    || exit_fail "Failed to SELECT FROM NexusBankTransactions nexus DB!"
    #OLD_WTID=$(echo "SELECT \"reservePublicKey\" FROM TalerIncomingPayments WHERE payment='$OLD_ID';" \
    #               | psql "${DB}" -Aqt)
    #NEW_WTID="CK9QBFY972KR32FVA1MW958JWACEB6XCMHHKVFMCH1A780Q12SVG"
    #echo "UPDATE TalerIncomingPayments SET \"reservePublicKey\"='$NEW_WTID' WHERE payment='$OLD_ID';" \
    #    | psql "${DB}" -q \
    #    || exit_fail "Failed to update TalerIncomingPayments"

    run_audit
    check_auditor_running

    #TODO: fix audit wire
    #echo -n "Testing inconsistency detection... "
    #DIAG=$(jq -r .reserve_in_amount_inconsistencies[0].diagnostic < test-audit-wire.json)
    #if [ "x$DIAG" != "xwire subject does not match" ]
    #then
    #    exit_fail "Diagnostic wrong: $DIAG (0)"
    #fi
    #WTID=$(jq -r .reserve_in_amount_inconsistencies[0].reserve_pub < test-audit-wire.json)
    #if [ "$WTID" != "$OLD_WTID" ] && [ "$WTID" != "$NEW_WTID" ]
    #then
    #    exit_fail "WTID reported wrong: $WTID (wanted $OLD_WTID or $NEW_WTID)"
    #fi
    #EX_A=$(jq -r .reserve_in_amount_inconsistencies[0].amount_exchange_expected < test-audit-wire.json)
    #if [ "$WTID" = "$OLD_WTID" ] && [ "$EX_A" != "TESTKUDOS:10" ]
    #then
    #    exit_fail "Amount reported wrong: $EX_A"
    #fi
    #if [ "$WTID" = "$NEW_WTID" ] && [ "$EX_A" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Amount reported wrong: $EX_A"
    #fi
    #DIAG=$(jq -r .reserve_in_amount_inconsistencies[1].diagnostic < test-audit-wire.json)
    #if [ "$DIAG" != "wire subject does not match" ]
    #then
    #    exit_fail "Diagnostic wrong: $DIAG (1)"
    #fi
    #WTID=$(jq -r .reserve_in_amount_inconsistencies[1].reserve_pub < test-audit-wire.json)
    #if [ "$WTID" != "$OLD_WTID" ] && [ "$WTID" != "$NEW_WTID" ]
    #then
    #    exit_fail "WTID reported wrong: $WTID (wanted: $NEW_WTID or $OLD_WTID)"
    #fi
    #EX_A=$(jq -r .reserve_in_amount_inconsistencies[1].amount_exchange_expected < test-audit-wire.json)
    #if [ "$WTID" = "$OLD_WTID" ] && [ "$EX_A" != "TESTKUDOS:10" ]
    #then
    #    exit_fail "Amount reported wrong: $EX_A"
    #fi
    #if [ "$WTID" = "$NEW_WTID" ] && [ "$EX_A" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Amount reported wrong: $EX_A"
    #fi
#
    #WIRED=$(jq -r .total_wire_in_delta_minus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:10" ]
    #then
    #    exit_fail "Wrong total wire_in_delta_minus, got $WIRED"
    #fi
    #DELTA=$(jq -r .total_wire_in_delta_plus < test-audit-wire.json)
    #if [ "$DELTA" != "TESTKUDOS:10" ]
    #then
    #    exit_fail "Expected total wire delta plus wrong, got $DELTA"
    #fi
    #echo "PASS"

    # Undo database modification
    #echo "UPDATE TalerIncomingPayments SET \"reservePublicKey\"='$OLD_WTID' WHERE payment='$OLD_ID';" \
    #    | psql "${DB}" -q
    stop_auditor_httpd
    full_reload
    cleanup
}


# Test wire origin disagreement!
function test_9() {

    echo "===========9: wire-origin disagreement==========="
    # Technically, this call shouldn't be needed, as libeufin should already be stopped here.
    stop_libeufin
    #TODO: see FIXME
    echo "FIXME: test needs update to new libeufin-bank schema"
    #exit 0
    #OLD_ID=$(echo "SELECT id FROM NexusBankTransactions WHERE amount='10' AND currency='TESTKUDOS' ORDER BY id LIMIT 1;" | psql "${DB}" -Aqt)
    #OLD_ACC=$(echo 'SELECT "incomingPaytoUri" FROM TalerIncomingPayments WHERE payment='"'$OLD_ID';" | psql "${DB}" -Aqt)
    #echo "UPDATE TalerIncomingPayments SET \"incomingPaytoUri\"='payto://iban/SANDBOXX/DE144373?receiver-name=New+Exchange+Company' WHERE payment='$OLD_ID';" \
    #    | psql "${DB}" -q

    run_audit
    check_auditor_running

    #TODO: fix helper wire
    #echo -n "Testing inconsistency detection... "
    #AMOUNT=$(jq -r .misattribution_in_inconsistencies[0].amount < test-audit-wire.json)
    #if test "x$AMOUNT" != "xTESTKUDOS:10"
    #then
    #    exit_fail "Reported amount wrong: $AMOUNT"
    #fi
    #AMOUNT=$(jq -r .total_misattribution_in < test-audit-wire.json)
    #if test "x$AMOUNT" != "xTESTKUDOS:10"
    #then
    #    exit_fail "Reported total amount wrong: $AMOUNT"
    #fi
    echo PASS

    # Undo database modification
    #echo "UPDATE TalerIncomingPayments SET \"incomingPaytoUri\"='$OLD_ACC' WHERE payment='$OLD_ID';" \
    #    | psql "${DB}" -q
    stop_auditor_httpd
    full_reload
    cleanup
}


# Test wire_in timestamp disagreement!
function test_10() {
    NOW_MS=$(date +%s)000
    echo "===========10: wire-timestamp disagreement==========="
    # Technically, this call shouldn't be needed, as libeufin should already be stopped here.
    stop_libeufin
    #TODO: see fixme
    #echo "FIXME: test needs update to new libeufin-bank schema"
    #exit 0
    #OLD_ID=$(echo "SELECT id FROM NexusBankTransactions WHERE amount='10' AND currency='TESTKUDOS' ORDER BY id LIMIT 1;" | psql "${DB}" -Aqt)
    #OLD_DATE=$(echo "SELECT \"timestampMs\" FROM TalerIncomingPayments WHERE payment='$OLD_ID';" | psql "${DB}" -Aqt)
    #echo "UPDATE TalerIncomingPayments SET \"timestampMs\"=$NOW_MS WHERE payment=$OLD_ID;" | psql "${DB}" -q

    run_audit
    check_auditor_running

    #TODO: fix helper wire
    #echo -n "Testing inconsistency detection... "
    #DIAG=$(jq -r .row_minor_inconsistencies[0].diagnostic < test-audit-wire.json)
    #if test "x$DIAG" != "xexecution date mismatch"
    #then
    #    exit_fail "Reported diagnostic wrong: $DIAG"
    #fi
    #TABLE=$(jq -r .row_minor_inconsistencies[0].table < test-audit-wire.json)
    #if test "x$TABLE" != "xreserves_in"
    #then
    #    exit_fail "Reported table wrong: $TABLE"
    #fi
    #echo "PASS"

    # Undo database modification
    #echo "UPDATE TalerIncomingPayments SET \"timestampMs\"='$OLD_DATE' WHERE payment=$OLD_ID;" | psql "${DB}" -q
    stop_auditor_httpd
    full_reload
    cleanup
}


# Test for extra outgoing wire transfer.
# In case of changing the subject in the Nexus
# ingested table: '.batches[0].batchTransactions[0].details.unstructuredRemittanceInformation'
function test_11() {
    echo "===========11: spurious outgoing transfer ==========="
    # Technically, this call shouldn't be needed, as libeufin should already be stopped here.
    stop_libeufin
    echo "FIXME: test needs update to new libeufin-bank schema"
    #TODO: see fixme
    #exit 0
    #OLD_ID=$(echo "SELECT id FROM NexusBankTransactions WHERE amount='10' AND currency='TESTKUDOS' ORDER BY id LIMIT 1;" | psql "${DB}" -Aqt)
    #OLD_TX=$(echo "SELECT \"transactionJson\" FROM NexusBankTransactions WHERE id='$OLD_ID';" | psql "${DB}" -Aqt)
    # Change wire transfer to be FROM the exchange (#2) to elsewhere!
    # (Note: this change also causes a missing incoming wire transfer, but
    #  this test is only concerned about the outgoing wire transfer
    #  being detected as such, and we simply ignore the other
    #  errors being reported.)
    #OTHER_IBAN=$(echo -e "SELECT iban FROM BankAccounts WHERE label='fortytwo'" | psql "${DB}" -Aqt)
    #NEW_TX=$(echo "$OLD_TX" | jq .batches[0].batchTransactions[0].details.creditDebitIndicator='"DBIT"' | jq 'del(.batches[0].batchTransactions[0].details.debtor)' | jq 'del(.batches[0].batchTransactions[0].details.debtorAccount)' | jq 'del(.batches[0].batchTransactions[0].details.debtorAgent)' | jq '.batches[0].batchTransactions[0].details.creditor'='{"name": "Forty Two"}' | jq .batches[0].batchTransactions[0].details.creditorAccount='{"iban": "'"$OTHER_IBAN"'"}' | jq .batches[0].batchTransactions[0].details.creditorAgent='{"bic": "SANDBOXX"}' | jq .batches[0].batchTransactions[0].details.unstructuredRemittanceInformation='"CK9QBFY972KR32FVA1MW958JWACEB6XCMHHKVFMCH1A780Q12SVG http://exchange.example.com/"')
    #echo -e "UPDATE NexusBankTransactions SET \"transactionJson\"='""$NEW_TX""' WHERE id=$OLD_ID" \
    #    | psql "${DB}" -q
    # Now fake that the exchange prepared this payment (= it POSTed to /transfer)
    # This step is necessary, because the TWG table that accounts for outgoing
    # payments needs it.  Worth noting here is the column 'rawConfirmation' that
    # points to the transaction from the main Nexus ledger; without that column set,
    # a prepared payment won't appear as actually outgoing.
    #echo -e "INSERT INTO PaymentInitiations (\"bankAccount\",\"preparationDate\",\"submissionDate\",sum,currency,\"endToEndId\",\"paymentInformationId\",\"instructionId\",subject,\"creditorIban\",\"creditorBic\",\"creditorName\",submitted,\"messageId\",\"rawConfirmation\") VALUES (1,1,1,10,'TESTKUDOS','NOTGIVEN','unused','unused','CK9QBFY972KR32FVA1MW958JWACEB6XCMHHKVFMCH1A780Q12SVG http://exchange.example.com/','""$OTHER_IBAN""','SANDBOXX','Forty Two',false,1,$OLD_ID)" \
    #    | psql "${DB}" -q
    # Now populate the TWG table that accounts for outgoing payments, in
    # order to let /history/outgoing return one result.
    #echo -e "INSERT INTO TalerRequestedPayments (facade,payment,\"requestUid\",amount,\"exchangeBaseUrl\",wtid,\"creditAccount\") VALUES (1,1,'unused','TESTKUDOS:10','http://exchange.example.com/','CK9QBFY972KR32FVA1MW958JWACEB6XCMHHKVFMCH1A780Q12SVG','payto://iban/SANDBOXX/""$OTHER_IBAN""?receiver-name=Forty+Two')" \
    #    | psql "${DB}" -q

    run_audit
    check_auditor_running

    #TODO: fix helper wire
    #echo -n "Testing inconsistency detection... "
    #AMOUNT=$(jq -r .wire_out_amount_inconsistencies[0].amount_wired < test-audit-wire.json)
    #if [ "x$AMOUNT" != "xTESTKUDOS:10" ]
    #then
    #    exit_fail "Reported wired amount wrong: $AMOUNT"
    #fi
    #AMOUNT=$(jq -r .total_wire_out_delta_plus < test-audit-wire.json)
    #if [ "x$AMOUNT" != "xTESTKUDOS:10" ]
    #then
    #    exit_fail "Reported total plus amount wrong: $AMOUNT"
    #fi
    #AMOUNT=$(jq -r .total_wire_out_delta_minus < test-audit-wire.json)
    #if [ "x$AMOUNT" != "xTESTKUDOS:0" ]
    #then
    #    exit_fail "Reported total minus amount wrong: $AMOUNT"
    #fi
    #AMOUNT=$(jq -r .wire_out_amount_inconsistencies[0].amount_justified < test-audit-wire.json)
    #if [ "x$AMOUNT" != "xTESTKUDOS:0" ]
    #then
    #    exit_fail "Reported justified amount wrong: $AMOUNT"
    #fi
    #DIAG=$(jq -r .wire_out_amount_inconsistencies[0].diagnostic < test-audit-wire.json)
    #if [ "x$DIAG" != "xjustification for wire transfer not found" ]
    #then
    #    exit_fail "Reported diagnostic wrong: $DIAG"
    #fi
    #echo "PASS"

    stop_auditor_httpd
    full_reload
}


# Test for hanging/pending refresh.
function test_12() {

    echo "===========12: incomplete refresh ==========="
    OLD_ACC=$(echo "DELETE FROM exchange.refresh_revealed_coins;" | psql "$DB" -Aqt)

    run_audit
    check_auditor_running

    echo -n "Testing hung refresh detection... "

    call_endpoint "refreshes-hanging"
    call_endpoint "balances"
    call_endpoint "balances" "total_refresh_hanging"
    HANG=$(jq -er .refreshes_hanging[0].amount < ${MY_TMP_DIR}/refreshes-hanging.json)
    TOTAL_HANG=$(jq -er .balances[0].balance_value < ${MY_TMP_DIR}/total_refresh_hanging.json)
    if [ "$HANG" = "TESTKUDOS:0" ]
    then
        exit_fail "Hanging amount zero"
    fi
    if [ "$TOTAL_HANG" = "TESTKUDOS:0" ]
    then
        exit_fail "Total hanging amount zero"
    fi
    echo "PASS"

    # cannot easily undo DELETE, hence full reload
    full_reload
    stop_auditor_httpd
}


# Test for wrong signature on refresh.
function test_13() {

    echo "===========13: wrong melt signature ==========="
    # Modify denom_sig, so it is wrong
    COIN_PUB=$(echo "SELECT old_coin_pub FROM exchange.refresh_commitments LIMIT 1;"  | psql "$DB" -Aqt)
    OLD_SIG=$(echo "SELECT old_coin_sig FROM exchange.refresh_commitments WHERE old_coin_pub='$COIN_PUB';" | psql "$DB" -Aqt)
    NEW_SIG="\xba588af7c13c477dca1ac458f65cc484db8fba53b969b873f4353ecbd815e6b4c03f42c0cb63a2b609c2d726e612fd8e0c084906a41f409b6a23a08a83c89a02"
    echo "UPDATE exchange.refresh_commitments SET old_coin_sig='$NEW_SIG' WHERE old_coin_pub='$COIN_PUB'" \
        | psql -Aqt "$DB"

    run_audit
    check_auditor_running

    echo -n "Testing inconsistency detection... "

    call_endpoint "bad-sig-losses"
    call_endpoint "balances" "coin_irregular_loss"

    OP=$(jq -er .bad_sig_losses[0].operation < ${MY_TMP_DIR}/bad-sig-losses.json)
    if [ "$OP" != "melt" ]
    then
        exit_fail "Operation wrong, got $OP"
    fi

    LOSS=$(jq -er .bad_sig_losses[0].loss < ${MY_TMP_DIR}/bad-sig-losses.json)
    TOTAL_LOSS=$(jq -er .balances[0].balance_value < ${MY_TMP_DIR}/coin_irregular_loss.json)
    if [ "$LOSS" != "$TOTAL_LOSS" ]
    then
        exit_fail "Loss inconsistent, got $LOSS and $TOTAL_LOSS"
    fi
    if [ "$TOTAL_LOSS" = "TESTKUDOS:0" ]
    then
        exit_fail "Loss zero"
    fi

    echo "PASS"

    # cannot easily undo DELETE, hence full reload
    full_reload
    stop_auditor_httpd
}


# Test for wire fee disagreement
function test_14() {

    echo "===========14: wire-fee disagreement==========="

    # Wire fees are only checked/generated once there are
    # actual outgoing wire transfers, so we need to run the
    # aggregator here.
    pre_audit aggregator
    echo "UPDATE exchange.wire_fee SET wire_fee.frac=100 WHERE wire_fee_serial=1;" \
        | psql -Aqt "$DB"
    audit_only
    post_audit
    check_auditor_running

    call_endpoint "row-inconsistency"

    echo -n "Testing inconsistency detection... "
    TABLE=$(jq -r .row_inconsistency[0].row_table < ${MY_TMP_DIR}/row-inconsistency.json)
    if [ "$TABLE" != "wire-fee" ]
    then
        exit_fail "Reported table wrong: $TABLE"
    fi
    DIAG=$(jq -r .row_inconsistency[0].diagnostic < ${MY_TMP_DIR}/row-inconsistency.json)
    if [ "$DIAG" != "wire fee signature invalid at given time" ]
    then
        exit_fail "Reported diagnostic wrong: $DIAG"
    fi
    echo "PASS"

    # cannot easily undo aggregator, hence full reload
    full_reload
    stop_auditor_httpd
}


# Test where salt in the deposit table is wrong
function test_15() {
    echo "===========15: deposit wire salt wrong================="

    # Modify wire_salt hash, so it is inconsistent
    ##SALT=$(echo "SELECT wire_salt FROM exchange.deposits WHERE deposit_serial_id=1;" | psql -Aqt "$DB")
    SALT=$(echo "SELECT wire_salt FROM exchange.batch_deposits WHERE batch_deposit_serial_id=1;" | psql -Aqt "$DB")
# shellcheck disable=SC2028
    echo "UPDATE exchange.batch_deposits SET wire_salt='\x1197cd7f7b0e13ab1905fedb36c536a2' WHERE batch_deposit_serial_id=1;" \
        | psql -Aqt "$DB"

    run_audit
    check_auditor_running

    call_endpoint "bad-sig-losses"

    echo -n "Testing inconsistency detection... "
    OP=$(jq -r .bad_sig_losses[0].operation < ${MY_TMP_DIR}/bad-sig-losses.json)
    if [ "$OP" != "deposit" ]
    then
        exit_fail "Reported operation wrong: $OP"
    fi
    echo "PASS"

    # Restore DB
    echo "UPDATE exchange.batch_deposits SET wire_salt='$SALT' WHERE batch_deposit_serial_id=1;" \
        | psql -Aqt "$DB"
    stop_auditor_httpd

}


# Test where wired amount (wire out) is wrong
function test_16() {
    echo "===========16: incorrect wire_out amount================="

    # Check wire transfer lag reported (no aggregator!)

    # First, we need to run the aggregator so we even
    # have a wire_out to modify.
    pre_audit aggregator
    check_auditor_running
#TODO FIX LIBEUFIN
    #stop_libeufin
    #OLD_AMOUNT=$(echo "SELECT amount FROM TalerRequestedPayments WHERE id='1';" | psql "${DB}" -Aqt)
    #NEW_AMOUNT="TESTKUDOS:50"
    #echo "UPDATE TalerRequestedPayments SET amount='${NEW_AMOUNT}' WHERE id='1';" \
    #    | psql "${DB}" -q
    #launch_libeufin
    #audit_only
    #check_auditor_running
#
    #echo -n "Testing inconsistency detection... "
#
    #AMOUNT=$(jq -r .wire_out_amount_inconsistencies[0].amount_justified < test-audit-wire.json)
    #if [ "$AMOUNT" != "$OLD_AMOUNT" ]
    #then
    #    exit_fail "Reported justified amount wrong: $AMOUNT"
    #fi
    #AMOUNT=$(jq -r .wire_out_amount_inconsistencies[0].amount_wired < test-audit-wire.json)
    #if [ "$AMOUNT" != "$NEW_AMOUNT" ]
    #then
    #    exit_fail "Reported wired amount wrong: $AMOUNT"
    #fi
    #TOTAL_AMOUNT=$(jq -r .total_wire_out_delta_minus < test-audit-wire.json)
    #if [ "$TOTAL_AMOUNT" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Reported total wired amount minus wrong: $TOTAL_AMOUNT"
    #fi
    #TOTAL_AMOUNT=$(jq -r .total_wire_out_delta_plus < test-audit-wire.json)
    #if [ "$TOTAL_AMOUNT" = "TESTKUDOS:0" ]
    #then
    #    exit_fail "Reported total wired amount plus wrong: $TOTAL_AMOUNT"
    #fi
    #echo "PASS"
#
    #stop_libeufin
    #echo "Second modification: wire nothing"
    #NEW_AMOUNT="TESTKUDOS:0"
    #echo "UPDATE TalerRequestedPayments SET amount='${NEW_AMOUNT}' WHERE id='1';" \
    #    | psql "${DB}" -q
    #launch_libeufin
    #audit_only
    #stop_libeufin
    #echo -n "Testing inconsistency detection... "
#
    #AMOUNT=$(jq -r .wire_out_amount_inconsistencies[0].amount_justified < test-audit-wire.json)
    #if [ "$AMOUNT" != "$OLD_AMOUNT" ]
    #then
    #    exit_fail "Reported justified amount wrong: $AMOUNT"
    #fi
    #AMOUNT=$(jq -r .wire_out_amount_inconsistencies[0].amount_wired < test-audit-wire.json)
    #if [ "$AMOUNT" != "$NEW_AMOUNT" ]
    #then
    #    exit_fail "Reported wired amount wrong: $AMOUNT"
    #fi
    #TOTAL_AMOUNT=$(jq -r .total_wire_out_delta_minus < test-audit-wire.json)
    #if [ "$TOTAL_AMOUNT" != "$OLD_AMOUNT" ]
    #then
    #    exit_fail "Reported total wired amount minus wrong: $TOTAL_AMOUNT (wanted $OLD_AMOUNT)"
    #fi
    #TOTAL_AMOUNT=$(jq -r .total_wire_out_delta_plus < test-audit-wire.json)
    #if [ "$TOTAL_AMOUNT" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Reported total wired amount plus wrong: $TOTAL_AMOUNT"
    #fi
    #echo "PASS"
#
    #post_audit

    # cannot easily undo aggregator, hence full reload
    full_reload
    stop_auditor_httpd
}


# Test where wire-out timestamp is wrong
function test_17() {
    echo "===========17: incorrect wire_out timestamp================="

    # First, we need to run the aggregator so we even
    # have a wire_out to modify.
#TODO FIX libeufin
#    pre_audit aggregator
#    stop_libeufin
#    OLD_ID=1
#    OLD_PREP=$(echo "SELECT payment FROM TalerRequestedPayments WHERE id='${OLD_ID}';" | psql "${DB}" -Aqt)
#    OLD_DATE=$(echo "SELECT \"preparationDate\" FROM PaymentInitiations WHERE id='${OLD_ID}';" | psql "${DB}" -Aqt)
#    # Note: need - interval '1h' as "NOW()" may otherwise be exactly what is already in the DB
#    # (due to rounding, if this machine is fast...)
#    NOW_1HR=$(( $(date +%s) - 3600))
#    echo "UPDATE PaymentInitiations SET \"preparationDate\"='$NOW_1HR' WHERE id='${OLD_PREP}';" \
#        | psql "${DB}" -q
#    launch_libeufin
#    echo "DONE"
#    audit_only
#    post_audit
#    check_auditor_running
#
#    echo -n "Testing inconsistency detection... "
#    TABLE=$(jq -r .row_minor_inconsistencies[0].table < test-audit-wire.json)
#    if [ "$TABLE" != "wire_out" ]
#    then
#        exit_fail "Reported table wrong: $TABLE"
#    fi
#    DIAG=$(jq -r .row_minor_inconsistencies[0].diagnostic < test-audit-wire.json)
#    DIAG=$(echo "$DIAG" | awk '{print $1 " " $2 " " $3}')
#    if [ "$DIAG" != "execution date mismatch" ]
#    then
#        exit_fail "Reported diagnostic wrong: $DIAG"
#    fi
#    echo "PASS"
#
#    # cannot easily undo aggregator, hence full reload
#    full_reload
}


# Test where we trigger an emergency.
function test_18() {
    echo "===========18: emergency================="

    echo "DELETE FROM exchange.reserves_out;" \
        | psql -Aqt "$DB" -q

    run_audit
    check_auditor_running

    call_endpoint "reserve-balance-summary-wrong-inconsistency"
    call_endpoint "emergency"
    call_endpoint "emergency-by-count"
    call_endpoint "amount-arithmetic-inconsistency"
    call_endpoint "balances" "coins_emergencies_loss_by_count"
    call_endpoint "balances" "coins_emergencies_loss"

    echo -n "Testing emergency detection... "
    jq -e .reserve_balance_summary_wrong_inconsistency[0] \
       < ${MY_TMP_DIR}/reserve-balance-summary-wrong-inconsistency.json \
       > /dev/null \
        || exit_fail "Reserve balance inconsistency not detected"
    jq -e .emergency[0] \
       < ${MY_TMP_DIR}/emergency.json \
       > /dev/null \
        || exit_fail "Emergency not detected"
    jq -e .emergency_by_count[0] \
       < ${MY_TMP_DIR}/emergency-by-count.json \
       > /dev/null \
        || exit_fail "Emergency by count not detected"
    jq -e .amount_arithmetic_inconsistency[0] \
       < ${MY_TMP_DIR}/amount-arithmetic-inconsistency.json \
       > /dev/null \
        || exit_fail "Escrow balance calculation impossibility not detected"
    echo "PASS"

    echo -n "Testing loss calculation... "
    AMOUNT=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/coins_emergencies_loss_by_count.json)
    if [ "$AMOUNT" == "TESTKUDOS:0" ]
    then
        exit_fail "Reported amount wrong: $AMOUNT"
    fi
    AMOUNT=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/coins_emergencies_loss.json)
    if [ "$AMOUNT" == "TESTKUDOS:0" ]
    then
        exit_fail "Reported amount wrong: $AMOUNT"
    fi
    echo "PASS"

    # cannot easily undo broad DELETE operation, hence full reload
    full_reload
    stop_auditor_httpd
}


# Test where reserve closure was done properly
function test_19() {
    echo "===========19: reserve closure done properly ================="

    OLD_TIME=$(echo "SELECT execution_date FROM exchange.reserves_in WHERE reserve_in_serial_id=1;" | psql "$DB" -Aqt)
    OLD_VAL=$(echo "SELECT (credit).val FROM exchange.reserves_in WHERE reserve_in_serial_id=1;" | psql "$DB" -Aqt)
    RES_PUB=$(echo "SELECT reserve_pub FROM exchange.reserves_in WHERE reserve_in_serial_id=1;" | psql "$DB" -Aqt)
    OLD_EXP=$(echo "SELECT expiration_date FROM exchange.reserves WHERE reserve_pub='${RES_PUB}';" | psql "$DB" -Aqt)
    VAL_DELTA=1
    NEW_TIME=$(( OLD_TIME - 3024000000000))  # 5 weeks
    NEW_EXP=$(( OLD_EXP - 3024000000000))  # 5 weeks
    NEW_CREDIT=$(( OLD_VAL + VAL_DELTA))
    echo "UPDATE exchange.reserves_in SET execution_date='${NEW_TIME}',credit.val=${NEW_CREDIT} WHERE reserve_in_serial_id=1;" \
        | psql -Aqt "$DB"
    echo "UPDATE exchange.reserves SET current_balance.val=${VAL_DELTA}+(current_balance).val,expiration_date='${NEW_EXP}' WHERE reserve_pub='${RES_PUB}';" \
        | psql -Aqt "$DB"
#TODO fix helper wire
    # Need to run with the aggregator so the reserve closure happens
        #run_audit aggregator
        check_auditor_running

        call_endpoint "reserve-not-closed-inconsistency"

        echo -n "Testing reserve closure was done correctly... "

        jq -e .reserve_not_closed_inconsistencies[0] < \
        ${MY_TMP_DIR}/reserve-not-closed-inconsistency.json > /dev/null \
        && exit_fail "Unexpected reserve not closed inconsistency detected"

        echo "PASS"

    #TODO fix helepr wire
        #echo -n "Testing no bogus transfers detected... "
        #jq -e .wire_out_amount_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected wire out inconsistency detected in run with reserve closure"

        echo "PASS"

        # cannot easily undo aggregator, hence full reload
        full_reload
        stop_auditor_httpd
}


# Test where reserve closure was not done properly
function test_20() {
    echo "===========20: reserve closure missing ================="

    OLD_TIME=$(echo "SELECT execution_date FROM exchange.reserves_in WHERE reserve_in_serial_id=1;" | psql "$DB" -Aqt)
    OLD_VAL=$(echo "SELECT (credit).val FROM exchange.reserves_in WHERE reserve_in_serial_id=1;" | psql "$DB" -Aqt)
    RES_PUB=$(echo "SELECT reserve_pub FROM exchange.reserves_in WHERE reserve_in_serial_id=1;" | psql "$DB" -Aqt)
    NEW_TIME=$(( OLD_TIME - 3024000000000 ))  # 5 weeks
    NEW_CREDIT=$(( OLD_VAL + 100 ))
    echo "UPDATE exchange.reserves_in SET execution_date='${NEW_TIME}',credit.val=${NEW_CREDIT} WHERE reserve_in_serial_id=1;" \
        | psql -Aqt "$DB"
    echo "UPDATE exchange.reserves SET current_balance.val=100+(current_balance).val WHERE reserve_pub='${RES_PUB}';" \
        | psql -Aqt "$DB"

    # This time, run without the aggregator so the reserve closure is skipped!
    run_audit
    check_auditor_running

    call_endpoint "reserve-not-closed-inconsistency"
    call_endpoint "balances" "total_balance_reserve_not_closed"

    echo -n "Testing reserve closure missing detected... "
    jq -e .reserve_not_closed_inconsistency[0] \
       < ${MY_TMP_DIR}/reserve-not-closed-inconsistency.json\
       > /dev/null  \
        || exit_fail "Reserve not closed inconsistency not detected"
    echo "PASS"

    AMOUNT=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/total_balance_reserve_not_closed.json)
    if [ "$AMOUNT" == "TESTKUDOS:0" ]
    then
        exit_fail "Reported total amount wrong: $AMOUNT"
    fi

    # Undo
    echo "UPDATE exchange.reserves_in SET execution_date='${OLD_TIME}',credit.val=${OLD_VAL} WHERE reserve_in_serial_id=1;" \
        | psql -Aqt "$DB"
    echo "UPDATE exchange.reserves SET current_balance.val=(current_balance).val-100 WHERE reserve_pub='${RES_PUB}';" \
        | psql -Aqt "$DB"

    full_reload
    stop_auditor_httpd
}


# Test reserve closure reported but wire transfer missing detection
function test_21() {
    echo "===========21: reserve closure missreported ================="

    OLD_TIME=$(echo "SELECT execution_date FROM exchange.reserves_in WHERE reserve_in_serial_id=1;" | psql "$DB" -Aqt)
    OLD_VAL=$(echo "SELECT (credit).val FROM exchange.reserves_in WHERE reserve_in_serial_id=1;" | psql "$DB" -Aqt)
    RES_PUB=$(echo "SELECT reserve_pub FROM exchange.reserves_in WHERE reserve_in_serial_id=1;" | psql "$DB" -Aqt)
    OLD_EXP=$(echo "SELECT expiration_date FROM exchange.reserves WHERE reserve_pub='${RES_PUB}';" | psql "$DB" -Aqt)
    VAL_DELTA=1
    NEW_TIME=$(( OLD_TIME - 3024000000000 ))  # 5 weeks
    NEW_EXP=$(( OLD_EXP - 3024000000000 ))  # 5 weeks
    NEW_CREDIT=$(( OLD_VAL + VAL_DELTA ))
    echo "UPDATE exchange.reserves_in SET execution_date='${NEW_TIME}',credit.val=${NEW_CREDIT} WHERE reserve_in_serial_id=1;" \
        | psql -Aqt "$DB"
    echo "UPDATE exchange.reserves SET current_balance.val=${VAL_DELTA}+(current_balance).val,expiration_date='${NEW_EXP}' WHERE reserve_pub='${RES_PUB}';" \
        | psql -Aqt "$DB"
#TODO FIX AUDITOR wire
    # Need to first run the aggregator so the transfer is marked as done exists
#    pre_audit aggregator
#    stop_libeufin
#    # remove transaction from bank DB
#    # Currently emulating this (to be deleted):
#    echo "DELETE FROM TalerRequestedPayments WHERE amount='TESTKUDOS:${VAL_DELTA}'" \
#        | psql "${DB}" -q
#    launch_libeufin
#    audit_only
#    post_audit
#    check_auditor_running
#
#    call_endpoint "reserve-not-closed-inconsistency"
#
#
#    echo -n "Testing lack of reserve closure transaction detected... "
#
#    jq -e .reserve_lag_details[0] \
#       < test-audit-wire.json \
#       > /dev/null \
#        || exit_fail "Reserve closure lag not detected"
#
#    AMOUNT=$(jq -r .reserve_lag_details[0].amount < test-audit-wire.json)
#    if [ "$AMOUNT" != "TESTKUDOS:${VAL_DELTA}" ]
#    then
#        exit_fail "Reported total amount wrong: $AMOUNT"
#    fi
#    AMOUNT=$(jq -r .total_closure_amount_lag < test-audit-wire.json)
#    if [ "$AMOUNT" != "TESTKUDOS:${VAL_DELTA}" ]
#    then
#        exit_fail "Reported total amount wrong: $AMOUNT"
#    fi

    echo "PASS"

    # cannot easily undo aggregator, hence full reload
    full_reload
}


# Test use of withdraw-expired denomination key
function test_22() {
    echo "===========22: denomination key expired ================="

    S_DENOM=$(echo 'SELECT denominations_serial FROM exchange.reserves_out LIMIT 1;' | psql "$DB" -Aqt)

    OLD_START=$(echo "SELECT valid_from FROM exchange.denominations WHERE denominations_serial='${S_DENOM}';" | psql "$DB" -Aqt)
    OLD_WEXP=$(echo "SELECT expire_withdraw FROM exchange.denominations WHERE denominations_serial='${S_DENOM}';" | psql "$DB" -Aqt)
    # Basically expires 'immediately', so that the withdraw must have been 'invalid'
    NEW_WEXP=$OLD_START

    echo "UPDATE exchange.denominations SET expire_withdraw=${NEW_WEXP} WHERE denominations_serial='${S_DENOM}';" | psql -Aqt "$DB"


    run_audit
    check_auditor_running

    call_endpoint "denomination-key-validity-withdraw-inconsistency"

    echo -n "Testing inconsistency detection... "
    jq -e .denomination_key_validity_withdraw_inconsistency[0] < ${MY_TMP_DIR}/denomination-key-validity-withdraw-inconsistency.json \
     > /dev/null || exit_fail "Denomination key withdraw inconsistency for $S_DENOM not detected"

    echo "PASS"

    # Undo modification
    echo "UPDATE exchange.denominations SET expire_withdraw=${OLD_WEXP} WHERE denominations_serial='${S_DENOM}';" | psql -Aqt "$DB"

    full_reload
    stop_auditor_httpd
}


# Test calculation of wire-out amounts
function test_23() {
    echo "===========23: wire out calculations ================="

    # Need to first run the aggregator so the transfer is marked as done exists
    pre_audit aggregator

    OLD_AMOUNT=$(echo "SELECT (amount).frac FROM exchange.wire_out WHERE wireout_uuid=1;" | psql "$DB" -Aqt)
    NEW_AMOUNT=$(( OLD_AMOUNT - 1000000 ))
    echo "UPDATE exchange.wire_out SET amount.frac=${NEW_AMOUNT} WHERE wireout_uuid=1;" \
        | psql -Aqt "$DB"

    audit_only
    post_audit
    check_auditor_running

    echo -n "Testing inconsistency detection... "

    call_endpoint "wire-out-inconsistency"

    jq -e .wire_out_inconsistency[0] \
       < ${MY_TMP_DIR}/wire-out-inconsistency.json \
       > /dev/null \
        || exit_fail "Wire out inconsistency not detected"

    ROW=$(jq .wire_out_inconsistency[0].row_id < ${MY_TMP_DIR}/wire-out-inconsistency.json)
    if [ "$ROW" != 1 ]
    then
        exit_fail "Row wrong"
    fi

    call_endpoint "balances" "aggregation_total_wire_out_delta_plus"
    AMOUNT=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/aggregation_total_wire_out_delta_plus.json)
    if [ "$AMOUNT" != "TESTKUDOS:0" ]
    then
        exit_fail "Reported amount wrong: '$AMOUNT'"
    fi

    call_endpoint "balances" "aggregation_total_wire_out_delta_minus"
    AMOUNT=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/aggregation_total_wire_out_delta_minus.json)
    if [ "$AMOUNT" != "TESTKUDOS:0.01" ]
    then
        exit_fail "Reported total amount wrong: '$AMOUNT'"
    fi
    echo "PASS"

    echo "Second pass: changing how amount is wrong to other direction"
    NEW_AMOUNT=$(( OLD_AMOUNT + 1000000 ))
    echo "UPDATE exchange.wire_out SET amount.frac=${NEW_AMOUNT} WHERE wireout_uuid=1;" | psql -Aqt "$DB"

    pre_audit
    audit_only
    post_audit

    echo -n "Testing inconsistency detection... "

    call_endpoint "wire-out-inconsistency"
    jq -e .wire_out_inconsistency[0] < ${MY_TMP_DIR}/wire-out-inconsistency.json > /dev/null || exit_fail "Wire out inconsistency not detected"

    ROW=$(jq .wire_out_inconsistency[0].rowid < ${MY_TMP_DIR}/test-audit-aggregation.out)
    if [ "$ROW" != 1 ]
    then
        exit_fail "Row wrong"
    fi

    call_endpoint "balances" "aggregation_total_wire_out_delta_minus"
    AMOUNT=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/aggregation_total_wire_out_delta_minus.json)
    if [ "$AMOUNT" != "TESTKUDOS:0" ]
    then
        exit_fail "Reported amount wrong: $AMOUNT"
    fi

    call_endpoint "balances" "aggregation_total_wire_out_delta_plus"
    AMOUNT=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/aggregation_total_wire_out_delta_plus.json)
    if [ "$AMOUNT" != "TESTKUDOS:0.01" ]
    then
        exit_fail "Reported total amount wrong: $AMOUNT"
    fi
    echo "PASS"

    # cannot easily undo aggregator, hence full reload
    full_reload
    stop_auditor_httpd
}


# Test for missing deposits in exchange database.
function test_24() {
#TODO needs to be rebuild probably
    echo "===========24: deposits missing ==========="
    # Modify denom_sig, so it is wrong
    CNT=$(echo "SELECT COUNT(*) FROM auditor.auditor_deposit_confirmations;" | psql -Aqt "$DB")
    if [ "$CNT" = "0" ]
    then
        echo "Skipping deposits missing test: no deposit confirmations in database!"
    else
        echo "DELETE FROM exchange.batch_deposits;" | psql -Aqt "$DB"
        echo "DELETE FROM exchange.batch_deposits WHERE batch_deposit_serial_id=1;" \
            | psql -Aqt "$DB"

        run_audit
        check_auditor_running

        echo -n "Testing inconsistency detection... "

        call_endpoint "deposit-confirmation"
        call_endpoint "balances"

        jq -e .deposit_confirmation_inconsistencies[0] \
           < test-audit-deposits.json \
           > /dev/null \
            || exit_fail "Deposit confirmation inconsistency NOT detected"

        AMOUNT=$(jq -er .missing_deposit_confirmation_total < test-audit-deposits.json)
        if [ "$AMOUNT" = "TESTKUDOS:0" ]
        then
            exit_fail "Expected non-zero total missing deposit confirmation amount"
        fi
        COUNT=$(jq -er .missing_deposit_confirmation_count < test-audit-deposits.json)
        if [ "$AMOUNT" = "0" ]
        then
            exit_fail "Expected non-zero total missing deposit confirmation count"
        fi

        echo "PASS"

        # cannot easily undo DELETE, hence full reload
        full_reload
    fi
}


# Test for inconsistent coin history.
function test_25() {

    echo "=========25: inconsistent coin history========="

    # Drop refund, so coin history is bogus.
    echo "DELETE FROM exchange.refunds WHERE refund_serial_id=1;" \
        | psql -At "$DB"

    run_audit aggregator
    check_auditor_running

    echo -n "Testing inconsistency detection... "

    call_endpoint "coin-inconsistency"
    call_endpoint "emergency"
    call_endpoint "balances" "coins_reported_emergency_risk_by_amount"

#TODO: doesn't find any
    #jq -e .coin_inconsistency[0] \
    #   < ${MY_TMP_DIR}/coin-inconsistency.json \
    #   > /dev/null \
    #    || exit_fail "Coin inconsistency NOT detected"

    # Note: if the wallet withdrew much more than it spent, this might indeed
    # go legitimately unnoticed.
    #jq -e .emergency[0] \
    #   < ${MY_TMP_DIR}/emergency.json \
    #   > /dev/null \
    #    || exit_fail "Denomination value emergency NOT reported"
#TODO: find's only wrong amount
    call_endpoint "balances" "aggregation_total_coin_delta_minus"
    #AMOUNT=$(jq -er .balances[0].balance_value < ${MY_TMP_DIR}/aggregation_total_coin_delta_minus.json)
    #if [ "$AMOUNT" = "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected non-zero total inconsistency amount from coins"
    #fi
    # Note: if the wallet withdrew much more than it spent, this might indeed
    # go legitimately unnoticed.
    #COUNT=$(jq -er .balances[0].balance_value < ${MY_TMP_DIR}/coins_reported_emergency_risk_by_amount.json)
    #if [ "$COUNT" = "TESTKUDOS:0" ]
    #then
       # exit_fail "Expected non-zero emergency-by-amount"
    #fi
    #echo "PASS"

    # cannot easily undo DELETE, hence full reload
    full_reload
    stop_auditor_httpd
}


# Test for deposit wire target malformed
function test_26() {
    echo "===========26: deposit wire target malformed ================="
    #TODO needs to be rebuild
#    # Expects 'payto_uri', not 'url' (also breaks signature, but we cannot even check that).
#    SERIAL=$(echo "SELECT deposit_serial_id FROM exchange.coin_deposits WHERE (amount_with_fee).val=3 AND (amount_with_fee).frac=0 ORDER BY deposit_serial_id LIMIT 1" | psql "$DB" -Aqt)
#    OLD_WIRE_ID=$(echo "SELECT wire_target_h_payto FROM exchange.deposits WHERE deposit_serial_id=${SERIAL};"  | psql "$DB" -Aqt)
## shellcheck disable=SC2028
#    echo "INSERT INTO exchange.wire_targets (payto_uri, wire_target_h_payto) VALUES ('payto://x-taler-bank/localhost/testuser-xxlargtp', '\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660b');" \
#        | psql "$DB" -Aqt
## shellcheck disable=SC2028
#    echo "UPDATE exchange.deposits SET wire_target_h_payto='\x1e8f31936b3cee8f8afd3aac9e38b5db42d45b721ffc4eb1e5b9ddaf1565660b' WHERE deposit_serial_id=${SERIAL}" \
#        | psql -Aqt "$DB"
#
#    run_audit
#    check_auditor_running
#
#    echo -n "Testing inconsistency detection... "
#
#    jq -e .bad_sig_losses[0] < test-audit-coins.json > /dev/null || exit_fail "Bad signature not detected"
#
#    ROW=$(jq -e .bad_sig_losses[0].row < test-audit-coins.json)
#    if [ "$ROW" != "${SERIAL}" ]
#    then
#        exit_fail "Row wrong, got $ROW"
#    fi
#
#    LOSS=$(jq -r .bad_sig_losses[0].loss < test-audit-coins.json)
#    if [ "$LOSS" != "TESTKUDOS:3" ]
#    then
#        exit_fail "Wrong deposit bad signature loss, got $LOSS"
#    fi
#
#    OP=$(jq -r .bad_sig_losses[0].operation < test-audit-coins.json)
#    if [ "$OP" != "deposit" ]
#    then
#        exit_fail "Wrong operation, got $OP"
#    fi
#
#    LOSS=$(jq -r .irregular_loss < test-audit-coins.json)
#    if [ "$LOSS" != "TESTKUDOS:3" ]
#    then
#        exit_fail "Wrong total bad sig loss, got $LOSS"
#    fi
#
#    echo "PASS"
#    # Undo:
#    echo "UPDATE exchange.deposits SET wire_target_h_payto='$OLD_WIRE_ID' WHERE deposit_serial_id=${SERIAL}" \
#        | psql -Aqt "$DB"
}

# Test for duplicate wire transfer subject
function test_27() {
    echo "===========27: duplicate WTID detection ================="
#TODO libeufin fix
 #   pre_audit aggregator
 #   stop_libeufin
 #   # Obtain data to duplicate.
 #   WTID=$(echo SELECT wtid FROM TalerRequestedPayments WHERE id=1 | psql "${DB}" -Aqt)
 #   OTHER_IBAN=$(echo -e "SELECT iban FROM BankAccounts WHERE label='fortytwo'" | psql "${DB}" -Aqt)
 #   # 'rawConfirmation' is set to 2 here, that doesn't
 #   # point to any record.  That's only needed to set a non null value.
 #   echo -e "INSERT INTO PaymentInitiations (\"bankAccount\",\"preparationDate\",\"submissionDate\",sum,currency,\"endToEndId\",\"paymentInformationId\",\"instructionId\",subject,\"creditorIban\",\"creditorBic\",\"creditorName\",submitted,\"messageId\",\"rawConfirmation\") VALUES (1,$(date +%s),$(( $(date +%s) + 2)),10,'TESTKUDOS','NOTGIVEN','unused','unused','$WTID http://exchange.example.com/','$OTHER_IBAN','SANDBOXX','Forty Two',false,1,2)" \
 #       | psql "${DB}" -q
 #   echo -e "INSERT INTO TalerRequestedPayments (facade,payment,\"requestUid\",amount,\"exchangeBaseUrl\",wtid,\"creditAccount\") VALUES (1,2,'unused','TESTKUDOS:1','http://exchange.example.com/','$WTID','payto://iban/SANDBOXX/$OTHER_IBAN?receiver-name=Forty+Two')" \
 #       | psql "${DB}" -q
 #   launch_libeufin
 #   audit_only
 #   post_audit
#
 #   echo -n "Testing inconsistency detection... "
#
 #   AMOUNT=$(jq -r .wire_format_inconsistencies[0].amount < test-audit-wire.json)
 #   if [ "${AMOUNT}" != "TESTKUDOS:1" ]
 #   then
 #       exit_fail "Amount wrong, got ${AMOUNT}"
 #   fi
#
 #   AMOUNT=$(jq -r .total_wire_format_amount < test-audit-wire.json)
 #   if [ "${AMOUNT}" != "TESTKUDOS:1" ]
 #   then
 #       exit_fail "Wrong total wire format amount, got $AMOUNT"
 #   fi
#
 #   # cannot easily undo aggregator, hence full reload
 #   full_reload
}




# Test where denom_sig in known_coins table is wrong
# (=> bad signature) AND the coin is used in aggregation
function test_28() {

    echo "===========28: known_coins signature wrong================="
    # Modify denom_sig, so it is wrong
    OLD_SIG=$(echo 'SELECT denom_sig FROM exchange.known_coins LIMIT 1;' | psql "$DB" -Aqt)
    COIN_PUB=$(echo "SELECT coin_pub FROM exchange.known_coins WHERE denom_sig='$OLD_SIG';"  | psql "$DB" -Aqt)
# shellcheck disable=SC2028
    echo "UPDATE exchange.known_coins SET denom_sig='\x0000000100000000287369672d76616c200a2028727361200a2020287320233542383731423743393036444643303442424430453039353246413642464132463537303139374131313437353746324632323332394644443146324643333445393939413336363430334233413133324444464239413833353833464536354442374335434445304441453035374438363336434541423834463843323843344446304144363030343430413038353435363039373833434431333239393736423642433437313041324632414132414435413833303432434346314139464635394244434346374436323238344143354544364131373739463430353032323241373838423837363535453434423145443831364244353638303232413123290a2020290a20290b' WHERE coin_pub='$COIN_PUB'" \
        | psql -Aqt "$DB"

    run_audit aggregator
    check_auditor_running

    call_endpoint "bad-sig-losses"

    echo -n "Testing inconsistency detection... "
    LOSS=$(jq -r .bad_sig_losses[0].loss < ${MY_TMP_DIR}/bad-sig-losses.json)
    if [ "$LOSS" == "TESTKUDOS:0" ]
    then
        exit_fail "Wrong deposit bad signature loss, got $LOSS"
    fi

    OP=$(jq -r .bad_sig_losses[0].operation < ${MY_TMP_DIR}/bad-sig-losses.json)
    if [ "$OP" != "wire" ]
    then
        exit_fail "Wrong operation, got $OP"
    fi

    call_endpoint "row-inconsistency"
    TAB=$(jq -r .row_inconsistency[0].row_table < ${MY_TMP_DIR}/row-inconsistency.json)
    if [ "$TAB" != "deposit" ]
    then
        exit_fail "Wrong table for row inconsistency, got $TAB"
    fi

    #TODO test seems to be wrong, original auditor logic seems to not spot it
    #LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/total_bad_sig_loss.json)
    #if [ "$LOSS" == "TESTKUDOS:0" ]
    #then
    #    exit_fail "Wrong total bad sig loss, got $LOSS"
    #fi

    echo "OK"
    # cannot easily undo aggregator, hence full reload
    full_reload
    stop_auditor_httpd
}



# Test where fees known to the auditor differ from those
# accounted for by the exchange
function test_29() {
    echo "===========29: withdraw fee inconsistency ================="

    echo "UPDATE exchange.denominations SET fee_withdraw.frac=5000000 WHERE (coin).val=1;" | psql -Aqt "$DB"

    run_audit
    check_auditor_running

    call_endpoint "balances" "total_balance_summary_delta_minus"
    call_endpoint "amount-arithmetic-inconsistency"

    echo -n "Testing inconsistency detection... "
    AMOUNT=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/total_balance_summary_delta_minus.json)
    if [ "$AMOUNT" == "TESTKUDOS:0" ]
    then
        exit_fail "Reported total amount wrong: $AMOUNT"
    fi

    PROFIT=$(jq -r .amount_arithmetic_inconsistency[0].profitable < ${MY_TMP_DIR}/amount-arithmetic-inconsistency.json)
    if [ "$PROFIT" != "true" ]
    then
        exit_fail "Reported wrong profitability: $PROFIT"
    fi
    echo "OK"
    # Undo
    echo "UPDATE exchange.denominations SET fee_withdraw.frac=2000000 WHERE (coin).val=1;" | psql -Aqt "$DB"
    full_reload
    stop_auditor_httpd

}


# Test where fees known to the auditor differ from those
# accounted for by the exchange
function test_30() {
    echo "===========30: melt fee inconsistency ================="

    echo "UPDATE exchange.denominations SET fee_refresh.frac=5000000 WHERE (coin).val=10;" | psql -Aqt "$DB"

    run_audit
    check_auditor_running

    call_endpoint "bad-sig-losses"
    call_endpoint "amount-arithmetic-inconsistency"
    call_endpoint "emergency"

    echo -n "Testing inconsistency detection... "
    AMOUNT=$(jq -r .bad_sig_losses[0].loss < ${MY_TMP_DIR}/bad-sig-losses.json)
    if [ "$AMOUNT" == "TESTKUDOS:0" ]
    then
        exit_fail "Reported total amount wrong: $AMOUNT"
    fi

    PROFIT=$(jq -r .amount_arithmetic_inconsistency[0].profitable < ${MY_TMP_DIR}/amount-arithmetic-inconsistency.json)
    if [ "$PROFIT" != "true" ]
    then
        exit_fail "Reported profitability wrong: $PROFIT"
    fi

    jq -e .emergency[0] < ${MY_TMP_DIR}/emergency.json > /dev/null && exit_fail "Unexpected emergency detected in ordinary run"
    echo "OK"
    # Undo
    echo "UPDATE exchange.denominations SET fee_refresh.frac=3000000 WHERE (coin).val=10;" | psql -Aqt "$DB"

    full_reload
    stop_auditor_httpd

}


# Test where fees known to the auditor differ from those
# accounted for by the exchange
function test_31() {

    echo "===========31: deposit fee inconsistency ================="

    echo "UPDATE exchange.denominations SET fee_deposit.frac=5000000 WHERE (coin).val=8;" | psql -Aqt "$DB"

    run_audit aggregator
    check_auditor_running

    echo -n "Testing inconsistency detection... "

    call_endpoint "balances" "coin_irregular_loss"
    call_endpoint "bad-sig-losses"

    AMOUNT=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/coin_irregular_loss.json)
    if [ "$AMOUNT" == "TESTKUDOS:0" ]
    then
        exit_fail "Reported total amount wrong: $AMOUNT"
    fi

    OP=$(jq -r --arg dep "deposit" '.bad_sig_losses[] | select(.operation == $dep) | .operation'< \
     ${MY_TMP_DIR}/bad-sig-losses.json | head -n1)
    if [ "$OP" != "deposit" ]
    then
        exit_fail "Reported wrong operation: $OP"
    fi

    echo "OK"
    # Undo
    echo "UPDATE exchange.denominations SET fee_deposit.frac=2000000 WHERE (coin).val=8;" | psql -Aqt "$DB"
    stop_auditor_httpd
    full_reload
}




# Test where denom_sig in known_coins table is wrong
# (=> bad signature)
function test_32() {

    echo "===========32: known_coins signature wrong w. aggregation================="
    # Modify denom_sig, so it is wrong
    OLD_SIG=$(echo 'SELECT denom_sig FROM exchange.known_coins LIMIT 1;' | psql "$DB" -Aqt)
    COIN_PUB=$(echo "SELECT coin_pub FROM exchange.known_coins WHERE denom_sig='$OLD_SIG';"  | psql "$DB" -Aqt)
# shellcheck disable=SC2028
    echo "UPDATE exchange.known_coins SET denom_sig='\x0000000100000000287369672d76616c200a2028727361200a2020287320233542383731423743393036444643303442424430453039353246413642464132463537303139374131313437353746324632323332394644443146324643333445393939413336363430334233413133324444464239413833353833464536354442374335434445304441453035374438363336434541423834463843323843344446304144363030343430413038353435363039373833434431333239393736423642433437313041324632414132414435413833303432434346314139464635394244434346374436323238344143354544364131373739463430353032323241373838423837363535453434423145443831364244353638303232413123290a2020290a20290b' WHERE coin_pub='$COIN_PUB'" \
        | psql -Aqt "$DB"

    run_audit aggregator
    check_auditor_running

    echo -n "Testing inconsistency detection... "

    call_endpoint "bad-sig-losses"

    AMOUNT=$(jq -r .total_bad_sig_loss < ${MY_TMP_DIR}/bad-sig-losses.json)
    if [ "$AMOUNT" == "TESTKUDOS:0" ]
    then
        exit_fail "Reported total amount wrong: $AMOUNT"
    fi

    OP=$(jq -r .bad_sig_losses[0].operation < ${MY_TMP_DIR}/bad-sig-losses.json)
    if [ "$OP" != "wire" ]
    then
        exit_fail "Reported wrong operation: $OP"
    fi

    echo "OK"
    # Cannot undo aggregation, do full reload
    stop_auditor_httpd
    full_reload
    cleanup
}



function test_33() {

    echo "===========33: normal run with aggregator and profit drain==========="
    run_audit aggregator drain
    check_auditor_running

    echo "Checking output"
    # if an emergency was detected, that is a bug and we should fail
    echo -n "Test for emergencies... "
    call_endpoint "emergency"
    jq -e .emergency[0] < ${MY_TMP_DIR}/emergency.json > /dev/null && exit_fail "Unexpected emergency detected in ordinary run" || echo PASS
    echo -n "Test for deposit confirmation emergencies... "
    call_endpoint "deposit-confirmation"
    jq -e .deposit_confirmation[0] < ${MY_TMP_DIR}/deposit-confirmation.json > /dev/null && exit_fail "Unexpected deposit confirmation inconsistency detected" || echo PASS
    echo -n "Test for emergencies by count... "
    call_endpoint "emergency-by-count"
    jq -e .emergency_by_count[0] < ${MY_TMP_DIR}/emergency-by-count.json > /dev/null && exit_fail "Unexpected emergency by count detected in ordinary run" || echo PASS

    echo -n "Test for wire inconsistencies... "
    #TODO: fix wire
    #jq -e .wire_out_amount_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected wire out inconsistency detected in ordinary run"
    #jq -e .reserve_in_amount_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected reserve in inconsistency detected in ordinary run"
    #jq -e .misattribution_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected misattribution inconsistency detected in ordinary run"
    #jq -e .row_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected row inconsistency detected in ordinary run"
    #jq -e .denomination_key_validity_withdraw_inconsistencies[0] < test-audit-reserves.json > /dev/null && exit_fail "Unexpected denomination key withdraw inconsistency detected in ordinary run"
    #jq -e .row_minor_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected minor row inconsistency detected in ordinary run"
    #jq -e .lag_details[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected lag detected in ordinary run"
    #jq -e .wire_format_inconsistencies[0] < test-audit-wire.json > /dev/null && exit_fail "Unexpected wire format inconsistencies detected in ordinary run"


    # TODO: check operation balances are correct (once we have all transaction types and wallet is deterministic)
    # TODO: check revenue summaries are correct (once we have all transaction types and wallet is deterministic)

    echo "PASS"

    echo "Testing for aggregation bad sig loss"
    call_endpoint "balances" "aggregation_total_bad_sig_loss"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/aggregation_total_bad_sig_loss.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong total bad sig loss from aggregation, got unexpected loss of $LOSS"
    fi
    call_endpoint "balances" "coin_irregular_loss"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/coin_irregular_loss.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong total bad sig loss from coins, got unexpected loss of $LOSS"
    fi
    call_endpoint "balances" "reserves_total_bad_sig_loss"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/reserves_total_bad_sig_loss.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong total bad sig loss from reserves, got unexpected loss of $LOSS"
    fi

    echo -n "Test for wire amounts... "
    #WIRED=$(jq -r .total_wire_in_delta_plus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total wire delta plus wrong, got $WIRED"
    #fi
    #WIRED=$(jq -r .total_wire_in_delta_minus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total wire delta minus wrong, got $WIRED"
    #fi
    #WIRED=$(jq -r .total_wire_out_delta_plus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total wire delta plus wrong, got $WIRED"
    #fi
    #WIRED=$(jq -r .total_wire_out_delta_minus < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total wire delta minus wrong, got $WIRED"
    #fi
    #WIRED=$(jq -r .total_misattribution_in < test-audit-wire.json)
    #if [ "$WIRED" != "TESTKUDOS:0" ]
    #then
    #    exit_fail "Expected total misattribution in wrong, got $WIRED"
    #fi
    echo "PASS"

    echo -n "Checking for unexpected arithmetic differences "
    call_endpoint "balances" "aggregation_total_arithmetic_delta_plus"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/aggregation_total_arithmetic_delta_plus.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from aggregations, got unexpected plus of $LOSS"
    fi
    call_endpoint "balances" "aggregation_total_arithmetic_delta_minus"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/aggregation_total_arithmetic_delta_minus.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from aggregation, got unexpected minus of $LOSS"
    fi
    call_endpoint "balances" "coins_total_arithmetic_delta_plus"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/coins_total_arithmetic_delta_plus.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from coins, got unexpected plus of $LOSS"
    fi
    call_endpoint "balances" "coins_total_arithmetic_delta_minus"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/coins_total_arithmetic_delta_minus.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from coins, got unexpected minus of $LOSS"
    fi
    call_endpoint "balances" "reserves_total_arithmetic_delta_plus"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/reserves_total_arithmetic_delta_plus.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from reserves, got unexpected plus of $LOSS"
    fi
    call_endpoint "balances" "reserves_total_arithmetic_delta_minus"
    LOSS=$(jq -r .balances[0].balance_value < ${MY_TMP_DIR}/reserves_total_arithmetic_delta_minus.json)
    if [ "$LOSS" != "TESTKUDOS:0" ]
    then
        exit_fail "Wrong arithmetic delta from reserves, got unexpected minus of $LOSS"
    fi

    #DRAINED=$(jq -r .total_drained < test-audit-wire.json)
    #if [ "$DRAINED" != "TESTKUDOS:0.1" ]
    #then
    #    exit_fail "Wrong amount drained, got unexpected drain of $DRAINED"
    #fi

#TODO: fix AAI
    call_endpoint "amount-arithmetic-inconsistency"
#    jq -e .amount_arithmetic_inconsistency[0] \
#       < ${MY_TMP_DIR}/amount-arithmetic-inconsistency.json \
#       > /dev/null \
#        && exit_fail "Unexpected arithmetic inconsistencies from aggregations detected in ordinary run"
#    jq -e .amount_arithmetic_inconsistency[0] \
#       < ${MY_TMP_DIR}/amount-arithmetic-inconsistency.json \
#       > /dev/null \
#        && exit_fail "Unexpected arithmetic inconsistencies from coins detected in ordinary run"
#    jq -e .amount_arithmetic_inconsistency[0] \
#       < ${MY_TMP_DIR}/amount-arithmetic-inconsistency.json \
#       > /dev/null \
#        && exit_fail "Unexpected arithmetic inconsistencies from reserves detected in ordinary run"
    echo "PASS"

    echo -n "Checking for unexpected wire out differences "
    call_endpoint "wire-out-inconsistency"
    jq -e .wire_out_inconsistency[0] \
       < ${MY_TMP_DIR}/wire-out-inconsistency.json \
       > /dev/null \
        && exit_fail "Unexpected wire out inconsistencies detected in ordinary run"
    echo "PASS"

    # cannot easily undo aggregator, hence full reload
    full_reload
    stop_auditor_httpd

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
    taler-config \
        -f \
        -c "${CONF}" \
        -s exchange-offline \
        -o MASTER_PRIV_FILE \
        -V "${MASTER_PRIV_FILE}"

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
echo "Testing for libeufin"
libeufin-bank --help >/dev/null 2> /dev/null </dev/null || exit_skip "libeufin required"
echo "Testing for pdflatex"
which pdflatex > /dev/null </dev/null || exit_skip "pdflatex required"
echo "Testing for taler-wallet-cli"
taler-wallet-cli -h >/dev/null </dev/null 2>/dev/null || exit_skip "taler-wallet-cli required"


echo -n "Testing for Postgres"
# Available directly in path?
INITDB_BIN=$(command -v initdb) || true
if [[ -n "$INITDB_BIN" ]]; then
  echo " FOUND (in path) at $INITDB_BIN"
else
    HAVE_INITDB=$(find /usr -name "initdb" 2> /dev/null \
                      | head -1 2> /dev/null \
                      | grep postgres) \
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

# Once we move to PG16, we can use:
#    --set listen_addresses='' \
#    --set fsync=off \
#    --set max_wal_senders=0 \
#    --set synchronous_commit=off \
#    --set wal_level=minimal \
#    --set unix_socket_directories="${TMPDIR}/sockets" \


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
    -l "${MY_TMP_DIR}/postgres.log" \
    start \
    > "${MY_TMP_DIR}/postgres-start.log" \
    2> "${MY_TMP_DIR}/postgres-start.err"
echo " DONE"
PGHOST="$TMPDIR/sockets"
export PGHOST
MYDIR="${MY_TMP_DIR}/basedb"
mkdir -p "${MYDIR}"

if [ -z ${REUSE_BASEDB_DIR+x} ]
then
    echo "Generating fresh database at $MYDIR"

    if faketime -f '-1 d' ./generate-auditor-basedb.sh -d "$MYDIR/$DB"
    then
        echo -n "Reset 'auditor-basedb' database at $PGHOST ..."
        dropdb --if-exists "auditor-basedb" > /dev/null 2> /dev/null || true
        createdb "auditor-basedb" || exit_skip "Could not create database '$BASEDB' at $PGHOST"
        echo " DONE"
    else
        echo "Generation failed"
        exit 1
    fi
    echo "To re-use this database in the future, use:"
    echo "export REUSE_BASEDB_DIR=$MY_TMP_DIR"
else
    echo "Reusing existing database from ${REUSE_BASEDB_DIR}"
    cp -r "${REUSE_BASEDB_DIR}/basedb"/* "${MYDIR}/"
fi

check_with_database "$MYDIR/$DB"
if [ "$fail" != "0" ]
then
    exit "$fail"
fi

if [ -z "${REUSE_BASEDB_DIR}" ]
then
    echo "Run 'export REUSE_BASEDB_DIR=${MY_TMP_DIR}' to re-run tests against the same database"
fi

exit 0
