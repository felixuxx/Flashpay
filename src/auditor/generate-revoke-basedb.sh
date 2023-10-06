#!/bin/bash
# Script to test revocation.
#
# Requires the wallet CLI to be installed and in the path.  Furthermore, the
# user running this script must be Postgres superuser and be allowed to
# create/drop databases.
#
set -eu
# set -x

. setup.sh

echo -n "Testing for curl ..."
curl --help >/dev/null </dev/null || exit_skip " MISSING"
echo " FOUND"

CONF="generate-auditor-basedb.conf"

# reset database
echo -n "Reset 'auditor-basedb' database ..."
dropdb "auditor-basedb" >/dev/null 2>/dev/null || true
createdb "auditor-basedb" || exit_skip "Could not create database '$BASEDB'"
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
BANK_URL="http://localhost:1${BANK_PORT}"


# Setup merchant
echo -n "Setting up merchant ..."
curl -H "Content-Type: application/json" -X POST -d '{"auth": {"method": "external"}, "accounts":[{"payto_uri":"payto://iban/SANDBOXX/DE474361?receiver-name=Merchant43"}],"id":"default","name":"default","address":{},"jurisdiction":{},"default_max_wire_fee":"TESTKUDOS:1", "default_max_deposit_fee":"TESTKUDOS:1","default_wire_fee_amortization":1,"default_wire_transfer_delay":{"d_us" : 3600000000},"default_pay_delay":{"d_us": 3600000000}}' "${MERCHANT_URL}management/instances"
echo " DONE"


# run wallet CLI
echo "Running wallet"

export WALLET_DB="wallet.wdb"
rm -f "$WALLET_DB"

taler-wallet-cli \
    --no-throttle \
    --wallet-db="$WALLET_DB" \
    api \
    --expect-success 'withdrawTestBalance' \
  "$(jq -n '
    {
      amount: "TESTKUDOS:8",
      corebankApiBaseUrl: $BANK_URL,
      exchangeBaseUrl: $EXCHANGE_URL,
    }' \
    --arg BANK_URL "$BANK_URL/demobanks/default/access-api/" \
    --arg EXCHANGE_URL "$EXCHANGE_URL"
  )" &> taler-wallet-cli-withdraw.log

taler-wallet-cli \
    --no-throttle \
    --wallet-db="$WALLET_DB" \
    run-until-done \
    &> taler-wallet-cli-withdraw-finish.log

export COINS=$(taler-wallet-cli --wallet-db="$WALLET_DB" advanced dump-coins)

echo -n "COINS are:"
echo "$COINS"

# Find coin we want to revoke
export rc=$(echo "$COINS" | jq -r '[.coins[] | select((.denom_value == "TESTKUDOS:2"))][0] | .coin_pub')
# Find the denom
export rd=$(echo "$COINS" | jq -r '[.coins[] | select((.denom_value == "TESTKUDOS:2"))][0] | .denom_pub_hash')
echo -n "Revoking denomination ${rd} (to affect coin ${rc}) ..."
# Find all other coins, which will be suspended
export susp=$(echo "$COINS" | jq --arg rc "$rc" '[.coins[] | select(.coin_pub != $rc) | .coin_pub]')

# Do the revocation
taler-exchange-offline \
    -c $CONF \
    revoke-denomination "${rd}" \
    upload \
    &> taler-exchange-offline-revoke.log
echo "DONE"

echo -n "Signing replacement keys ..."
sleep 1 # Give exchange time to create replacmenent key

# Re-sign replacement keys
taler-auditor-offline \
    -c $CONF \
    download \
    sign \
    upload \
    &> taler-auditor-offline-reinit.log
echo " DONE"

# Now we suspend the other coins, so later we will pay with the recouped coin
taler-wallet-cli \
    --wallet-db="$WALLET_DB" \
    advanced \
    suspend-coins "$susp"

# Update exchange /keys so recoup gets scheduled
taler-wallet-cli \
    --wallet-db="$WALLET_DB" \
    exchanges \
    update \
    -f "$EXCHANGE_URL"

# Block until scheduled operations are done
taler-wallet-cli \
    --wallet-db="$WALLET_DB"\
    run-until-done

# Now we buy something, only the coins resulting from recoup will be
# used, as other ones are suspended
taler-wallet-cli \
    --no-throttle \
    --wallet-db="$WALLET_DB" \
    api \
    'testPay' \
  "$(jq -n '
    {
      amount: "TESTKUDOS:1",
      merchantBaseUrl: $MERCHANT_URL,
      summary: "foo",
    }' \
    --arg MERCHANT_URL "$MERCHANT_URL"
  )"

taler-wallet-cli \
    --wallet-db="$WALLET_DB" \
    run-until-done

echo "Purchase with recoup'ed coin (via reserve) done"

# Find coin we want to refresh, then revoke
export rrc=$(echo "$coins" | jq -r '[.coins[] | select((.denom_value == "TESTKUDOS:5"))][0] | .coin_pub')
# Find the denom
export zombie_denom=$(echo "$coins" | jq -r '[.coins[] | select((.denom_value == "TESTKUDOS:5"))][0] | .denom_pub_hash')

echo "Will refresh coin ${rrc} of denomination ${zombie_denom}"
# Find all other coins, which will be suspended
export susp=$(echo "$coins" | jq --arg rrc "$rrc" '[.coins[] | select(.coin_pub != $rrc) | .coin_pub]')

# Travel into the future! (must match DURATION_WITHDRAW option)
export TIMETRAVEL="--timetravel=604800000000"

echo "Launching exchange 1 week in the future"
kill -TERM $EXCHANGE_PID
kill -TERM $RSA_DENOM_HELPER_PID
kill -TERM $CS_DENOM_HELPER_PID
kill -TERM $SIGNKEY_HELPER_PID
taler-exchange-secmod-eddsa $TIMETRAVEL -c $CONF 2> ${MY_TMP_DIR}/taler-exchange-secmod-eddsa.log &
SIGNKEY_HELPER_PID=$!
taler-exchange-secmod-rsa $TIMETRAVEL -c $CONF 2> ${MY_TMP_DIR}/taler-exchange-secmod-rsa.log &
RSA_DENOM_HELPER_PID=$!
taler-exchange-secmod-cs $TIMETRAVEL -c $CONF 2> ${MY_TMP_DIR}/taler-exchange-secmod-cs.log &
CS_DENOM_HELPER_PID=$!
taler-exchange-httpd $TIMETRAVEL -c $CONF 2> ${MY_TMP_DIR}/taler-exchange-httpd.log &
export EXCHANGE_PID=$!

# Wait for exchange to be available
for n in `seq 1 50`
do
    echo -n "."
    sleep 0.1
    OK=0
    # exchange
    wget http://localhost:8081/ -o /dev/null -O /dev/null >/dev/null || continue
    OK=1
    break
done

echo "Refreshing coin $rrc"
taler-wallet-cli \
    "$TIMETRAVEL" \
    --wallet-db="$WALLET_DB" \
    advanced force-refresh \
    "$rrc"
taler-wallet-cli \
    "$TIMETRAVEL" \
    --wallet-db="$WALLET_DB" \
    run-until-done

# Update our list of the coins
export coins=$(taler-wallet-cli $TIMETRAVEL --wallet-db=$WALLET_DB advanced dump-coins)

# Find resulting refreshed coin
export freshc=$(echo "$coins" | jq -r --arg rrc "$rrc" \
  '[.coins[] | select((.refresh_parent_coin_pub == $rrc) and .denom_value == "TESTKUDOS:0.1")][0] | .coin_pub'
)

# Find the denom of freshc
export fresh_denom=$(echo "$coins" | jq -r --arg rrc "$rrc" \
  '[.coins[] | select((.refresh_parent_coin_pub == $rrc) and .denom_value == "TESTKUDOS:0.1")][0] | .denom_pub_hash'
)

echo "Coin ${freshc} of denomination ${fresh_denom} is the result of the refresh"

# Find all other coins, which will be suspended
export susp=$(echo "$coins" | jq --arg freshc "$freshc" '[.coins[] | select(.coin_pub != $freshc) | .coin_pub]')


# Do the revocation of freshc
echo "Revoking ${fresh_denom} (to affect coin ${freshc})"
taler-exchange-offline \
    -c "$CONF" \
    revoke-denomination \
    "${fresh_denom}" \
    upload &> taler-exchange-offline-revoke-2.log

sleep 1 # Give exchange time to create replacmenent key

# Re-sign replacement keys
taler-auditor-offline \
    -c "$CONF" \
    download \
    sign \
    upload &> taler-auditor-offline.log

# Now we suspend the other coins, so later we will pay with the recouped coin
taler-wallet-cli \
    "$TIMETRAVEL" \
    --wallet-db="$WALLET_DB" \
    advanced \
    suspend-coins "$susp"

# Update exchange /keys so recoup gets scheduled
taler-wallet-cli \
    "$TIMETRAVEL"\
    --wallet-db="$WALLET_DB" \
    exchanges update \
    -f "$EXCHANGE_URL"

# Block until scheduled operations are done
taler-wallet-cli \
    "$TIMETRAVEL" \
    --wallet-db="$WALLET_DB" \
    run-until-done

echo "Restarting merchant (so new keys are known)"
kill -TERM $MERCHANT_PID
taler-merchant-httpd \
    -c "$CONF" \
    -L INFO \
    2> ${MY_TMP_DIR}/taler-merchant-httpd.log &
MERCHANT_PID=$!

# Wait for merchant to be again available
for n in `seq 1 50`
do
    echo -n "."
    sleep 0.1
    OK=0
    # merchant
    wget http://localhost:9966/ -o /dev/null -O /dev/null >/dev/null || continue
    OK=1
    break
done

# Now we buy something, only the coins resulting from recoup+refresh will be
# used, as other ones are suspended
taler-wallet-cli $TIMETRAVEL --no-throttle --wallet-db=$WALLET_DB api 'testPay' \
  "$(jq -n '
    {
      amount: "TESTKUDOS:0.02",
      merchantBaseUrl: $MERCHANT_URL,
      summary: "bar",
    }' \
    --arg MERCHANT_URL $MERCHANT_URL
  )"
taler-wallet-cli \
    "$TIMETRAVEL" \
    --wallet-db="$WALLET_DB" \
    run-until-done

echo "Bought something with refresh-recouped coin"

echo "Shutting down services"
exit_cleanup


# Where do we write the result?
export BASEDB=${1:-"revoke-basedb"}


# Dump database
echo "Dumping database ${BASEDB}.sql"
pg_dump -O "auditor-basedb" | sed -e '/AS integer/d' > "${BASEDB}.sql"

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
