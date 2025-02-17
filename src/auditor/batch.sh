#!/bin/bash
set -eu

# Cleanup to run whenever we exit
function cleanup()
{
    for n in `jobs -p`
    do
        kill $n 2> /dev/null || true
    done
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
BASEDB=${1:-"batch"}

# Name of the Postgres database we will use for the script.
# Will be dropped, do NOT use anything that might be used
# elsewhere
export TARGET_DB=`basename ${BASEDB}`

export WALLET_DB=${BASEDB:-"wallet"}.wdb

# delete existing wallet database
rm -f $WALLET_DB


# Configuration file will be edited, so we create one
# from the template.
CONF=${BASEDB}.conf
cp generate-auditor-basedb.conf $CONF


echo -n "Testing for taler-fakebank-run"
taler-fakebank-run -h >/dev/null </dev/null || exit_skip " MISSING"
echo " FOUND"
echo -n "Testing for taler-wallet-cli"
taler-wallet-cli -v >/dev/null </dev/null || exit_skip " MISSING"
echo " FOUND"
echo -n "Testing for curl"
curl --help >/dev/null </dev/null || exit_skip " MISSING"
echo " FOUND"


pwd
# Clean up

DATA_DIR=`taler-exchange-config -f -c $CONF -s PATHS -o TALER_HOME`
rm -rf $DATA_DIR || true

# reset database
dropdb $TARGET_DB >/dev/null 2>/dev/null || true
createdb $TARGET_DB || exit_skip "Could not create database $TARGET_DB"


# obtain key configuration data
MASTER_PRIV_FILE=$(taler-exchange-config -f -c $CONF -s exchange-offline -o MASTER_PRIV_FILE)
MASTER_PRIV_DIR=$(dirname $MASTER_PRIV_FILE)
mkdir -p $MASTER_PRIV_DIR
gnunet-ecc -g1 $MASTER_PRIV_FILE > /dev/null
MASTER_PUB=$(gnunet-ecc -p $MASTER_PRIV_FILE)
EXCHANGE_URL=$(taler-exchange-config -c $CONF -s EXCHANGE -o BASE_URL)
MERCHANT_PORT=$(taler-merchant-config -c $CONF -s MERCHANT -o PORT)
MERCHANT_URL=http://localhost:${MERCHANT_PORT}/
BANK_PORT=$(taler-exchange-config -c $CONF -s BANK -o HTTP_PORT)
BANK_URL=http://localhost:${BANK_PORT}/
AUDITOR_URL=http://localhost:8083/
AUDITOR_PRIV_FILE=$(taler-auditor-config -f -c $CONF -s AUDITOR -o AUDITOR_PRIV_FILE)
AUDITOR_PRIV_DIR=$(dirname $AUDITOR_PRIV_FILE)
mkdir -p $AUDITOR_PRIV_DIR
gnunet-ecc -g1 $AUDITOR_PRIV_FILE > /dev/null
AUDITOR_PUB=$(gnunet-ecc -p $AUDITOR_PRIV_FILE)

echo "AUDITOR PUB is $AUDITOR_PUB using file $AUDITOR_PRIV_FILE"

# patch configuration
taler-exchange-config \
    -c $CONF \
    -s exchange \
    -o MASTER_PUBLIC_KEY \
    -V $MASTER_PUB
taler-auditor-config \
    -c $CONF \
    -s auditor \
    -o PUBLIC_KEY \
    -V $AUDITOR_PUB
taler-merchant-config \
    -c $CONF \
    -s merchant-exchange-default \
    -o MASTER_KEY \
    -V $MASTER_PUB
taler-exchange-config \
    -c $CONF \
    -s exchangedb-postgres \
    -o CONFIG \
    -V postgres:///$TARGET_DB
taler-auditor-config \
    -c $CONF \
    -s auditordb-postgres \
    -o CONFIG \
    -V postgres:///$TARGET_DB
taler-merchant-config \
    -c $CONF \
    -s merchantdb-postgres \
    -o CONFIG \
    -V postgres:///$TARGET_DB
taler-exchange-config \
    -c $CONF \
    -s bank \
    -o database \
    -V postgres:///$TARGET_DB

# setup exchange
echo "Setting up exchange"
taler-exchange-dbinit -c $CONF

echo "Setting up merchant"
taler-merchant-dbinit -c $CONF

# setup auditor
echo "Setting up auditor"
taler-auditor-dbinit -c $CONF || exit_skip "Failed to initialize auditor DB"
taler-auditor-exchange -c $CONF -m $MASTER_PUB -u $EXCHANGE_URL || exit_skip "Failed to add exchange to auditor"

# Launch services
echo "Launching services"
taler-fakebank-run -c $CONF &> taler-bank.log &
TFN=`which taler-exchange-httpd`
TBINPFX=`dirname $TFN`
TLIBEXEC=${TBINPFX}/../lib/taler/libexec/
taler-exchange-secmod-eddsa -c $CONF 2> taler-exchange-secmod-eddsa.log &
taler-exchange-secmod-rsa -c $CONF 2> taler-exchange-secmod-rsa.log &
taler-exchange-secmod-cs -c $CONF 2> taler-exchange-secmod-cs.log &
taler-exchange-httpd -c $CONF 2> taler-exchange-httpd.log &
taler-merchant-httpd -c $CONF -L INFO 2> taler-merchant-httpd.log &
taler-exchange-wirewatch -c $CONF 2> taler-exchange-wirewatch.log &
taler-auditor-httpd -L INFO -c $CONF 2> taler-auditor-httpd.log &

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
echo " DONE"

echo -n "Setting up keys"
taler-exchange-offline -c $CONF \
  download sign \
  enable-account payto://x-taler-bank/localhost/Exchange \
  enable-auditor $AUDITOR_PUB $AUDITOR_URL "TESTKUDOS Auditor" \
  wire-fee now x-taler-bank TESTKUDOS:0.01 TESTKUDOS:0.01 TESTKUDOS:0.01 \
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

taler-auditor-offline -c $CONF \
  download sign upload &> taler-auditor-offline.log

echo " DONE"
# Setup merchant

echo -n "Setting up merchant"

curl -H "Content-Type: application/json" -X POST -d '{"auth":{"method":"external"},"accounts":[{"payto_uri":"payto://x-taler-bank/localhost/43"}],"id":"default","name":"default","address":{},"jurisdiction":{},"default_max_wire_fee":"TESTKUDOS:1", "default_max_deposit_fee":"TESTKUDOS:1","default_wire_fee_amortization":1,"default_wire_transfer_delay":{"d_us" : 3600000000},"default_pay_delay":{"d_us": 3600000000}}' http://localhost:9966/management/instances


echo " DONE"

# run wallet CLI
echo "Ready to run wallet"
export WALLET_DB
export EXCHANGE_URL
export MERCHANT_URL
export BANK_URL
unset TALER_WALLET_INSECURE_TRUST_EXCHANGE
export TALER_WALLET_BATCH_WITHDRAWAL=1
echo 'taler-wallet-cli --wallet-db=$WALLET_DB -L TRACE advanced bench1 --config-json "{ \"exchange\": \"$EXCHANGE_URL\", \"bank\": \"${BANK_URL}\", \"currency\": \"TESTKUDOS\", \"payto\": \"payto://x-taler-bank/localhost/foo\", \"iterations\": 100000, \"deposits\": 10, \"restartAfter\": 2 }"'
bash

#taler-wallet-cli --no-throttle --wallet-db=$WALLET_DB api 'runIntegrationTest' \
#  "$(jq -n '
#    {
#      amountToSpend: "TESTKUDOS:4",
#      amountToWithdraw: "TESTKUDOS:10",
#      corebankApiBaseUrl: $BANK_URL,
#      exchangeBaseUrl: $EXCHANGE_URL,
#      merchantBaseUrl: $MERCHANT_URL,
#    }' \
#    --arg MERCHANT_URL "$MERCHANT_URL" \
#    --arg EXCHANGE_URL "$EXCHANGE_URL" \
#    --arg BANK_URL "$BANK_URL"
#  )" &> taler-wallet-cli.log


echo "Shutting down services"
cleanup

# clean up
echo "Final clean up"
dropdb $TARGET_DB

rm -rf $DATA_DIR || true
exit 0
