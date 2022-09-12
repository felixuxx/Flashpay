#!/bin/bash
# Script to generate the basic database for auditor
# testing from a 'correct' interaction between exchange,
# wallet and merchant.
#
# Creates $BASEDB.sql, $BASEDB.fees, $BASEDB.mpub and
# $BASEDB.age.
# Default $BASEDB is "auditor-basedb", override via $1.
#
# Currently must be run online as it interacts with
# bank.test.taler.net; also requires the wallet CLI
# to be installed and in the path.  Furthermore, the
# user running this script must be Postgres superuser
# and be allowed to create/drop databases.
#
set -eu

function get_iban() {
    export LIBEUFIN_SANDBOX_USERNAME=$1
    export LIBEUFIN_SANDBOX_PASSWORD=$2
    export LIBEUFIN_SANDBOX_URL=$BANK_URL
    libeufin-cli sandbox demobank info --bank-account $1 | jq --raw-output '.iban'
}

function get_payto_uri() {
    export LIBEUFIN_SANDBOX_USERNAME=$1
    export LIBEUFIN_SANDBOX_PASSWORD=$2
    export LIBEUFIN_SANDBOX_URL=$BANK_URL
    libeufin-cli sandbox demobank info --bank-account $1 | jq --raw-output '.paytoUri'
}

# Cleanup to run whenever we exit
function cleanup()
{
    for n in `jobs -p`
    do
        kill $n 2> /dev/null || true
    done
    echo Killing euFin..
    kill `cat libeufin-sandbox.pid 2> /dev/null` &> /dev/null || true
    kill `cat libeufin-nexus.pid 2> /dev/null` &> /dev/null || true
    wait
}

# Install cleanup handler (except for kill -9)
trap cleanup EXIT


# Exit, with status code "skip" (no 'real' failure)
function exit_skip() {
    echo $1
    exit 77
}
# Where do we write the result?
BASEDB=${1:-"auditor-basedb"}
# Name of the Postgres database we will use for the script.
# Will be dropped, do NOT use anything that might be used
# elsewhere
export TARGET_DB=`basename ${BASEDB}`

export WALLET_DB=${BASEDB:-"wallet"}.wdb

# delete existing wallet database
rm -f $WALLET_DB
# delete libeufin database
rm -f $TARGET_DB


# Configuration file will be edited, so we create one
# from the template.
CONF_ONCE=${BASEDB}.conf
cp generate-auditor-basedb.conf $CONF_ONCE
taler-config -c ${CONF_ONCE} -s exchange-offline -o MASTER_PRIV_FILE -V ${BASEDB}.mpriv


echo -n "Testing for libeufin"
libeufin-cli --help >/dev/null </dev/null || exit_skip " MISSING"
echo " FOUND"
echo -n "Testing for taler-wallet-cli"
taler-wallet-cli -v >/dev/null </dev/null || exit_skip " MISSING"
echo " FOUND"
echo -n "Testing for curl"
curl --help >/dev/null </dev/null || exit_skip " MISSING"
echo " FOUND"

# Clean up

DATA_DIR=`taler-config -f -c $CONF_ONCE -s PATHS -o TALER_HOME`
rm -rf $DATA_DIR || true

# reset database
dropdb $TARGET_DB >/dev/null 2>/dev/null || true
createdb $TARGET_DB || exit_skip "Could not create database $TARGET_DB"


# obtain key configuration data
MASTER_PRIV_FILE=${TARGET_DB}.mpriv
taler-config -f -c ${CONF_ONCE} -s exchange-offline -o MASTER_PRIV_FILE -V ${MASTER_PRIV_FILE}
MASTER_PRIV_DIR=`dirname $MASTER_PRIV_FILE`
rm -f "${MASTER_PRIV_FILE}"
mkdir -p $MASTER_PRIV_DIR
gnunet-ecc -g1 $MASTER_PRIV_FILE > /dev/null
MASTER_PUB=`gnunet-ecc -p $MASTER_PRIV_FILE`
MERCHANT_PORT=`taler-config -c $CONF_ONCE -s MERCHANT -o PORT`
MERCHANT_URL=http://localhost:${MERCHANT_PORT}/
AUDITOR_URL=http://localhost:8083/
AUDITOR_PRIV_FILE=`taler-config -f -c $CONF_ONCE -s AUDITOR -o AUDITOR_PRIV_FILE`
AUDITOR_PRIV_DIR=`dirname $AUDITOR_PRIV_FILE`
mkdir -p $AUDITOR_PRIV_DIR
gnunet-ecc -g1 $AUDITOR_PRIV_FILE > /dev/null
AUDITOR_PUB=`gnunet-ecc -p $AUDITOR_PRIV_FILE`
EXCHANGE_URL=`taler-config -c $CONF_ONCE -s EXCHANGE -o BASE_URL`
BANK_PORT=`taler-config -c $CONF_ONCE -s BANK -o HTTP_PORT`
BANK_URL="http://localhost:1${BANK_PORT}/demobanks/default"

echo "MASTER PUB is ${MASTER_PUB} using file ${MASTER_PRIV_FILE}"
echo "AUDITOR PUB is ${AUDITOR_PUB} using file ${AUDITOR_PRIV_FILE}"

# patch configuration
taler-config -c $CONF_ONCE -s exchange -o MASTER_PUBLIC_KEY -V $MASTER_PUB
taler-config -c $CONF_ONCE -s auditor -o PUBLIC_KEY -V $AUDITOR_PUB
taler-config -c $CONF_ONCE -s merchant-exchange-default -o MASTER_KEY -V $MASTER_PUB
taler-config -c $CONF_ONCE -s exchangedb-postgres -o CONFIG -V postgres:///$TARGET_DB
taler-config -c $CONF_ONCE -s auditordb-postgres -o CONFIG -V postgres:///$TARGET_DB
taler-config -c $CONF_ONCE -s merchantdb-postgres -o CONFIG -V postgres:///$TARGET_DB
taler-config -c $CONF_ONCE -s bank -o database -V postgres:///$TARGET_DB

# setup exchange
echo "Setting up exchange"
taler-exchange-dbinit -c $CONF_ONCE

echo "Setting up merchant"
taler-merchant-dbinit -c $CONF_ONCE

# setup auditor
echo "Setting up auditor"
taler-auditor-dbinit -c $CONF_ONCE || exit_skip "Failed to initialize auditor DB"
taler-auditor-exchange -c $CONF_ONCE -m $MASTER_PUB -u $EXCHANGE_URL || exit_skip "Failed to add exchange to auditor"

# Launch services
echo "Launching services (pre audit DB: $TARGET_DB)"
taler-bank-manage-testing $BANK_PORT $TARGET_DB $EXCHANGE_URL $CONF_ONCE
TFN=`which taler-exchange-httpd`
TBINPFX=`dirname $TFN`
TLIBEXEC=${TBINPFX}/../lib/taler/libexec/
taler-exchange-secmod-eddsa -c $CONF_ONCE 2> taler-exchange-secmod-eddsa.log &
taler-exchange-secmod-rsa -c $CONF_ONCE 2> taler-exchange-secmod-rsa.log &
taler-exchange-secmod-cs -c $CONF_ONCE 2> taler-exchange-secmod-cs.log &
taler-exchange-httpd -c $CONF_ONCE 2> taler-exchange-httpd.log &
taler-merchant-httpd -c $CONF_ONCE -L INFO 2> taler-merchant-httpd.log &
taler-exchange-wirewatch -c $CONF_ONCE 2> taler-exchange-wirewatch.log &
taler-auditor-httpd -L INFO -c $CONF_ONCE 2> taler-auditor-httpd.log &

# Wait for all bank to be available (usually the slowest)
for n in `seq 1 50`
do
    echo -n "."
    sleep 0.2
    OK=0
    # bank
    wget http://localhost:8082/ -o /dev/null -O /dev/null >/dev/null || continue
    OK=1
    break
done

if [ 1 != $OK ]
then
    exit_skip "Failed to launch services"
fi

# Wait for all services to be available
for n in `seq 1 50`
do
    echo -n "."
    sleep 0.1
    OK=0
    # exchange
    wget http://localhost:8081/seed -o /dev/null -O /dev/null >/dev/null || continue
    # merchant
    wget http://localhost:9966/ -o /dev/null -O /dev/null >/dev/null || continue
    # Auditor
    wget http://localhost:8083/ -o /dev/null -O /dev/null >/dev/null || continue
    OK=1
    break
done

if [ 1 != $OK ]
then
    exit_skip "Failed to launch services"
fi
echo -n "Setting up keys"
taler-exchange-offline -c $CONF_ONCE \
  download sign \
  enable-account `taler-config -c $CONF_ONCE -s exchange-account-1 -o PAYTO_URI` \
  enable-auditor $AUDITOR_PUB $AUDITOR_URL "TESTKUDOS Auditor" \
  wire-fee now iban TESTKUDOS:0.07 TESTKUDOS:0.01 TESTKUDOS:0.01 \
  global-fee now TESTKUDOS:0.01 TESTKUDOS:0.01 TESTKUDOS:0.01 TESTKUDOS:0.01 1h 1h 1year 5 \
  upload &> taler-exchange-offline.log

echo -n "."

for n in `seq 1 2`
do
    echo -n "."
    OK=0
    wget --timeout=1 http://localhost:8081/keys -o /dev/null -O /dev/null >/dev/null || continue
    OK=1
    break
done

if [ 1 != $OK ]
then
    exit_skip "Failed to setup keys"
fi

echo " DONE"
echo -n "Adding auditor signatures ..."

taler-auditor-offline -c $CONF_ONCE \
  download sign upload &> taler-auditor-offline.log

echo " DONE"
# Setup merchant

echo -n "Setting up merchant"

curl -H "Content-Type: application/json" -X POST -d '{"auth":{"method":"external"},"payto_uris":["payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43"],"id":"default","name":"default","address":{},"jurisdiction":{},"default_max_wire_fee":"TESTKUDOS:1", "default_max_deposit_fee":"TESTKUDOS:1","default_wire_fee_amortization":1,"default_wire_transfer_delay":{"d_us" : 3600000000},"default_pay_delay":{"d_us": 3600000000}}' http://localhost:9966/management/instances


echo " DONE"

# run wallet CLI
echo "Running wallet"


taler-wallet-cli --no-throttle --wallet-db=$WALLET_DB api 'runIntegrationTest' \
  "$(jq -n '
    {
      amountToSpend: "TESTKUDOS:4",
      amountToWithdraw: "TESTKUDOS:10",
      bankBaseUrl: $BANK_URL,
      exchangeBaseUrl: $EXCHANGE_URL,
      merchantBaseUrl: $MERCHANT_URL,
    }' \
    --arg MERCHANT_URL "$MERCHANT_URL" \
    --arg EXCHANGE_URL "$EXCHANGE_URL" \
    --arg BANK_URL "$BANK_URL/access-api/"
  )" &> taler-wallet-cli.log

echo "Shutting down services"
cleanup

# Dump database
echo "Dumping database ${BASEDB}(-libeufin).sql"
pg_dump -O $TARGET_DB | sed -e '/AS integer/d' > ${BASEDB}.sql
sqlite3 $TARGET_DB ".dump" > ${BASEDB}-libeufin.sql

echo $MASTER_PUB > ${BASEDB}.mpub

date +%s > ${BASEDB}.age

# clean up
echo "Final clean up"
dropdb $TARGET_DB
rm $TARGET_DB # libeufin DB
rm -rf $DATA_DIR || true

echo "====================================="
echo "  Finished generation of $BASEDB"
echo "====================================="

exit 0
