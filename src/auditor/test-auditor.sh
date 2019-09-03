#!/bin/bash
# Setup database which was generated from a perfectly normal
# exchange-wallet interaction and run the auditor against it.
#
# Check that the auditor report is as expected.
#
# Requires 'jq' tool and Postgres superuser rights!
set -eu

# Set of numbers for all the testcases.
# When adding new tests, increase the last number:
ALL_TESTS=`seq 0 4`

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

# Exit, with status code "skip" (no 'real' failure)
function exit_skip() {
    echo $1
    exit 77
}

# Exit, with error message (hard failure)
function exit_fail() {
    echo $1
    kill `jobs -p`
    exit 1
}

# Run audit process on current database, including report
# generation.  Pass "aggregator" as $1 to run
# $ taler-exchange-aggregator
# before auditor (to trigger pending wire transfers).
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

    if test ${1:-no} = "aggregator"
    then
        echo "Running exchange aggregator"
        taler-exchange-aggregator -t -c test-auditor.conf
    fi

    # Run the auditor!
    echo "Running audit(s)"
    taler-auditor -r -c test-auditor.conf -m $MASTER_PUB > test-audit.json 2> test-audit.log || exit_fail "auditor failed"

    taler-wire-auditor -r -c test-auditor.conf -m $MASTER_PUB > test-wire-audit.json 2> test-wire-audit.log || exit_fail "wire auditor failed"

    echo "Shutting down services"
    kill `jobs -p` || true

    echo "TeXing"
    ../../contrib/render.py test-audit.json test-wire-audit.json < ../../contrib/auditor-report.tex.j2 > test-report.tex || exit_fail "Renderer failed"

    timeout 10 pdflatex test-report.tex >/dev/null || exit_fail "pdflatex failed"
    timeout 10 pdflatex test-report.tex >/dev/null
}


# Do a full reload of the (original) database
full_reload()
{
    dropdb $DB 2> /dev/null || true
    createdb -T template0 $DB || exit_skip "could not create database"
    # Import pre-generated database, -q(ietly) using single (-1) transaction
    psql -Aqt $DB -q -1 -f ../benchmark/auditor-basedb.sql > /dev/null
}


test_0() {

echo "===========0: normal run with aggregator==========="
run_audit aggregator

echo "Checking output"
# if an emergency was detected, that is a bug and we should fail
echo -n "Test for emergencies... "
jq -e .emergencies[0] < test-audit.json > /dev/null && exit_fail "Unexpected emergency detected in ordinary run" || echo OK

jq -e .emergencies_by_count[0] < test-audit.json > /dev/null && exit_fail "Unexpected emergency by count detected in ordinary run" || echo OK

echo -n "Test for wire inconsistencies... "
jq -e .wire_out_amount_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected wire out inconsistency detected in ordinary run"
jq -e .reserve_in_amount_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected reserve in inconsistency detected in ordinary run"
jq -e .missattribution_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected missattribution inconsistency detected in ordinary run"
jq -e .row_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected row inconsistency detected in ordinary run"
jq -e .row_minor_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected minor row inconsistency detected in ordinary run"
jq -e .lag_details[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected lag detected in ordinary run"
jq -e .wire_format_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected wire format inconsistencies detected in ordinary run"

# FIXME: check operation balances are correct (once we have more transaction types)
# FIXME: check revenue summaries are correct (once we have more transaction types)

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

# FIXME: check NO lag reported

# cannot easily undo aggregator, hence full reload
full_reload
echo "OK"
}


# Run without aggregator, hence auditor should detect wire
# transfer lag!
test_1() {

echo "===========1: normal run==========="
run_audit

echo "Checking output"
# if an emergency was detected, that is a bug and we should fail
echo -n "Test for emergencies... "
jq -e .emergencies[0] < test-audit.json > /dev/null && exit_fail "Unexpected emergency detected in ordinary run" || echo OK

jq -e .emergencies_by_count[0] < test-audit.json > /dev/null && exit_fail "Unexpected emergency by count detected in ordinary run" || echo OK

echo -n "Test for wire inconsistencies... "
jq -e .wire_out_amount_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected wire out inconsistency detected in ordinary run"
jq -e .reserve_in_amount_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected reserve in inconsistency detected in ordinary run"
jq -e .missattribution_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected missattribution inconsistency detected in ordinary run"
jq -e .row_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected row inconsistency detected in ordinary run"
jq -e .row_minor_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected minor row inconsistency detected in ordinary run"
jq -e .lag_details[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected lag detected in ordinary run"
jq -e .wire_format_inconsistencies[0] < test-wire-audit.json > /dev/null && exit_fail "Unexpected wire format inconsistencies detected in ordinary run"

# FIXME: check operation balances are correct (once we have more transaction types)
# FIXME: check revenue summaries are correct (once we have more transaction types)

echo OK

# FIXME: check wire transfer lag reported (no aggregator!)

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
# Database was unmodified, no need to undo
echo "OK"
}


# Change amount of wire transfer reported by exchange
test_2() {

echo "===========2: reserves_in inconsitency==========="
echo "UPDATE reserves_in SET credit_val=5 WHERE reserve_in_serial_id=1" | psql -Aqt $DB

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

WIRED=`jq -r .total_wire_in_delta_minus < test-wire-audit.json`
if test $WIRED != "TESTKUDOS:0"
then
    exit_fail "Wrong total wire_in_delta_minus, got $WIRED"
fi
DELTA=`jq -r .total_wire_in_delta_plus < test-wire-audit.json`
if test $DELTA != "TESTKUDOS:5"
then
    exit_fail "Expected total wire delta plus wrong"
fi
echo OK

# Undo database modification
echo "UPDATE reserves_in SET credit_val=10 WHERE reserve_in_serial_id=1" | psql -Aqt $DB

}


# Check for incoming wire transfer amount given being
# lower than what exchange claims to have received.
test_3() {

echo "===========3: reserves_in inconsitency==========="
echo "UPDATE reserves_in SET credit_val=15 WHERE reserve_in_serial_id=1" | psql -Aqt $DB

run_audit

EXPECTED=`jq -r .reserve_balance_summary_wrong_inconsistencies[0].auditor < test-audit.json`
if test $EXPECTED != "TESTKUDOS:5.01"
then
    exit_fail "Expected reserve balance summary amount wrong, got $EXPECTED (auditor)"
fi

EXPECTED=`jq -r .reserve_balance_summary_wrong_inconsistencies[0].exchange < test-audit.json`
if test $EXPECTED != "TESTKUDOS:0.01"
then
    exit_fail "Expected reserve balance summary amount wrong, got $EXPECTED (exchange)"
fi

WIRED=`jq -r .total_loss_balance_insufficient < test-audit.json`
if test $WIRED != "TESTKUDOS:0"
then
    exit_fail "Wrong total loss from insufficient balance, got $WIRED"
fi

ROW=`jq -e .reserve_in_amount_inconsistencies[0].row < test-wire-audit.json`
if test $ROW != 1
then
    exit_fail "Row wrong, got $ROW"
fi

WIRED=`jq -r .reserve_in_amount_inconsistencies[0].amount_exchange_expected < test-wire-audit.json`
if test $WIRED != "TESTKUDOS:15"
then
    exit_fail "Wrong amount_exchange_expected, got $WIRED"
fi

WIRED=`jq -r .reserve_in_amount_inconsistencies[0].amount_wired < test-wire-audit.json`
if test $WIRED != "TESTKUDOS:10"
then
    exit_fail "Wrong amount_wired, got $WIRED"
fi

WIRED=`jq -r .total_wire_in_delta_minus < test-wire-audit.json`
if test $WIRED != "TESTKUDOS:5"
then
    exit_fail "Wrong total wire_in_delta_minus, got $WIRED"
fi

WIRED=`jq -r .total_wire_in_delta_plus < test-wire-audit.json`
if test $WIRED != "TESTKUDOS:0"
then
    exit_fail "Wrong total wire_in_delta_plus, got $WIRED"
fi

# Undo database modification
echo "UPDATE reserves_in SET credit_val=10 WHERE reserve_in_serial_id=1" | psql -Aqt $DB

}


# Check for incoming wire transfer amount given being
# lower than what exchange claims to have received.
test_4() {

echo "===========4: deposit wire target wrong================="
# Original target bank account was 43, changing to 44
echo "UPDATE deposits SET wire='{\"url\":\"payto://x-taler-bank/localhost:8082/44\",\"salt\":\"test-salt (must be constant for aggregation tests)\"}' WHERE deposit_serial_id=1" | psql -Aqt $DB

run_audit

ROW=`jq -e .bad_sig_losses[0].row < test-audit.json`
if test $ROW != 1
then
    exit_fail "Row wrong, got $ROW"
fi

LOSS=`jq -r .bad_sig_losses[0].loss < test-audit.json`
if test $LOSS != "TESTKUDOS:0.1"
then
    exit_fail "Wrong deposit bad signature loss, got $LOSS"
fi

OP=`jq -r .bad_sig_losses[0].operation < test-audit.json`
if test $OP != "deposit"
then
    exit_fail "Wrong operation, got $OP"
fi

LOSS=`jq -r .total_bad_sig_loss < test-audit.json`
if test $LOSS != "TESTKUDOS:0.1"
then
    exit_fail "Wrong total bad sig loss, got $LOSS"
fi

# Undo:
echo "UPDATE deposits SET wire='{\"url\":\"payto://x-taler-bank/localhost:8082/43\",\"salt\":\"test-salt (must be constant for aggregation tests)\"}' WHERE deposit_serial_id=1" | psql -Aqt $DB

}



# Test where h_contract_terms in the deposit table is wrong
# (=> bad signature)
test_5() {
echo "===========5: deposit contract hash wrong================="
# Modify h_wire hash, so it is inconsistent with 'wire'
OLD_H=`echo 'SELECT h_contract_terms FROM deposits WHERE deposit_serial_id=1;'  | psql taler-auditor-test -Aqt`
echo "UPDATE deposits SET h_contract_terms='\x12bb676444955c98789f219148aa31899d8c354a63330624d3d143222cf3bb8b8e16f69accd5a8773127059b804c1955696bf551dd7be62719870613332aa8d5' WHERE deposit_serial_id=1" | psql -Aqt $DB

run_audit

ROW=`jq -e .bad_sig_losses[0].row < test-audit.json`
if test $ROW != 1
then
    exit_fail "Row wrong, got $ROW"
fi

LOSS=`jq -r .bad_sig_losses[0].loss < test-audit.json`
if test $LOSS != "TESTKUDOS:0.1"
then
    exit_fail "Wrong deposit bad signature loss, got $LOSS"
fi

OP=`jq -r .bad_sig_losses[0].operation < test-audit.json`
if test $OP != "deposit"
then
    exit_fail "Wrong operation, got $OP"
fi

LOSS=`jq -r .total_bad_sig_loss < test-audit.json`
if test $LOSS != "TESTKUDOS:0.1"
then
    exit_fail "Wrong total bad sig loss, got $LOSS"
fi

# Undo:
echo "UPDATE deposits SET h_contract_terms='${OLD_H}' WHERE deposit_serial_id=1" | psql -Aqt $DB

}




# Test where h_wire in the deposit table is wrong
test_99() {
echo "===========99: deposit wire hash wrong================="
# Modify h_wire hash, so it is inconsistent with 'wire'
echo "UPDATE deposits SET h_wire='\x973e52d193a357940be9ef2939c19b0575ee1101f52188c3c01d9005b7d755c397e92624f09cfa709104b3b65605fe5130c90d7e1b7ee30f8fc570f39c16b853' WHERE deposit_serial_id=1" | psql -Aqt $DB

# The auditor checks h_wire consistency only for
# coins where the wire transfer has happened, hence
# run aggregator first to get this test to work.
#
# FIXME: current test database has transfers still
# in the *distant* future, test cannot yet work.
# patch up once DB was re-generated!
run_audit aggregator

# FIXME: check for the respective inconsistency in the report!

# Undo:
# echo "UPDATE deposits SET h_wire='\x973e52d193a357940be9ef2939c19b0575ee1101f52188c3c01d9005b7d755c397e92624f09cfa709104b3b65605fe5130c90d7e1b7ee30f8fc570f39c16b852' WHERE deposit_serial_id=1" | psql -Aqt $DB

}




# **************************************************
# Add more tests here! :-)
# **************************************************


# *************** Main logic starts here **************

# Setup globals
DB=taler-auditor-test
MASTER_PUB=`cat ../benchmark/auditor-basedb.mpub`

# test required commands exist
echo "Testing for jq"
jq -h > /dev/null || exit_skip "jq required"
echo "Testing for taler-bank-manage"
taler-bank-manage -h >/dev/null </dev/null || exit_skip "taler-bank-manage required"
echo "Testing for pdflatex"
which pdflatex > /dev/null </dev/null || exit_skip "pdflatex required"

echo "Database setup"
full_reload

# Run test suite
fail=0
for i in $TESTS
do
    test_$i
    if test 0 != $fail
    then
       break
    fi
done


echo "Cleanup"
# dropdb $DB
# rm -f test-audit.log test-wire-audit.log

exit $fail
