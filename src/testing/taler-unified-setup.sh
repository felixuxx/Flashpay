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
# Author: Christian Grothoff
#
# This script configures and launches various GNU Taler services.
# Which ones depend on command-line options. Use "-h" to find out.
# Prints "<<READY>>" on a separate line once all requested services
# are running. Close STDIN (or input 'NEWLINE') to stop all started
# services again.
#
# shellcheck disable=SC2317

set -eu

EXIT_STATUS=2

# Exit, with status code "skip" (no 'real' failure)
function exit_skip() {
    echo " SKIP: " "$@" >&2
    EXIT_STATUS=77
    exit "$EXIT_STATUS"
}

# Exit, with error message (hard failure)
function exit_fail() {
    echo " FAIL: " "$@" >&2
    EXIT_STATUS=1
    exit "$EXIT_STATUS"
}

# Cleanup to run whenever we exit
function cleanup()
{
    echo "Taler unified setup terminating!" >&2

    for n in $(jobs -p)
    do
        kill "$n" 2> /dev/null || true
    done
    wait
    rm -f libeufin-nexus.pid libeufin-sandbox.pid
    exit "$EXIT_STATUS"
}

# Install cleanup handler (except for kill -9)
trap cleanup EXIT

WAIT_FOR_SIGNAL=0
START_AUDITOR=0
START_BACKUP=0
START_EXCHANGE=0
START_FAKEBANK=0
START_CHALLENGER=0
START_AGGREGATOR=0
START_MERCHANT=0
START_NEXUS=0
START_BANK=0
START_TRANSFER=0
START_WIREWATCH=0
USE_ACCOUNT="exchange-account-1"
USE_VALGRIND=""
WIRE_DOMAIN="x-taler-bank"
CONF_ORIG="$HOME/.config/taler.conf"
LOGLEVEL="DEBUG"
DEFAULT_SLEEP="0.2"

# Parse command-line options
while getopts ':abc:d:efghkL:mnr:stu:vwW' OPTION; do
    case "$OPTION" in
        a)
            START_AUDITOR="1"
            ;;
        b)
            START_BANK="1"
            ;;
        c)
            CONF_ORIG="$OPTARG"
            ;;
        d)
            WIRE_DOMAIN="$OPTARG"
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
            echo '  -b           -- start bank'
            # shellcheck disable=SC2016
            echo '  -c $CONF     -- set configuration'
            # shellcheck disable=SC2016
            echo '  -d $METHOD   -- use wire method (default: x-taler-bank)'
            echo '  -e           -- start exchange'
            echo '  -f           -- start fakebank'
            echo '  -g           -- start aggregator'
            echo '  -h           -- print this help'
            # shellcheck disable=SC2016
            echo '  -L $LOGLEVEL -- set log level'
            echo '  -m           -- start merchant'
            echo '  -n           -- start nexus'
            # shellcheck disable=SC2016
            echo '  -r $MEX      -- which exchange to use at the merchant (optional)'
            echo '  -s           -- start backup/sync'
            echo '  -t           -- start transfer'
            # shellcheck disable=SC2016
            echo '  -u $SECTION  -- exchange account to use'
            echo '  -v           -- use valgrind'
            echo '  -w           -- start wirewatch'
            exit 0
            ;;
        g)
            START_AGGREGATOR="1"
            ;;
        k)
            START_CHALLENGER="1"
            ;;
        L)
            LOGLEVEL="$OPTARG"
            ;;
        m)
            START_MERCHANT="1"
            ;;
        n)
            START_NEXUS="1"
            ;;
        r)
            USE_MERCHANT_EXCHANGE="$OPTARG"
            ;;
        s)
            START_BACKUP="1"
            ;;
        t)
            START_TRANSFER="1"
            ;;
        u)
            USE_ACCOUNT="$OPTARG"
            ;;
        v)
            USE_VALGRIND="valgrind --leak-check=yes"
            DEFAULT_SLEEP="2"
            ;;
        w)
            START_WIREWATCH="1"
            ;;
        W)
            WAIT_FOR_SIGNAL="1"
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

if [ "1" = "$START_CHALLENGER" ]
then
    echo -n "Testing for Taler challenger"
    challenger-httpd -h > /dev/null || exit_skip " challenger-httpd required"
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

echo "Setting up for $CURRENCY at $EXCHANGE_URL"

register_bank_account() {
    wget \
        --http-user="$AUSER" \
        --http-password="$APASS" \
        --method=DELETE \
        -o /dev/null \
        -O /dev/null \
        -a wget-delete-account.log \
        "http://localhost:${BANK_PORT}/accounts/$1" \
        || true # deletion may fail, that's OK!
    if [ "$1" = "exchange" ] || [ "$1" = "Exchange" ]
    then
        IS_EXCHANGE="true"
    else
        IS_EXCHANGE="false"
    fi
    MAYBE_IBAN="${4:-}"
    if test -n "$MAYBE_IBAN";
    then
        # shellcheck disable=SC2001
        ENAME=$(echo "$3" | sed -e "s/ /+/g")
        # Note: this assumes that $3 has no spaces. Should probably escape in the future..
        PAYTO="payto://iban/SANDBOXX/${MAYBE_IBAN}?receiver-name=$ENAME"
        BODY='{"username":"'"$1"'","password":"'"$2"'","is_taler_exchange":'"$IS_EXCHANGE"',"name":"'"$3"'","internal_payto_uri":"'"$PAYTO"'"}'
    else
        BODY='{"username":"'"$1"'","password":"'"$2"'","is_taler_exchange":'"$IS_EXCHANGE"',"name":"'"$3"'"}'
    fi
    wget \
        --http-user="$AUSER" \
        --http-password="$APASS" \
        --method=POST \
        --header='Content-type: application/json' \
        --body-data="${BODY}" \
        -o /dev/null \
        -O /dev/null \
        -a wget-register-account.log \
        "http://localhost:${BANK_PORT}/accounts"
}

register_fakebank_account() {
    if [ "$1" = "exchange" ] || [ "$1" = "Exchange" ]
    then
        IS_EXCHANGE="true"
    else
        IS_EXCHANGE="false"
    fi
    BODY='{"username":"'"$1"'","password":"'"$2"'","name":"'"$1"'","is_taler_exchange":'"$IS_EXCHANGE"'}'
    wget \
        --post-data="$BODY" \
        --header='Content-type: application/json' \
        --tries=3 \
        --waitretry=1 \
        --timeout=30 \
        "http://localhost:$BANK_PORT/accounts" \
        -a wget-register-account.log \
        -o /dev/null \
        -O /dev/null \
        >/dev/null
}


if [[ "1" = "$START_BANK" ]]
then
    BANK_PORT=$(taler-config -c "$CONF" -s "libeufin-bank" -o "PORT")
    BANK_URL="http://localhost:${BANK_PORT}/"
fi

if [[ "1" = "$START_FAKEBANK" ]]
then
    BANK_PORT=$(taler-config -c "$CONF" -s "BANK" -o "HTTP_PORT")
    BANK_URL="http://localhost:${BANK_PORT}/"
fi

if [ "1" = "$START_BANK" ]
then
    echo -n "Setting up bank database ... "
    libeufin-bank dbinit \
        -r \
        -c "$CONF" \
        &> libeufin-bank-reset.log
    echo "DONE"
    echo -n "Launching bank ... "
    libeufin-bank serve \
      -c "$CONF" \
      > libeufin-bank-stdout.log \
      2> libeufin-bank-stderr.log &
    echo $! > libeufin-bank.pid
    echo "DONE"
    echo -n "Waiting for Bank ..."
    OK="0"
    for n in $(seq 1 100); do
        echo -n "."
        sleep "$DEFAULT_SLEEP"
        wget --timeout=1 \
             --tries=3 \
             --waitretry=0 \
             -a wget-bank-check.log \
             -o /dev/null \
             -O /dev/null \
             "$BANK_URL/config" || continue
        OK="1"
        break
    done
    if [ "1" != "$OK" ]
    then
        exit_skip "Failed to launch services (bank)"
    fi
    echo "OK"
    echo -n "Set admin password..."
    AUSER="admin"
    APASS="secret"
    libeufin-bank \
      passwd \
      -c "$CONF" \
      "$AUSER" "$APASS" \
      &> libeufin-bank-passwd.log
    libeufin-bank \
      edit-account \
      -c "$CONF" \
      --debit_threshold="$CURRENCY:1000000" \
      "$AUSER" \
      &> libeufin-bank-debit-threshold.log
    echo " OK"
fi

if [ "1" = "$START_NEXUS" ]
then
    echo "Nexus currently not supported ..."
fi

if [ "1" = "$START_FAKEBANK" ]
then
    echo -n "Setting up fakebank ..."
    $USE_VALGRIND taler-fakebank-run \
                  -c "$CONF" \
                  -L "$LOGLEVEL" \
                  -n 4 \
                  2> taler-fakebank-run.log &
    echo " OK"
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
             -a wget-bank-check.log \
             -o /dev/null \
             -O /dev/null \
             "http://localhost:${BANK_PORT}/" || continue
        OK="1"
        break
    done
    if [ "1" != "$OK" ]
    then
        exit_skip "Failed to launch services (bank)"
    fi
    echo " OK"
fi

if [ "1" = "$START_FAKEBANK" ]
then
    echo -n "Register Fakebank users ..."
    register_fakebank_account fortytwo x
    register_fakebank_account fortythree x
    register_fakebank_account exchange x
    register_fakebank_account tor x
    register_fakebank_account gnunet x
    register_fakebank_account tutorial x
    register_fakebank_account survey x
    echo " DONE"
fi

if [ "1" = "$START_BANK" ]
then
    echo -n "Register bank users ..."
    # The specified IBAN and name must match the ones hard-coded into
    # the C helper for the add-incoming call.  Without this value,
    # libeufin-bank  won't find the target account to debit along a /add-incoming
    # call.
    register_bank_account fortytwo x "User42" FR7630006000011234567890189
    register_bank_account fortythree x "Forty Three"
    register_bank_account exchange x "Exchange Company" DE989651
    register_bank_account tor x "Tor Project"
    register_bank_account gnunet x "GNUnet"
    register_bank_account tutorial x "Tutorial"
    register_bank_account survey x "Survey"
    echo " DONE"
fi

if [ "1" = "$START_EXCHANGE" ]
then
    echo -n "Starting exchange ..."
    EXCHANGE_PORT=$(taler-config -c "$CONF" -s EXCHANGE -o PORT)
    SERVE=$(taler-config -c "$CONF" -s EXCHANGE -o SERVE)
    if [ "${SERVE}" = "unix" ]
    then
        EXCHANGE_URL=$(taler-config -c "$CONF" -s EXCHANGE -o BASE_URL)
    else
        EXCHANGE_URL="http://localhost:${EXCHANGE_PORT}/"
    fi
    MASTER_PRIV_FILE=$(taler-config -f -c "${CONF}" -s "EXCHANGE-OFFLINE" -o "MASTER_PRIV_FILE")
    MASTER_PRIV_DIR=$(dirname "$MASTER_PRIV_FILE")
    mkdir -p "${MASTER_PRIV_DIR}"
    if [ ! -e "$MASTER_PRIV_FILE" ]
    then
        gnunet-ecc -g1 "$MASTER_PRIV_FILE" > /dev/null 2> /dev/null
        echo -n "."
    fi
    MASTER_PUB=$(gnunet-ecc -p "${MASTER_PRIV_FILE}")
    MPUB=$(taler-config -c "$CONF" -s exchange -o MASTER_PUBLIC_KEY)
    if [ "$MPUB" != "$MASTER_PUB" ]
    then
        echo -n " patching master_pub ($MASTER_PUB)..."
        taler-config -c "$CONF" -s exchange -o MASTER_PUBLIC_KEY -V "$MASTER_PUB"
    fi
    taler-exchange-dbinit -c "$CONF" --reset
    $USE_VALGRIND taler-exchange-secmod-eddsa \
                  -c "$CONF" \
                  -L "$LOGLEVEL" \
                  2> taler-exchange-secmod-eddsa.log &
    $USE_VALGRIND taler-exchange-secmod-rsa \
                  -c "$CONF" \
                  -L "$LOGLEVEL" \
                  2> taler-exchange-secmod-rsa.log &
    $USE_VALGRIND taler-exchange-secmod-cs \
                  -c "$CONF" \
                  -L "$LOGLEVEL" \
                  2> taler-exchange-secmod-cs.log &
    $USE_VALGRIND taler-exchange-httpd \
                  -c "$CONF" \
                  -L "$LOGLEVEL" 2> taler-exchange-httpd.log &
    echo " DONE"
fi

if [ "1" = "$START_WIREWATCH" ]
then
    echo -n "Starting wirewatch ..."
    $USE_VALGRIND taler-exchange-wirewatch \
                  --account="$USE_ACCOUNT" \
                  -c "$CONF" \
                  -L "$LOGLEVEL" \
                  --longpoll-timeout="1 s" \
                  2> taler-exchange-wirewatch.log &
    echo " DONE"
fi

if [ "1" = "$START_AGGREGATOR" ]
then
    echo -n "Starting aggregator ..."
    $USE_VALGRIND taler-exchange-aggregator \
                  -c "$CONF" \
                  -L "$LOGLEVEL" \
                  2> taler-exchange-aggregator.log &
    echo " DONE"
fi

if [ "1" = "$START_TRANSFER" ]
then
    echo -n "Starting transfer ..."
    $USE_VALGRIND taler-exchange-transfer \
                  -c "$CONF" \
                  -L "$LOGLEVEL" \
                  2> taler-exchange-transfer.log &
    echo " DONE"
fi

if [ "1" = "$START_MERCHANT" ]
then
    echo -n "Starting merchant ..."
    if [ -n "${USE_MERCHANT_EXCHANGE+x}" ]
    then
        MEPUB=$(taler-config -c "$CONF" -s "${USE_MERCHANT_EXCHANGE}" -o MASTER_KEY)
        MXPUB=${MASTER_PUB:-$(taler-config -c "$CONF" -s exchange -o MASTER_PUBLIC_KEY)}
        if [ "$MEPUB" != "$MXPUB" ]
        then
            echo -n " patching master_pub ($MXPUB)..."
            taler-config -c "$CONF" -s "${USE_MERCHANT_EXCHANGE}" -o MASTER_KEY -V "$MXPUB"
        fi
    fi
    MERCHANT_TYPE=$(taler-config -c "$CONF" -s MERCHANT -o SERVE)
    if [ "unix" = "$MERCHANT_TYPE" ]
    then
        MERCHANT_URL="$(taler-config -c "$CONF" -s MERCHANT -o BASE_URL)"
    else
        MERCHANT_PORT="$(taler-config -c "$CONF" -s MERCHANT -o PORT)"
        MERCHANT_URL="http://localhost:${MERCHANT_PORT}/"
    fi
    taler-merchant-dbinit \
        -c "$CONF" \
        --reset &> taler-merchant-dbinit.log
    $USE_VALGRIND taler-merchant-httpd \
                  -c "$CONF" \
                  -L "$LOGLEVEL" 2> taler-merchant-httpd.log &
    $USE_VALGRIND taler-merchant-webhook \
                  -c "$CONF" \
                  -L "$LOGLEVEL" 2> taler-merchant-webhook.log &
    echo " DONE"
fi

if [ "1" = "$START_BACKUP" ]
then
    echo -n "Starting sync ..."
    SYNC_PORT=$(taler-config -c "$CONF" -s SYNC -o PORT)
    SERVE=$(taler-config -c "$CONF" -s SYNC -o SERVE)
    if [ "${SERVE}" = "unix" ]
    then
        SYNC_URL=$(taler-config -c "$CONF" -s SYNC -o BASE_URL)
    else
        SYNC_URL="http://localhost:${SYNC_PORT}/"
    fi
    sync-dbinit -c "$CONF" --reset
    $USE_VALGRIND sync-httpd \
                  -c "$CONF" \
                  -L "$LOGLEVEL" \
                  2> sync-httpd.log &
    echo " DONE"
fi

if [ "1" = "$START_CHALLENGER" ]
then
    echo -n "Starting challenger ..."
    CHALLENGER_PORT=$(challenger-config -c "$CONF" -s CHALLENGER -o PORT)
    SERVE=$(taler-config -c "$CONF" -s CHALLENGER -o SERVE)
    if [ "${SERVE}" = "unix" ]
    then
        CHALLENGER_URL=$(taler-config -c "$CONF" -s CHALLENGER -o BASE_URL)
    else
        CHALLENGER_URL="http://localhost:${CHALLENGER_PORT}/"
    fi
    challenger-dbinit \
        -c "$CONF" \
        --reset
    $USE_VALGRIND challenger-httpd \
                  -c "$CONF" \
                  -L "$LOGLEVEL" \
                  2> challenger-httpd.log &
    echo " DONE"
    for SECTION in $(taler-config -c "$CONF" -S | grep kyc-provider)
    do
        LOGIC=$(taler-config -c "$CONF" -s "$SECTION" -o "LOGIC")
        if [ "${LOGIC}" = "oauth2" ]
        then
            INFO=$(taler-config -c "$CONF" -s "$SECTION" -o "KYC_OAUTH2_INFO_URL")
            if [ "${CHALLENGER_URL}info" = "$INFO" ]
            then
                echo -n "Enabling Challenger client for $SECTION"
                CLIENT_SECRET=$(taler-config -c "$CONF" -s "$SECTION" -o "KYC_OAUTH2_CLIENT_SECRET")
                RFC_8959_PREFIX="secret-token:"
                if ! echo "${CLIENT_SECRET}" | grep ^${RFC_8959_PREFIX} > /dev/null
                then
                    exit_fail "Client secret does not begin with '${RFC_8959_PREFIX}'"
                fi
                REDIRECT_URI="${EXCHANGE_URL}kyc-proof/kyc-provider-example-challeger"
                CLIENT_ID=$(challenger-admin --add="${CLIENT_SECRET}" --quiet "${REDIRECT_URI}")
                taler-config -c "$CONF" -s "$SECTION" -o KYC_OAUTH2_CLIENT_ID -V "$CLIENT_ID"
                echo " DONE"
            fi
        fi
    done
fi


if [ "1" = "$START_AUDITOR" ]
then
    echo -n "Starting auditor ..."
    AUDITOR_URL=$(taler-config -c "$CONF" -s AUDITOR -o BASE_URL)
    AUDITOR_PRIV_FILE=$(taler-config -f -c "$CONF" -s AUDITOR -o AUDITOR_PRIV_FILE)
    AUDITOR_PRIV_DIR=$(dirname "$AUDITOR_PRIV_FILE")
    mkdir -p "$AUDITOR_PRIV_DIR"
    if [ ! -e "$AUDITOR_PRIV_FILE" ]
    then
        gnunet-ecc -g1 "$AUDITOR_PRIV_FILE" > /dev/null 2> /dev/null
        echo -n "."
    fi
    AUDITOR_PUB=$(gnunet-ecc -p "${AUDITOR_PRIV_FILE}")
    MAPUB=${MASTER_PUB:-$(taler-config -c "$CONF" -s exchange -o MASTER_PUBLIC_KEY)}
    taler-auditor-dbinit \
        -c "$CONF" \
        --reset
    taler-auditor-exchange \
        -c "$CONF" \
        -m "$MAPUB" \
        -u "$EXCHANGE_URL"
    $USE_VALGRIND taler-auditor-httpd \
                  -L "$LOGLEVEL" \
                  -c "$CONF" 2> taler-auditor-httpd.log &
    echo " DONE"
fi


echo -n "Waiting for Taler services ..."
# Wait for all other taler services to be available
E_DONE=0
M_DONE=0
S_DONE=0
K_DONE=0
A_DONE=0
for n in $(seq 1 20)
do
    sleep "$DEFAULT_SLEEP"
    OK="0"
    if [ "0" = "$E_DONE" ] && [ "1" = "$START_EXCHANGE" ]
    then
        echo -n "E"
        wget \
            --tries=1 \
            --timeout=1 \
            "${EXCHANGE_URL}config" \
            -o /dev/null \
            -O /dev/null >/dev/null || continue
        E_DONE=1
    fi
    if [ "0" = "$M_DONE" ] && [ "1" = "$START_MERCHANT" ]
    then
        echo -n "M"
        wget \
            --tries=1 \
            --timeout=1 \
            "${MERCHANT_URL}config" \
            -o /dev/null \
            -O /dev/null >/dev/null || continue
        M_DONE=1
    fi
    if [ "0" = "$S_DONE" ] && [ "1" = "$START_BACKUP" ]
    then
        echo -n "S"
        wget \
            --tries=1 \
            --timeout=1 \
            "${SYNC_URL}config" \
            -o /dev/null \
            -O /dev/null >/dev/null || continue
        S_DONE=1
    fi
    if [ "0" = "$K_DONE" ] && [ "1" = "$START_CHALLENGER" ]
    then
        echo -n "K"
        wget \
            --tries=1 \
            --timeout=1 \
            "${CHALLENGER_URL}config" \
            -o /dev/null \
            -O /dev/null >/dev/null || continue
        K_DONE=1
    fi
    if [ "0" = "$A_DONE" ] && [ "1" = "$START_AUDITOR" ]
    then
        echo -n "A"
        wget \
            --tries=1 \
            --timeout=1 \
            "${AUDITOR_URL}config" \
            -o /dev/null \
            -O /dev/null >/dev/null || continue
        A_DONE=1
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
    for n in $(seq 1 10)
    do
        echo -n "."
        sleep "$DEFAULT_SLEEP"
        # exchange
        wget \
            --tries=3 \
            --waitretry=0 \
            --timeout=30 \
            "${EXCHANGE_URL}management/keys"\
            -o /dev/null \
            -O "$LAST_RESPONSE" \
            >/dev/null || continue
        OK="1"
        break;
    done
    if [ "1" != "$OK" ]
    then
        cat "$LAST_RESPONSE"
        exit_fail "Failed to setup exchange keys, check secmod logs"
    fi
    rm "$LAST_RESPONSE"
    echo " OK"

    echo -n "Setting up exchange keys ..."
    taler-exchange-offline -c "$CONF" \
      download \
      sign \
      wire-fee now "$WIRE_DOMAIN" "$CURRENCY:0.01" "$CURRENCY:0.01" \
      global-fee now "$CURRENCY:0.01" "$CURRENCY:0.01" "$CURRENCY:0.01" 1h 1year 5 \
      upload &> taler-exchange-offline.log
    echo "OK"
    ENABLED=$(taler-config -c "$CONF" -s "$USE_ACCOUNT" -o "ENABLE_CREDIT")
    if [ "YES" = "$ENABLED" ]
    then
        echo -n "Configuring bank account $USE_ACCOUNT ..."
        EXCHANGE_PAYTO_URI=$(taler-config -c "$CONF" -s "$USE_ACCOUNT" -o "PAYTO_URI")
        taler-exchange-offline -c "$CONF" \
          enable-account "$EXCHANGE_PAYTO_URI" \
          upload &> "taler-exchange-offline-account.log"
        echo " OK"
    else
        echo "WARNING: Account ${USE_ACCOUNT} not enabled (set to: '$ENABLED')"
    fi
    if [ "1" = "$START_AUDITOR" ]
    then
        echo -n "Enabling auditor ..."
        taler-exchange-offline -c "$CONF" \
          enable-auditor "$AUDITOR_PUB" "$AUDITOR_URL" "$CURRENCY Auditor" \
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
            --timeout=5 \
            "${EXCHANGE_URL}keys" \
            -a wget-keys-check.log \
            -o /dev/null \
            -O "$LAST_RESPONSE" \
            >/dev/null || continue
        OK="1"
        break
    done
    if [ "1" != "$OK" ]
    then
        cat "$LAST_RESPONSE"
        exit_fail " Failed to fetch ${EXCHANGE_URL}keys"
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

if [ "1" = "$WAIT_FOR_SIGNAL" ]
then
    while true
    do
        sleep 0.1
    done
else
    # Wait until caller stops us.
    # shellcheck disable=SC2162
    read
fi

echo "Taler unified setup terminating!" >&2
EXIT_STATUS=0
exit "$EXIT_STATUS"
