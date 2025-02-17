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
# shellcheck disable=SC2317

set -eu

# Exit, with status code "skip" (no 'real' failure)
function exit_skip() {
    echo "SKIPPING test: $1"
    exit 77
}

# Exit, with error message (hard failure)
function exit_fail() {
    echo "FAILING test: $1"
    exit 1
}

# Cleanup to run whenever we exit
function cleanup() {
    if [ -n "${POSTGRES_PATH:-}" ]
    then
        "${POSTGRES_PATH}/pg_ctl" -D "$TMPDIR" stop &> /dev/null || true
    fi
    for n in $(jobs -p)
    do
        kill "$n" 2> /dev/null || true
    done
    wait
}

# Install cleanup handler (except for kill -9)
trap cleanup EXIT

# If this script is not run as root,
# create the temporary storage space for postgres.
# Will set PGHOST accordingly
function perform_initdb() {
    # Available directly in path?
    INITDB_BIN=$(command -v initdb) || true
    if [[ -n "$INITDB_BIN" ]]; then
      echo " FOUND (in path) at $INITDB_BIN"
    else
      HAVE_INITDB=$(find /usr -name "initdb" | head -1 2> /dev/null | grep postgres) || exit_skip " MISSING"
      echo " FOUND at " "$(dirname "$HAVE_INITDB")"
      INITDB_BIN=$(echo "$HAVE_INITDB" | grep bin/initdb | grep postgres | sort -n | tail -n1)
    fi
    echo -n "Setting up Postgres DB"
    POSTGRES_PATH=$(dirname "$INITDB_BIN")
    TMPDIR="$MYDIR/postgres/"
    mkdir -p "$TMPDIR"
    "$INITDB_BIN" --no-sync --auth=trust -D "${TMPDIR}" \
                > "${MYDIR}/postgres-dbinit.log" \
                2> "${MYDIR}/postgres-dbinit.err"
    echo " DONE"
    mkdir "${TMPDIR}/sockets"
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
        > "${MYDIR}/postgres-start.log" \
        2> "${MYDIR}/postgres-start.err"
    echo " DONE"
    PGHOST="$TMPDIR/sockets"
    export PGHOST
}

function check_with_database()
{
    echo -n "Testing synchronization logic ..."

    dropdb talercheck-in 2> /dev/null || true
    dropdb talercheck-out 2> /dev/null || true

    createdb talercheck-in || exit 77
    createdb talercheck-out || exit 77
    echo -n "."

    taler-exchange-dbinit -c test-sync-out.conf
    echo -n "."
    psql -Aqt talercheck-in \
         -q -1 \
         -f "$1.sql" \
         >/dev/null \
        || exit_skip "Failed to load database"

    echo -n "."
    taler-auditor-sync \
        -s test-sync-in.conf \
        -d test-sync-out.conf -t

    # cs_nonce_locks excluded: no point
    for table in denominations denomination_revocations wire_targets reserves reserves_in reserves_close reserves_open_requests reserves_open_deposits reserves_out auditors auditor_denom_sigs exchange_sign_keys signkey_revocations known_coins refresh_commitments refresh_revealed_coins refresh_transfer_keys batch_deposits coin_deposits refunds wire_out aggregation_tracking wire_fee recoup recoup_refresh extensions policy_details policy_fulfillments purse_requests purse_decision purse_merges purse_deposits account_merges history_requests close_requests wads_out wad_out_entries wads_in wad_in_entries profit_Drains aml_staff purse_deletion age_withdraw legitimization_measures legitimization_outcomes legitimization_processes kyc_attributes aml_history kyc_events kycauths_in
    do
        echo -n "."
        CIN=$(echo "SELECT COUNT(*) FROM exchange.$table" | psql talercheck-in -Aqt)
        COUT=$(echo "SELECT COUNT(*) FROM exchange.$table" | psql talercheck-out -Aqt)

        if [ "${CIN}" != "${COUT}" ]
        then
            dropdb talercheck-in
            dropdb talercheck-out
            echo "FAIL"
            exit_fail "Record count mismatch: $CIN / $COUT in table $table"
        fi
    done

    echo -n ". "
    dropdb talercheck-in
    dropdb talercheck-out

    echo "PASS"
    fail=0
}

# test required commands exist
echo "Testing for jq"
jq -h > /dev/null || exit_skip "jq required"
echo "Testing for faketime"
faketime -h > /dev/null || exit_skip "faketime required"
echo "Testing for libeufin-bank"
libeufin-bank --help >/dev/null </dev/null 2> /dev/null || exit_skip "libeufin-bank required"
echo "Testing for taler-wallet-cli"
taler-wallet-cli -h >/dev/null </dev/null 2>/dev/null || exit_skip "taler-wallet-cli required"

MYDIR=$(mktemp -d /tmp/taler-auditor-basedbXXXXXX)

echo -n "Testing for Postgres"
[ $(id -u == 0) ] || perform_initdb

echo "Generating fresh database at $MYDIR"
if faketime -f '-1 d' ./generate-auditor-basedb.sh -d "$MYDIR/auditor-basedb"
then
    check_with_database "$MYDIR/auditor-basedb"
    if [ x$fail != x0 ]
    then
        exit "$fail"
    else
        echo "Cleaning up $MYDIR..."
        rm -rf "$MYDIR" || echo "Removing $MYDIR failed"
    fi
else
    echo "Generation failed"
    exit 77
fi
exit 0
