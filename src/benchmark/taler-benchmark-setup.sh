#!/bin/bash
#
# This file is part of TALER
# Copyright (C) 2023 Taler Systems SA
#
# TALER is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 3, or
# (at your option) any later version.
#
# TALER is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with TALER; see the file COPYING.  If not, see
# <http://www.gnu.org/licenses/>
#

set -eu

# Exit, with status code "skip" (no 'real' failure)
function exit_skip() {
    echo " SKIP: " "$@"
    exit 77
}

# Exit, with error message (hard failure)
function exit_fail() {
    echo " FAIL: " "$@"
    exit 1
}

# Cleanup to run whenever we exit
function cleanup()
{
    for n in $(jobs -p)
    do
        kill $n 2> /dev/null || true
    done
    wait
    rm -f libeufin-nexus.pid libeufin-sandbox.pid
}

# Install cleanup handler (except for kill -9)
trap cleanup EXIT

START_AUDITOR=0
START_BACKUP=0
START_EXCHANGE=0
START_FAKEBANK=0
START_MERCHANT=0
START_NEXUS=0
START_SANDBOX=0
USE_VALGRIND=""
CONF_ORIG="~/.config/taler.conf"
LOGLEVEL="DEBUG"
DEFAULT_SLEEP="0.2"

# Parse command-line options
while getopts ':abc:efhl:mnsv' OPTION; do
    case "$OPTION" in
        a)
            START_AUDITOR="1"
            ;;
        b)
            START_BACKUP="1"
            ;;
        c)
            CONF_ORIG="$OPTARG"
            ;;
        e)
            START_EXCHANGE="1"
            ;;
        f)
            START_FAKEBANK="1"
            ;;
        h)
            echo 'Supported options:'
            echo '  -a           -- start auditor'
            echo '  -b           -- start backup/sync'
            echo '  -c $CONF     -- set configuration'
            echo '  -e           -- start exchange'
            echo '  -f           -- start fakebank'
            echo '  -h           -- print this help'
            echo '  -l $LOGLEVEL -- set log level'
            echo '  -m           -- start merchant'
            echo '  -n           -- start nexus'
            echo '  -s           -- start sandbox'
            echo '  -v           -- use valgrind'
            exit 0
            ;;
        l)
            LOGLEVEL="$OPTARG"
            ;;
        m)
            START_MERCHANT="1"
            ;;
        n)
            START_NEXUS="1"
            ;;
        s)
            START_SANDBOX="1"
            ;;
        v)
            USE_VALGRIND="valgrind --leak-check=yes"
            DEFAULT_SLEEP="2"
            ;;
        ?)
        exit_fail "Unrecognized command line option"
        ;;
    esac
done

echo "Starting with configuration file at: $CONF_ORIG"
CONF="$CONF_ORIG.edited"
cp "${CONF_ORIG}" "${CONF}"

echo -n "Testing for jq"
jq -h > /dev/null || exit_skip " jq required"
echo " FOUND"

if [ "1" = "$START_EXCHANGE" ]
then
    echo -n "Testing for Taler exchange"
    taler-exchange-httpd -h > /dev/null || exit_skip " taler-exchange-httpd required"
    echo " FOUND"
fi

if [ "1" = "$START_MERCHANT" ]
then
    echo -n "Testing for Taler merchant"
    taler-merchant-httpd -h > /dev/null || exit_skip " taler-merchant-httpd required"
    echo " FOUND"
fi

if [ "1" = "$START_BACKUP" ]
then
    echo -n "Testing for sync-httpd"
    sync-httpd -h > /dev/null || exit_skip " sync-httpd required"
    echo " FOUND"
fi

if [ "1" = "$START_NEXUS" ]
then
    echo -n "Testing for libeufin-cli"
    libeufin-cli --help >/dev/null </dev/null || exit_skip " MISSING"
    echo " FOUND"
fi

EXCHANGE_URL=$(taler-config -c "$CONF" -s "EXCHANGE" -o "BASE_URL")
CURRENCY=$(taler-config -c "$CONF" -s "TALER" -o "CURRENCY")

register_sandbox_account() {
    export LIBEUFIN_SANDBOX_USERNAME="$1"
    export LIBEUFIN_SANDBOX_PASSWORD="$2"
    libeufin-cli sandbox \
      demobank \
      delete \
      --bank-account "$1" &> /dev/null || true
    libeufin-cli sandbox \
      demobank \
      register --name "$3"
    unset LIBEUFIN_SANDBOX_USERNAME
    unset LIBEUFIN_SANDBOX_PASSWORD
}


BANK_PORT=$(taler-config -c "$CONF" -s "BANK" -o "HTTP_PORT")
if [ "1" = "$START_NEXUS" ]
then
    NEXUS_PORT="$BANK_PORT"
    SANDBOX_PORT="1$BANK_PORT"
else
    NEXUS_PORT="0"
    SANDBOX_PORT="1$BANK_PORT"
fi

if [ "1" = "$START_SANDBOX" ]
then
    export LIBEUFIN_SANDBOX_DB_CONNECTION=$(taler-config -c "$CONF" -s "libeufin-sandbox" -o "DB_CONNECTION")

    # Create the default demobank.
    echo -n "Configuring sandbox "
    libeufin-sandbox config --currency "$CURRENCY" default &> libeufin-sandbox-config.log
    echo "DONE"
    echo -n "Launching sandbox "
    export LIBEUFIN_SANDBOX_ADMIN_PASSWORD="secret"
    libeufin-sandbox serve \
      --port "$SANDBOX_PORT" \
      > libeufin-sandbox-stdout.log \
      2> libeufin-sandbox-stderr.log &
    echo $! > libeufin-sandbox.pid
    echo "DONE"
    export LIBEUFIN_SANDBOX_URL="http://localhost:$SANDBOX_PORT/"
    OK="0"
    echo -n "Waiting for Sandbox ..."
    for n in $(seq 1 100); do
        echo -n "."
        sleep "$DEFAULT_SLEEP"
        wget --timeout=1 \
             --tries=3 \
             --waitretry=0 \
             -o /dev/null \
             -O /dev/null \
             "$LIBEUFIN_SANDBOX_URL" || continue
        OK="1"
        break
    done
    if [ "1" != "$OK" ]
    then
        exit_skip "Failed to launch services (sandbox)"
    fi
    echo "OK"
    echo -n "Register Sandbox users ..."
    register_sandbox_account fortytwo x "Forty Two"
    register_sandbox_account fortythree x "Forty Three"
    register_sandbox_account exchange x "Exchange Company"
    register_sandbox_account tor x "Tor Project"
    register_sandbox_account gnunet x "GNUnet"
    register_sandbox_account tutorial x "Tutorial"
    register_sandbox_account survey x "Survey"
    echo " DONE"

    echo -n "Fixing up exchange's PAYTO_URI in the config ..."
    export LIBEUFIN_SANDBOX_USERNAME="exchange"
    export LIBEUFIN_SANDBOX_PASSWORD="x"
    EXCHANGE_PAYTO=$(libeufin-cli sandbox demobank info --bank-account exchange | jq --raw-output '.paytoUri')
    taler-config -c "$CONF" -s exchange-account-1 -o "PAYTO_URI" -V "$EXCHANGE_PAYTO"
    echo " OK"

    echo -n "Setting this exchange as the bank's default ..."
    libeufin-sandbox default-exchange "$EXCHANGE_URL" "$EXCHANGE_PAYTO"
    echo " OK"

    # Prepare EBICS: create Ebics host and Exchange subscriber.
    # Shortly becoming admin to setup Ebics.
    export LIBEUFIN_SANDBOX_USERNAME="admin"
    export LIBEUFIN_SANDBOX_PASSWORD="secret"
    echo -n "Create EBICS host at Sandbox.."
    libeufin-cli sandbox \
       --sandbox-url "$LIBEUFIN_SANDBOX_URL" \
       ebicshost create --host-id talerebics &> libeufin-sandbox-ebicshost-create.log || true
    echo "OK"
    echo -n "Create exchange EBICS subscriber at Sandbox.."
    libeufin-cli sandbox \
       demobank new-ebicssubscriber --host-id talerebics \
       --user-id exchangeebics --partner-id talerpartner \
       --bank-account exchange &> libeufin-sandbox-ebicsscubscriber.log || true
    # that's a username _and_ a bank account name
    echo "OK"
    unset LIBEUFIN_SANDBOX_USERNAME
    unset LIBEUFIN_SANDBOX_PASSWORD
fi

if [ "1" = "$START_NEXUS" ]
then
    echo "Setting up Nexus ..."

    # Prepare Nexus, which is the side actually talking
    # to the exchange.
    export LIBEUFIN_NEXUS_DB_CONNECTION=$(taler-config -c "$CONF" -s "libeufin-nexus" -o "DB_CONNECTION")

    # For convenience, username and password are
    # identical to those used at the Sandbox.
    echo -n "Create exchange Nexus user ..."
    libeufin-nexus superuser exchange --password x
    echo "OK"
    libeufin-nexus serve --port "$NEXUS_PORT" \
      2> libeufin-nexus-stderr.log \
      > libeufin-nexus-stdout.log &
    echo $! > libeufin-nexus.pid
    export LIBEUFIN_NEXUS_URL="http://localhost:$NEXUS_PORT"
    echo -n "Waiting for Nexus ..."
    OK="0"
    for n in $(seq 1 100); do
        echo -n "."
        sleep "$DEFAULT_SLEEP"
        wget --timeout=1 \
             --tries=3 \
             --waitretry=0 \
             -o /dev/null \
             -O /dev/null \
             "$LIBEUFIN_NEXUS_URL" || continue
        OK="1"
        break
    done
    if [ "1" != "$OK" ]
    then
        exit_skip "Failed to launch services (bank)"
    fi
    echo " OK"

    export LIBEUFIN_NEXUS_USERNAME=exchange
    export LIBEUFIN_NEXUS_PASSWORD=x
    echo -n "Creating a EBICS connection at Nexus ..."
    libeufin-cli connections new-ebics-connection \
      --ebics-url "http://localhost:$SANDBOX_PORT/ebicsweb" \
      --host-id talerebics \
      --partner-id talerpartner \
      --ebics-user-id exchangeebics \
      talerconn
    echo "OK"

    echo -n "Setup EBICS keying ..."
    libeufin-cli connections connect talerconn > /dev/null
    echo "OK"
    echo -n "Download bank account name from Sandbox ..."
    libeufin-cli connections download-bank-accounts talerconn
    echo "OK"
    echo -n "Importing bank account info into Nexus ..."
    libeufin-cli connections import-bank-account \
      --offered-account-id exchange \
      --nexus-bank-account-id exchange-nexus \
      talerconn
    echo "OK"
    echo -n "Setup payments submission task..."
    # Tries every second.
    libeufin-cli accounts task-schedule \
      --task-type submit \
      --task-name exchange-payments \
      --task-cronspec "* * *" \
      exchange-nexus
    echo "OK"
    # Tries every second.  Ask C52
    echo -n "Setup history fetch task..."
    libeufin-cli accounts task-schedule \
      --task-type fetch \
      --task-name exchange-history \
      --task-cronspec "* * *" \
      --task-param-level report \
      --task-param-range-type latest \
      exchange-nexus
    echo "OK"
    # create Taler facade.
    echo -n "Create the Taler facade at Nexus..."
    libeufin-cli facades \
      new-taler-wire-gateway-facade \
      --currency TESTKUDOS --facade-name test-facade \
      talerconn exchange-nexus
    echo "OK"
    # Facade schema: http://localhost:$NEXUS_PORT/facades/test-facade/taler-wire-gateway/
    # FIXME: set the above URL automatically in the configuration?
fi

if [ "1" = "$START_FAKEBANK" ]
then
    echo "Setting up fakebank ..."
    taler-fakebank-run -c "$CONF" -L "$LOGLEVEL" 2> taler-fakebank-run.log &
fi


if [ "1" = "$START_EXCHANGE" ]
then
    echo -n "Starting exchange ..."

    EXCHANGE_PORT=$(taler-config -c "$CONF" -s EXCHANGE -o PORT)
    EXCHANGE_URL="http://localhost:${EXCHANGE_PORT}/"
    MASTER_PRIV_FILE=$(taler-config -f -c "${CONF}" -s "EXCHANGE-OFFLINE" -o "MASTER_PRIV_FILE")
    MASTER_PRIV_DIR=$(dirname "$MASTER_PRIV_FILE")
    mkdir -p "${MASTER_PRIV_DIR}"
    gnunet-ecc -g1 "$MASTER_PRIV_FILE" > /dev/null 2> /dev/null
    MASTER_PUB=$(gnunet-ecc -p "${MASTER_PRIV_FILE}")
    MPUB=$(taler-config -c "$CONF" -s exchange -o MASTER_PUBLIC_KEY)
    if [ "$MPUB" != "$MASTER_PUB" ]
    then
        echo -n " patching master_pub ($MASTER_PUB)..."
        taler-config -c "$CONF" -s exchange -o MASTER_PUBLIC_KEY -V "$MASTER_PUB"
    fi
    taler-exchange-dbinit -c "$CONF"
    $USE_VALGRIND taler-exchange-secmod-eddsa -c "$CONF" -L "$LOGLEVEL" 2> taler-exchange-secmod-eddsa.log &
    $USE_VALGRIND taler-exchange-secmod-rsa -c "$CONF" -L "$LOGLEVEL" 2> taler-exchange-secmod-rsa.log &
    $USE_VALGRIND taler-exchange-secmod-cs -c "$CONF" -L "$LOGLEVEL" 2> taler-exchange-secmod-cs.log &
    $USE_VALGRIND taler-exchange-httpd -c "$CONF" -L "$LOGLEVEL" 2> taler-exchange-httpd.log &
    EXCHANGE_HTTPD_PID=$!
    $USE_VALGRIND taler-exchange-wirewatch -c "$CONF" 2> taler-exchange-wirewatch.log &
    WIREWATCH_PID=$!
    $USE_VALGRIND taler-exchange-aggregator -c "$CONF" 2> taler-exchange-aggregator.log &
    AGGREGATOR_PID=$!
    $USE_VALGRIND taler-exchange-transfer -c "$CONF" 2> taler-exchange-transfer.log &
    TRANSFER_PID=$!
    echo " DONE"
fi

if [ "1" = "$START_MERCHANT" ]
then
    echo -n "Starting merchant ..."
    MEPUB=$(taler-config -c "$CONF" -s merchant-exchange-benchmark -o MASTER_KEY)
    MXPUB=${MASTER_PUB:-$(taler-config -c "$CONF" -s exchange -o MASTER_PUBLIC_KEY)}
    if [ "$MEPUB" != "$MXPUB" ]
    then
        echo -n " patching master_pub ($MXPUB)..."
        taler-config -c "$CONF" -s merchant-exchange-benchmark -o MASTER_KEY -V "$MXPUB"
    fi
    MERCHANT_PORT=$(taler-config -c "$CONF" -s MERCHANT -o PORT)
    MERCHANT_URL="http://localhost:${MERCHANT_PORT}/"
    taler-merchant-dbinit -c "$CONF"
    $USE_VALGRIND taler-merchant-httpd -c "$CONF" -L "$LOGLEVEL" 2> taler-merchant-httpd.log &
    MERCHANT_HTTPD_PID=$!
    $USE_VALGRIND taler-merchant-webhook -c "$CONF" -L "$LOGLEVEL" 2> taler-merchant-webhook.log &
    MERCHANT_WEBHOOK_PID=$!
    echo " DONE"
fi

if [ "1" = "$START_BACKUP" ]
then
    echo -n "Starting sync ..."
    SYNC_PORT=$(taler-config -c "$CONF" -s SYNC -o PORT)
    SYNC_URL="http://localhost:${SYNC_PORT}/"
    sync-dbinit -c "$CONF"
    $USE_VALGRIND sync-httpd -c "$CONF" -L "$LOGLEVEL" 2> sync-httpd.log &
    echo " DONE"
fi


if [ "1" = "$START_AUDITOR" ]
then
    echo -n "Starting auditor ..."
    AUDITOR_URL="http://localhost:8083/"
    AUDITOR_PRIV_FILE=$(taler-config -f -c "$CONF" -s AUDITOR -o AUDITOR_PRIV_FILE)
    AUDITOR_PRIV_DIR=$(dirname "$AUDITOR_PRIV_FILE")
    mkdir -p "$AUDITOR_PRIV_DIR"
    gnunet-ecc -g1 "$AUDITOR_PRIV_FILE" > /dev/null 2> /dev/null
    AUDITOR_PUB=$(gnunet-ecc -p "${AUDITOR_PRIV_FILE}")
    MAPUB=${MASTER_PUB:-$(taler-config -c "$CONF" -s exchange -o MASTER_PUBLIC_KEY)}
    taler-auditor-dbinit -c "$CONF"
    taler-auditor-exchange -c "$CONF" -m "$MAPUB" -u "$EXCHANGE_URL"
    $USE_VALGRIND taler-auditor-httpd -L "$LOGLEVEL" -c "$CONF" 2> taler-auditor-httpd.log &
    echo " DONE"
fi

if [[ "1" = "$START_NEXUS" || "1" = "$START_FAKEBANK" ]]
then
    echo -n "Waiting for the bank"
    # Wait for bank to be available (usually the slowest)
    OK="0"
    for n in $(seq 1 300)
    do
        echo -n "."
        sleep "$DEFAULT_SLEEP"
        # bank
        wget --tries=1 \
             --waitretry=0 \
             --timeout=1 \
             --user admin \
             --password secret \
             "http://localhost:8082/" \
             -o /dev/null \
             -O /dev/null >/dev/null || continue
        OK="1"
        break
    done
    if [ "1" != "$OK" ]
    then
        exit_skip "Failed to launch services (bank)"
    fi
    echo " OK"
fi

echo -n "Waiting for Taler services ..."
# Wait for all other taler services to be available
for n in $(seq 1 20)
do
    echo -n "."
    sleep "$DEFAULT_SLEEP"
    OK="0"
    if [ "1" = "$START_EXCHANGE" ]
    then
        wget \
            --tries=1 \
            --timeout=1 \
            "http://localhost:8081/config" \
            -o /dev/null \
            -O /dev/null >/dev/null || continue
    fi
    if [ "1" = "$START_MERCHANT" ]
    then
        wget \
            --tries=1 \
            --timeout=1 \
            "${MERCHANT_URL}config" \
            -o /dev/null \
            -O /dev/null >/dev/null || continue
    fi
    if [ "1" = "$START_BACKUP" ]
    then
        wget \
            --tries=1 \
            --timeout=1 \
            "${SYNC_URL}config" \
            -o /dev/null \
            -O /dev/null >/dev/null || continue
    fi
    if [ "1" = "$START_AUDITOR" ]
    then
        wget \
            --tries=1 \
            --timeout=1 \
            "${AUDITOR_URL}config" \
            -o /dev/null \
            -O /dev/null >/dev/null || continue
    fi
    OK="1"
    break
done
if [ 1 != "$OK" ]
then
    exit_skip "Failed to launch (some) Taler services"
fi
echo " OK"

if [ "1" = "$START_EXCHANGE" ]
then
    echo -n "Wait for exchange /management/keys to be ready "
    OK="0"
    LAST_RESPONSE=$(mktemp tmp-last-response.XXXXXXXX)
    for n in $(seq 1 50)
    do
        echo -n "."
        sleep "$DEFAULT_SLEEP"
        # exchange
        wget \
            --tries=3 \
            --waitretry=0 \
            --timeout=1 \
            "http://localhost:8081/management/keys"\
            -o /dev/null \
            -O "$LAST_RESPONSE" \
            >/dev/null || continue
        OK="1"
        break;
    done
    if [ "1" != "$OK" ]
    then
        cat "$LAST_RESPONSE"
        exit_skip "Failed to setup exchange keys, check secmod logs"
    fi
    rm "$LAST_RESPONSE"
    echo " OK"

    echo -n "Setting up exchange keys ..."
    taler-exchange-offline -c "$CONF" \
      download \
      sign \
      wire-fee now iban "$CURRENCY:0.01" "$CURRENCY:0.01" \
      global-fee now "$CURRENCY:0.01" "$CURRENCY:0.01" "$CURRENCY:0.01" 1h 1year 5 \
      upload &> taler-exchange-offline.log
    echo "OK"
    for ASEC in $(taler-config -c "$CONF" -S | grep -i "exchange-account-")
    do
        ENABLED=$(taler-config -c "$CONF" -s "$ASEC" -o "ENABLE_CREDIT")
        if [ "YES" = "$ENABLED" ]
        then
            echo -n "Configuring bank account $ASEC ..."
            EXCHANGE_PAYTO_URI=$(taler-config -c "$CONF" -s "$ASEC" -o "PAYTO_URI")
            taler-exchange-offline -c "$CONF" \
              enable-account "$EXCHANGE_PAYTO_URI" \
              upload &> "taler-exchange-offline-account-$ASEC.log"
            echo " OK"
        fi
    done
    if [ "1" = "$START_AUDITOR" ]
    then
        echo -n "Enabling auditor ..."
        taler-exchange-offline -c "$CONF" \
          enable-auditor $AUDITOR_PUB $AUDITOR_URL "$CURRENCY Auditor" \
          upload &> taler-exchange-offline-auditor.log
        echo "OK"
    fi

    echo -n "Checking /keys "
    OK="0"
    LAST_RESPONSE=$(mktemp tmp-last-response.XXXXXXXX)
    for n in $(seq 1 10)
    do
        echo -n "."
        sleep "$DEFAULT_SLEEP"
        wget \
            --tries=1 \
            --timeout=1 \
            "http://localhost:8081/keys" \
            -o /dev/null \
            -O "$LAST_RESPONSE" \
             >/dev/null || continue
        OK="1"
        break
    done
    if [ "1" != "$OK" ]
    then
        cat "$LAST_RESPONSE"
        exit_skip " Failed to setup keys"
    fi
    rm "$LAST_RESPONSE"
    echo " OK"
fi

if [ "1" = "$START_AUDITOR" ]
then
    echo -n "Setting up auditor signatures ..."
    timeout 15 taler-auditor-offline -c "$CONF" \
      download \
      sign \
      upload &> taler-auditor-offline.log
    echo " OK"
fi

# Signal caller that we are ready.
echo "<<READY>>"

# Wait until caller stops us.
read

exit 0
