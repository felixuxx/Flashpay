#!/bin/sh

set -eu

echo -n "Testing synchronization logic ..."

dropdb talercheck-in 2> /dev/null || true
dropdb talercheck-out 2> /dev/null || true

createdb talercheck-in || exit 77
createdb talercheck-out || exit 77
echo -n "."

taler-exchange-dbinit -c test-sync-out.conf
echo -n "."
psql talercheck-in < auditor-basedb.sql >/dev/null 2> /dev/null

echo -n "."
taler-auditor-sync -s test-sync-in.conf -d test-sync-out.conf -t

for table in denominations denomination_revocations reserves reserves_in reserves_close reserves_out auditors auditor_denom_sigs exchange_sign_keys signkey_revocations known_coins refresh_commitments refresh_revealed_coins refresh_transfer_keys deposits refunds wire_out aggregation_tracking wire_fee recoup recoup_refresh
do
    echo -n "."
    CIN=`echo "SELECT COUNT(*) FROM $table" | psql talercheck-in -Aqt`
    COUT=`echo "SELECT COUNT(*) FROM $table" | psql talercheck-out -Aqt`

    if test ${CIN} != ${COUT}
    then
        dropdb talercheck-in
        dropdb talercheck-out
        echo "FAIL"
        echo "Record count missmatch: $CIN / $COUT in table $table"
        exit 1
    fi
done

echo -n ". "
dropdb talercheck-in
dropdb talercheck-out

echo "PASS"
exit 0
