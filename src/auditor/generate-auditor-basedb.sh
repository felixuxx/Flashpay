#!/bin/bash
# Script to generate the basic database for auditor
# testing from a 'correct' interaction between exchange,
# wallet and merchant.
#
# Creates $BASEDB.sql, $BASEDB.fees,
# $BASEDB.{mpub,mpriv}.
# Default $BASEDB is "auditor-basedb", override via $1.
#
# Currently must be run online as it interacts with
# bank.test.taler.net; also requires the wallet CLI
# to be installed and in the path.  Furthermore, the
# user running this script must be Postgres superuser
# and be allowed to create/drop databases.
#
set -eux

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
function exit_cleanup()
{
    echo "Running generate-auditor-basedb exit cleanup logic..."
    if test -f libeufin-sandbox.pid
    then
        PID=`cat libeufin-sandbox.pid 2> /dev/null`
        kill $PID 2> /dev/null || true
        rm libeufin-sandbox.pid
        echo "Killed libeufin sandbox $PID"
        wait $PID || true
    fi
    if test -f libeufin-nexus.pid
    then
        PID=`cat libeufin-nexus.pid 2> /dev/null`
        kill $PID 2> /dev/null || true
        rm libeufin-nexus.pid
        echo "Killed libeufin nexus $PID"
        wait $PID || true
    fi
    echo "killing libeufin DONE"
    for n in `jobs -p`
    do
        kill $n 2> /dev/null || true
    done
    wait || true
}

# Install cleanup handler (except for kill -9)
trap exit_cleanup EXIT


# Exit, with status code "skip" (no 'real' failure)
function exit_skip() {
    echo "SKIPPING: $1"
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

# Configuration file will be edited, so we create one
# from the template.
export CONF=$1.conf
cp generate-auditor-basedb.conf $CONF
echo "Created configuration at ${CONF}"

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

DATA_DIR=`taler-config -f -c $CONF -s PATHS -o TALER_HOME`

# reset database
dropdb $TARGET_DB >/dev/null 2>/dev/null || true
createdb $TARGET_DB || exit_skip "Could not create database $TARGET_DB"

# obtain key configuration data
MASTER_PRIV_FILE=$1.mpriv
MASTER_PRIV_DIR=`dirname $MASTER_PRIV_FILE`
taler-config -f -c ${CONF} -s exchange-offline -o MASTER_PRIV_FILE -V ${MASTER_PRIV_FILE}
rm -f "${MASTER_PRIV_FILE}"
mkdir -p $MASTER_PRIV_DIR
gnunet-ecc -l/dev/null -g1 $MASTER_PRIV_FILE > /dev/null
export MASTER_PUB=`gnunet-ecc -p $MASTER_PRIV_FILE`
export EXCHANGE_URL=`taler-config -c $CONF -s EXCHANGE -o BASE_URL`
MERCHANT_PORT=`taler-config -c $CONF -s MERCHANT -o PORT`
export MERCHANT_URL=http://localhost:${MERCHANT_PORT}/
BANK_PORT=`taler-config -c $CONF -s BANK -o HTTP_PORT`
BANK_URL="http://localhost:1${BANK_PORT}/demobanks/default"
export AUDITOR_URL=http://localhost:8083/
AUDITOR_PRIV_FILE=$1.apriv
AUDITOR_PRIV_DIR=`dirname $AUDITOR_PRIV_FILE`
taler-config -f -c ${CONF} -s auditor -o AUDITOR_PRIV_FILE -V ${AUDITOR_PRIV_FILE}
mkdir -p $AUDITOR_PRIV_DIR
gnunet-ecc -l/dev/null -g1 $AUDITOR_PRIV_FILE > /dev/null
AUDITOR_PUB=`gnunet-ecc -p $AUDITOR_PRIV_FILE`

echo "MASTER PUB is ${MASTER_PUB} using file ${MASTER_PRIV_FILE}"
echo "AUDITOR PUB is ${AUDITOR_PUB} using file ${AUDITOR_PRIV_FILE}"

# patch configuration
taler-config -c $CONF -s exchange -o MASTER_PUBLIC_KEY -V $MASTER_PUB
taler-config -c $CONF -s auditor -o PUBLIC_KEY -V $AUDITOR_PUB
taler-config -c $CONF -s merchant-exchange-default -o MASTER_KEY -V $MASTER_PUB

taler-config -c $CONF -s exchangedb-postgres -o CONFIG -V postgres:///$TARGET_DB
taler-config -c $CONF -s auditordb-postgres -o CONFIG -V postgres:///$TARGET_DB
taler-config -c $CONF -s merchantdb-postgres -o CONFIG -V postgres:///$TARGET_DB
taler-config -c $CONF -s bank -o database -V postgres:///$TARGET_DB

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
echo "Launching services (pre audit DB: $TARGET_DB)"

rm -f ${TARGET_DB}-sandbox.sqlite3 ${TARGET_DB}-nexus.sqlite3 2> /dev/null # libeufin DB
export LIBEUFIN_SANDBOX_DB_CONNECTION="jdbc:sqlite:${TARGET_DB}-sandbox.sqlite3"
# Create the default demobank.
libeufin-sandbox config --currency "TESTKUDOS" default
export LIBEUFIN_SANDBOX_ADMIN_PASSWORD=secret
libeufin-sandbox serve --port "1${BANK_PORT}" \
  > libeufin-sandbox-stdout.log \
  2> libeufin-sandbox-stderr.log &
echo $! > libeufin-sandbox.pid
export LIBEUFIN_SANDBOX_URL="http://localhost:1${BANK_PORT}/demobanks/default"
set +e
echo -n "Waiting for Sandbox..."
OK=0
for n in `seq 1 50`; do
  echo -n "."
  sleep 1
  if wget --timeout=1 \
    --tries=3 --waitretry=0 \
    -o /dev/null -O /dev/null \
    $LIBEUFIN_SANDBOX_URL;
  then
    OK=1
    break
  fi
done
if test $OK != 1
then
    exit_skip " Failed to launch sandbox"
fi
echo "OK"

register_sandbox_account() {
    export LIBEUFIN_SANDBOX_USERNAME=$1
    export LIBEUFIN_SANDBOX_PASSWORD=$2
    libeufin-cli sandbox \
      demobank \
      register --name "$3"
    unset LIBEUFIN_SANDBOX_USERNAME
    unset LIBEUFIN_SANDBOX_PASSWORD
}
set -e
echo -n "Register the 'fortytwo' Sandbox user.."
register_sandbox_account fortytwo x "Forty Two"
echo OK
echo -n "Register the 'fortythree' Sandbox user.."
register_sandbox_account fortythree x "Forty Three"
echo OK
echo -n "Register 'exchange' Sandbox user.."
register_sandbox_account exchange x "Exchange Company"
echo OK
echo -n "Specify exchange's PAYTO_URI in the config ..."
export LIBEUFIN_SANDBOX_USERNAME=exchange
export LIBEUFIN_SANDBOX_PASSWORD=x
PAYTO=`libeufin-cli sandbox demobank info --bank-account exchange | jq --raw-output '.paytoUri'`
taler-config -c $CONF -s exchange-account-1 -o PAYTO_URI -V $PAYTO
echo " OK"
echo -n "Setting this exchange as the bank's default ..."
EXCHANGE_PAYTO=`libeufin-cli sandbox demobank info --bank-account exchange | jq --raw-output '.paytoUri'`
libeufin-sandbox default-exchange "$EXCHANGE_URL" "$EXCHANGE_PAYTO"
echo " OK"
# Prepare EBICS: create Ebics host and Exchange subscriber.
# Shortly becoming admin to setup Ebics.
export LIBEUFIN_SANDBOX_USERNAME=admin
export LIBEUFIN_SANDBOX_PASSWORD=secret
echo -n "Create EBICS host at Sandbox.."
libeufin-cli sandbox \
  --sandbox-url "http://localhost:1${BANK_PORT}" \
  ebicshost create --host-id "talerebics"
echo "OK"
echo -n "Create exchange EBICS subscriber at Sandbox.."
libeufin-cli sandbox \
  demobank new-ebicssubscriber --host-id talerebics \
  --user-id exchangeebics --partner-id talerpartner \
  --bank-account exchange # that's a username _and_ a bank account name
echo "OK"
unset LIBEUFIN_SANDBOX_USERNAME
unset LIBEUFIN_SANDBOX_PASSWORD
# Prepare Nexus, which is the side actually talking
# to the exchange.
export LIBEUFIN_NEXUS_DB_CONNECTION="jdbc:sqlite:${TARGET_DB}-nexus.sqlite3"
# For convenience, username and password are
# identical to those used at the Sandbox.
echo -n "Create exchange Nexus user..."
libeufin-nexus superuser exchange --password x
echo " OK"
libeufin-nexus serve --port ${BANK_PORT} \
  2> libeufin-nexus-stderr.log \
  > libeufin-nexus-stdout.log &
echo $! > libeufin-nexus.pid
export LIBEUFIN_NEXUS_URL="http://localhost:${BANK_PORT}"
echo -n "Waiting for Nexus..."
set +e
OK=0
for n in `seq 1 50`; do
  echo -n "."
  sleep 1
  if wget --timeout=1 \
    --tries=3 --waitretry=0 \
    -o /dev/null -O /dev/null \
    $LIBEUFIN_NEXUS_URL;
  then
    OK=1
    break
  fi
done
if test $OK != 1
then
    exit_skip " Failed to launch Nexus at $LIBEUFIN_NEXUS_URL"
fi
set -e
echo "OK"
export LIBEUFIN_NEXUS_USERNAME=exchange
export LIBEUFIN_NEXUS_PASSWORD=x
echo -n "Creating an EBICS connection at Nexus..."
libeufin-cli connections new-ebics-connection \
  --ebics-url "http://localhost:1${BANK_PORT}/ebicsweb" \
  --host-id "talerebics" \
  --partner-id "talerpartner" \
  --ebics-user-id "exchangeebics" \
  talerconn
echo "OK"
echo -n "Setup EBICS keying..."
libeufin-cli connections connect "talerconn" > /dev/null
echo "OK"
echo -n "Download bank account name from Sandbox..."
libeufin-cli connections download-bank-accounts "talerconn"
echo "OK"
echo -n "Importing bank account info into Nexus..."
libeufin-cli connections import-bank-account \
  --offered-account-id "exchange" \
  --nexus-bank-account-id "exchange-nexus" \
  "talerconn"
echo "OK"
echo -n "Setup payments submission task..."
# Tries every second.
libeufin-cli accounts task-schedule \
  --task-type submit \
  --task-name "exchange-payments" \
  --task-cronspec "* * *" \
  "exchange-nexus"
echo "OK"
# Tries every second.  Ask C52
echo -n "Setup history fetch task..."
libeufin-cli accounts task-schedule \
  --task-type fetch \
  --task-name "exchange-history" \
  --task-cronspec "* * *" \
  --task-param-level report \
  --task-param-range-type latest \
  "exchange-nexus"
echo "OK"
# create Taler facade.
echo -n "Create the Taler facade at Nexus..."
libeufin-cli facades \
  new-taler-wire-gateway-facade \
  --currency "TESTKUDOS" --facade-name "test-facade" \
  "talerconn" "exchange-nexus"
echo "OK"
# Facade schema: http://localhost:$BANK_PORT/facades/test-facade/taler-wire-gateway/


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
echo -n "Setting up keys"
taler-exchange-offline -c $CONF \
  download sign \
  enable-account `taler-config -c $CONF -s exchange-account-1 -o PAYTO_URI` \
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

taler-auditor-offline -c $CONF \
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

bash

echo "Shutting down services"
exit_cleanup

# Dump database
echo "Dumping database ${BASEDB}(-libeufin).sql"
pg_dump -O $TARGET_DB | sed -e '/AS integer/d' > ${BASEDB}.sql
sqlite3 ${TARGET_DB}-nexus.sqlite3 ".dump" > ${BASEDB}-libeufin-nexus.sql
sqlite3 ${TARGET_DB}-sandbox.sqlite3 ".dump" > ${BASEDB}-libeufin-sandbox.sql

echo $MASTER_PUB > ${BASEDB}.mpub

# clean up
echo "Final clean up"
dropdb $TARGET_DB
rm ${TARGET_DB}-sandbox.sqlite3 ${TARGET_DB}-nexus.sqlite3 # libeufin DB

echo "====================================="
echo "  Finished generation of $BASEDB"
echo "====================================="

exit 0
