#!/bin/sh

set -eu

# Exit, with status code "skip" (no 'real' failure)
exit_skip() {
    echo $1
    exit 77
}

# Exit, with error message (hard failure)
exit_fail() {
    echo $1
    exit 1
}

check_with_database()
{
    echo -n "Testing synchronization logic ..."

    dropdb talercheck-in 2> /dev/null || true
    dropdb talercheck-out 2> /dev/null || true

    createdb talercheck-in || exit 77
    createdb talercheck-out || exit 77
    echo -n "."

    taler-exchange-dbinit -c test-sync-out.conf
    echo -n "."
    psql -Aqt talercheck-in -q -1 -f $1.sql >/dev/null || exit_skip "Failed to load database"

    echo -n "."
    taler-auditor-sync -s test-sync-in.conf -d test-sync-out.conf -t

    # cs_nonce_locks excluded: no point
    for table in denominations denomination_revocations wire_targets reserves reserves_in reserves_close reserves_out auditors auditor_denom_sigs exchange_sign_keys signkey_revocations extensions extension_details known_coins refresh_commitments refresh_revealed_coins refresh_transfer_keys deposits refunds wire_out aggregation_tracking wire_fee recoup recoup_refresh
    do
        echo -n "."
        CIN=`echo "SELECT COUNT(*) FROM exchange.$table" | psql talercheck-in -Aqt`
        COUT=`echo "SELECT COUNT(*) FROM exchange.$table" | psql talercheck-out -Aqt`

        if test ${CIN} != ${COUT}
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
}



# Postgres database to use
DB=auditor-basedb

# Configuration file to use
CONF=${DB}.conf

# test required commands exist
echo "Testing for jq"
jq -h > /dev/null || exit_skip "jq required"
echo "Testing for faketime"
faketime -h > /dev/null || exit_skip "faketime required"
# NOTE: really check for all three libeufin commands?
echo "Testing for libeufin"
libeufin-cli --help >/dev/null </dev/null || exit_skip "libeufin required"
echo "Testing for pdflatex"
which pdflatex > /dev/null </dev/null || exit_skip "pdflatex required"

# check if we should regenerate the database
echo "Testing for taler-wallet-cli"
taler-wallet-cli -h >/dev/null </dev/null 2>/dev/null || exit_skip "taler-wallet-cli required"
MYDIR=`mktemp -d /tmp/taler-auditor-basedbXXXXXX`
echo "Generating fresh database at $MYDIR"
if faketime -f '-1 d' ./generate-auditor-basedb.sh $MYDIR/basedb
then
    check_with_database $MYDIR/basedb
    if test x$fail != x0
    then
        exit $fail
    else
        echo "Cleaning up $MYDIR..."
        rm -rf $MYDIR || echo "Removing $MYDIR failed"
    fi
else
    echo "Generation failed"
    exit 77
fi
exit 0
