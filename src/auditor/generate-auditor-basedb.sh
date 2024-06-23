#!/bin/bash
# This file is in the public domain.
#
# Script to generate the basic database for auditor testing from a 'correct'
# interaction between exchange, wallet and merchant.
#
# Creates "$1.sql".
#
# Requires the wallet CLI to be installed and in the path.  Furthermore, the
# user running this script must be Postgres superuser and be allowed to
# create/drop databases.
#
set -eu

. setup.sh

CONF="generate-auditor-basedb.conf"
# Parse command-line options
while getopts ':c:d:h' OPTION; do
    case "$OPTION" in
        c)
            CONF="$OPTARG"
            ;;
        d)
            BASEDB="$OPTARG"
            ;;
        h)
            echo 'Supported options:'
# shellcheck disable=SC2016
            echo '  -c $CONF     -- set configuration'
# shellcheck disable=SC2016
            echo '  -d $DB       -- set database name'
            ;;
        ?)
        exit_fail "Unrecognized command line option"
        ;;
    esac
done

# Where do we write the result?
if [ ! -v BASEDB ]
then
    exit_fail "-d option required"
fi
echo -n "Testing for curl ..."
curl --help >/dev/null </dev/null || exit_skip " MISSING"
echo " FOUND"

# reset database
echo -n "Reset 'auditor-basedb' database at $PGHOST ..."
dropdb --if-exists "auditor-basedb" > /dev/null 2> /dev/null || true
createdb "auditor-basedb" || exit_skip "Could not create database '$BASEDB' at $PGHOST"
echo " DONE"

# Launch exchange, merchant and bank.
setup -c "$CONF" \
      -abemw \
      -d "iban"

# obtain key configuration data
EXCHANGE_URL=$(taler-config -c "$CONF" -s EXCHANGE -o BASE_URL)
MERCHANT_PORT=$(taler-config -c "$CONF" -s MERCHANT -o PORT)
MERCHANT_URL="http://localhost:${MERCHANT_PORT}/"
BANK_PORT=$(taler-config -c "$CONF" -s BANK -o HTTP_PORT)
BANK_URL="http://localhost:${BANK_PORT}/"

echo -n "Checking setup worked ..."
wget \
    --tries=1 \
    --timeout=1 \
    "${EXCHANGE_URL}config" \
    -o /dev/null \
    -O /dev/null >/dev/null
echo "DONE"

export MERCHANT_URL
echo -n "Setting up merchant ..."

curl -H "Content-Type: application/json" -X POST -d '{"auth":{"method":"external"},"id":"default","name":"default","address":{},"jurisdiction":{},"default_max_wire_fee":"TESTKUDOS:1", "default_max_deposit_fee":"TESTKUDOS:1","default_wire_fee_amortization":1,"default_wire_transfer_delay":{"d_us" : 3600000000},"default_pay_delay":{"d_us": 3600000000},"use_stefan":false}' "${MERCHANT_URL}management/instances"
echo " DONE"

echo -n "Setting up merchant account ..."
FORTYTHREE="payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43"
STATUS=$(curl -H "Content-Type: application/json" -X POST \
    "${MERCHANT_URL}private/accounts" \
    -d '{"payto_uri":"'"$FORTYTHREE"'"}' \
    -w "%{http_code}" -s -o /dev/null)

if [ "$STATUS" != "200" ]
then
    exit_fail "Expected 200 OK. Got: $STATUS"
fi
echo " DONE"

# delete existing wallet database
export WALLET_DB="wallet.wdb"
rm -f "$WALLET_DB"

echo -n "Running wallet ..."
taler-wallet-cli \
    --no-throttle \
    --wallet-db="$WALLET_DB" \
    api \
    --expect-success \
    'runIntegrationTest' \
  "$(jq -n '
    {
      amountToSpend: "TESTKUDOS:4",
      amountToWithdraw: "TESTKUDOS:10",
      corebankApiBaseUrl: $BANK_URL,
      exchangeBaseUrl: $EXCHANGE_URL,
      merchantBaseUrl: $MERCHANT_URL,
    }' \
    --arg MERCHANT_URL "$MERCHANT_URL" \
    --arg EXCHANGE_URL "$EXCHANGE_URL" \
    --arg BANK_URL "$BANK_URL"
  )" &> taler-wallet-cli.log
echo " DONE"

taler-wallet-cli --wallet-db="$WALLET_DB" run-until-done

# Dump database
mkdir -p "$(dirname "$BASEDB")"

echo "Dumping database ${BASEDB}.sql"
pg_dump -O "auditor-basedb" | sed -e '/AS integer/d' > "${BASEDB}.sql"
cp "${CONF}.edited" "${BASEDB}.conf"
cp "$(taler-config -c "${CONF}.edited" -s exchange-offline -o MASTER_PRIV_FILE -f)" "${BASEDB}.mpriv"

# clean up
echo -n "Final clean up ..."
kill -TERM "$SETUP_PID"
wait
unset SETUP_PID
dropdb "auditor-basedb"
echo " DONE"

echo "====================================="
echo "Finished generation of ${BASEDB}.sql"
echo "====================================="

exit 0
