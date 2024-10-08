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
        > >(tee taler-unified-setup.log >&3) &
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
    echo "get_payto_uri currently not implemented"
    exit 1
#    libeufin-cli sandbox demobank info --bank-account "$1" | jq --raw-output '.paytoUri'
}

# Stop libeufin-bank (if running)
function stop_libeufin()
{
    if [ -f "${MY_TMP_DIR:-/}/libeufin-bank.pid" ]
    then
        PID=$(cat "${MY_TMP_DIR}/libeufin-bank.pid" 2> /dev/null)
        echo -n "Stopping libeufin $PID... "
        rm "${MY_TMP_DIR}/libeufin-bank.pid"
        kill "$PID" 2> /dev/null || true
        wait "$PID" || true
        echo "DONE"
    fi
}


function launch_libeufin () {
  libeufin-bank serve \
    -c "$CONF" \
    -L "INFO" \
    > "${MY_TMP_DIR}/libeufin-bank-stdout.log" \
    2> "${MY_TMP_DIR}/libeufin-bank-stderr.log" &
  echo $! > "${MY_TMP_DIR}/libeufin-bank.pid"
}
