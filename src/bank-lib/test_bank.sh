#!/bin/bash

set -eu

# Exit, with status code "skip" (no 'real' failure)
function exit_skip() {
    echo $1
    exit 77
}

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

echo -n "Launching bank..."

taler-fakebank-run -c test_bank.conf -L DEBUG &> bank.log &

# Wait for bank to be available (usually the slowest)
for n in `seq 1 50`
do
    echo -n "."
    sleep 0.2
    OK=0
    # bank
    wget --tries=1 --timeout=1 http://localhost:8899/ -o /dev/null -O /dev/null >/dev/null || continue
    OK=1
    break
done

if [ 1 != $OK ]
then
    exit_skip "Failed to launch services (bank)"
fi

echo "OK"

echo -n "Making wire transfer to exchange ..."

taler-exchange-wire-gateway-client \
    -b http://localhost:8899/exchange/ \
    -S 0ZSX8SH0M30KHX8K3Y1DAMVGDQV82XEF9DG1HC4QMQ3QWYT4AF00 \
    -D payto://x-taler-bank/localhost:8899/user?receiver-name=user \
    -a TESTKUDOS:4 > /dev/null
echo " OK"

echo -n "Requesting exchange incoming transaction list ..."

./taler-exchange-wire-gateway-client -b http://localhost:8899/exchange/ -i | grep TESTKUDOS:4 > /dev/null

echo " OK"

echo -n "Making wire transfer from exchange..."

./taler-exchange-wire-gateway-client \
    -b http://localhost:8899/exchange/ \
    -S 0ZSX8SH0M30KHX8K3Y1DAMVGDQV82XEF9DG1HC4QMQ3QWYT4AF00 \
    -C payto://x-taler-bank/localhost:8899/merchant?receiver-name=merchant \
    -a TESTKUDOS:2 \
    -L DEBUG > /dev/null
echo " OK"


echo -n "Requesting exchange's outgoing transaction list..."

./taler-exchange-wire-gateway-client -b http://localhost:8899/exchange/ -o | grep TESTKUDOS:2 > /dev/null

echo " OK"

echo "All tests passed"

exit 0
