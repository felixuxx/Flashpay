#!/bin/bash
# This file is in the public domain

# Script to be inlined into the main test scripts. Defines function 'setup()'
# which wraps around 'taler-unified-setup.sh' to launch GNU Taler services.
# Call setup() with the arguments to pass to 'taler-unified-setup'. setup()
# will then launch GNU Taler, wait for the process to be complete before
# returning. The script will also install an exit handler to ensure the GNU
# Taler processes are stopped when the shell exits.

set -eu

# Cleanup to run whenever we exit
function exit_cleanup()
{
    if [ ! -z ${SETUP_PID+x} ]
    then
        echo "Killing taler-unified-setup ($SETUP_PID)" >&2
        kill -TERM "$SETUP_PID" 2> /dev/null || true
        wait "$SETUP_PID" 2> /dev/null || true
    fi
}

# Install cleanup handler (except for kill -9)
trap exit_cleanup EXIT

function setup()
{
    echo "Starting test system ..." >&2
    # Create a named pipe in a temp directory we own.
    FIFO_DIR=$(mktemp -d fifo-XXXXXX)
    FIFO_OUT=$(echo "$FIFO_DIR/out")
    mkfifo "$FIFO_OUT"
    # Open pipe as FD 3 (RW) and FD 4 (RO)
    exec 3<> "$FIFO_OUT" 4< "$FIFO_OUT"
    rm -rf "$FIFO_DIR"
    # We require '-W' for our termination logic to work.
    taler-unified-setup.sh -W "$@" \
        | tee taler-unified-setup.log \
        >&3 &
    SETUP_PID=$!
    # Close FD3
    exec 3>&-
    sed -u '/<<READY>>/ q' <&4
    # Close FD4
    exec 4>&-
    echo "Test system ready" >&2
}

# Exit, with status code "skip" (no 'real' failure)
function exit_fail() {
    echo "$@" >&2
    exit 1
}

# Exit, with status code "skip" (no 'real' failure)
function exit_skip() {
    echo "SKIPPING: $1"
    exit 77
}

function get_payto_uri() {
    export LIBEUFIN_SANDBOX_USERNAME="$1"
    export LIBEUFIN_SANDBOX_PASSWORD="$2"
    export LIBEUFIN_SANDBOX_URL="http://localhost:18082"
    echo "broken"
    exit 1
#    libeufin-cli sandbox demobank info --bank-account "$1" | jq --raw-output '.paytoUri'
}

function get_bankaccount_transactions() {
    export LIBEUFIN_SANDBOX_USERNAME=$1
    export LIBEUFIN_SANDBOX_PASSWORD=$2
    export LIBEUFIN_SANDBOX_URL="http://localhost:18082"
    echo "broken"
    exit 1
#    libeufin-cli sandbox demobank list-transactions --bank-account $1
}


# Stop libeufin sandbox and nexus (if running)
function stop_libeufin()
{
    echo -n "Stopping libeufin... "
    if [ -f "${MY_TMP_DIR:-/}/libeufin-sandbox.pid" ]
    then
        PID=$(cat "${MY_TMP_DIR}/libeufin-sandbox.pid" 2> /dev/null)
        echo "Killing libeufin sandbox $PID"
        rm "${MY_TMP_DIR}/libeufin-sandbox.pid"
        kill "$PID" 2> /dev/null || true
        wait "$PID" || true
    fi
    if [ -f "${MY_TMP_DIR:-/}/libeufin-nexus.pid" ]
    then
        PID=$(cat "${MY_TMP_DIR}/libeufin-nexus.pid" 2> /dev/null)
        echo "Killing libeufin nexus $PID"
        rm "${MY_TMP_DIR}/libeufin-nexus.pid"
        kill "$PID" 2> /dev/null || true
        wait "$PID" || true
    fi
    echo "DONE"
}


function launch_libeufin () {
# shellcheck disable=SC2016
    export LIBEUFIN_SANDBOX_DB_CONNECTION="postgresql:///${DB}"
    libeufin-sandbox serve \
                     --no-auth \
                     --port 18082 \
                     > "${MY_TMP_DIR}/libeufin-sandbox-stdout.log" \
                     2> "${MY_TMP_DIR}/libeufin-sandbox-stderr.log" &
    echo $! > "${MY_TMP_DIR}/libeufin-sandbox.pid"
# shellcheck disable=SC2016
    export LIBEUFIN_NEXUS_DB_CONNECTION="postgresql:///${DB}"
    libeufin-nexus serve \
                   --port 8082 \
                   2> "${MY_TMP_DIR}/libeufin-nexus-stderr.log" \
                   > "${MY_TMP_DIR}/libeufin-nexus-stdout.log" &
    echo $! > "${MY_TMP_DIR}/libeufin-nexus.pid"
}



# Downloads new transactions from the bank.
function nexus_fetch_transactions () {
    export LIBEUFIN_NEXUS_USERNAME="exchange"
    export LIBEUFIN_NEXUS_PASSWORD="x"
    export LIBEUFIN_NEXUS_URL="http://localhost:8082/"
    echo "broken"
    exit 1
#    libeufin-cli accounts \
#                 fetch-transactions \
#                 --range-type since-last \
#                 --level report \
#                 exchange-nexus > /dev/null
    unset LIBEUFIN_NEXUS_USERNAME
    unset LIBEUFIN_NEXUS_PASSWORD
    unset LIBEUFIN_NEXUS_URL
}


# Instruct Nexus to all the prepared payments (= those
# POSTed to /transfer by the exchange).
function nexus_submit_to_sandbox () {
    export LIBEUFIN_NEXUS_USERNAME="exchange"
    export LIBEUFIN_NEXUS_PASSWORD="x"
    export LIBEUFIN_NEXUS_URL="http://localhost:8082/"
    echo "broken"
    exit 1
#    libeufin-cli accounts \
#                 submit-payments\
#                 exchange-nexus
    unset LIBEUFIN_NEXUS_USERNAME
    unset LIBEUFIN_NEXUS_PASSWORD
    unset LIBEUFIN_NEXUS_URL
}
