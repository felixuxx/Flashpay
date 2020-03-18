#!/bin/bash
#
# This file is part of TALER
# Copyright (C) 2015-2020 Taler Systems SA
#
#  TALER is free software; you can redistribute it and/or modify it under the
#  terms of the GNU Affero General Public License as published by the Free Software
#  Foundation; either version 3, or (at your option) any later version.
#
#  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
#  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
#  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.
#
#  You should have received a copy of the GNU Affero General Public License along with
#  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
#
#
# This script uses 'curl' to POST various ill-formed requests to the
# taler-exchange-httpd.  Basically, the goal is to make sure that the
# HTTP server survives (and produces the 'correct' error code).
#
#
# Clear environment from variables that override config.
unset XDG_DATA_HOME
unset XDG_CONFIG_HOME
#


# Exit, with status code "skip" (no 'real' failure)
function exit_skip() {
    echo $1
    exit 77
}

# test required commands exist
echo -n "Testing for jq ..."
jq -h > /dev/null || exit_skip "jq required"
echo " OK"

CONF="-c test_taler_exchange_httpd.conf"

echo -n "Launching exchange ..."
PREFIX=
# Uncomment this line to run with valgrind...
# PREFIX="valgrind --leak-check=yes --track-fds=yes --error-exitcode=1 --log-file=valgrind.%p"

# Setup database
taler-exchange-dbinit $CONF &> /dev/null
# Setup keys.
taler-exchange-keyup $CONF &> /dev/null || exit 1
# Setup wire accounts.
taler-exchange-wire $CONF > /dev/null || exit 1
# Run Exchange HTTPD (in background)
$PREFIX taler-exchange-httpd $CONF 2> test-exchange.log &

# Give HTTP time to start

for n in `seq 1 100`
do
    echo -n "."
    sleep 0.1
    OK=1
    wget http://localhost:8081/ -o /dev/null -O /dev/null >/dev/null && break
    OK=0
done
if [ 1 != $OK ]
then
    echo "Failed to launch exchange"
    kill -TERM $!
    wait $!
    echo Process status: $?
    exit 77
fi
echo " DONE"

# Finally run test...
echo -n "Running tests ... "

# Revoke active denomination key
REVOKE_DENOM_HASH=`taler-exchange-keycheck $CONF -i EUR:1 | sort | head -n1 | awk '{print $2}'`
REVOKE_DENOM_TIME=`taler-exchange-keycheck $CONF -i EUR:1 | sort | head -n1 | awk '{print $1}'`

taler-exchange-keyup $CONF -r "$REVOKE_DENOM_HASH" -k 1024

# check revocation file exists
RDIR=`taler-config $CONF -f -s exchange -o REVOCATION_DIR`
if [ -f "$RDIR"/$REVOKE_DENOM_HASH.rev ]
then
    echo -n "REV-OK "
else
    echo -n "REV-FAIL ($RDIR) "
    RET=1
fi

# Check we now have two keys for that timestamp
CNT=`taler-exchange-keycheck $CONF -i EUR:1 | awk '{print $1}' | grep -- "$REVOKE_DENOM_TIME" | wc -l`

if [ x2 != x${CNT} ]
then
    echo -n "CNT-FAIL (${CNT}) "
    RET=1
else
    echo -n "CNT-OK "
fi

# Reload keys (and revocation data) at the exchange
kill -SIGUSR1 $!

# Give exchange chance to parse and reload keys
sleep 5

# Download (updated) keys
wget http://localhost:8081/keys -O keys.json -o /dev/null >/dev/null

RK=`jq -er .recoup[0].h_denom_pub < keys.json`
if [ x$RK != x$REVOKE_DENOM_HASH ]
then
    echo -n "KEYS-FAIL ($RK vs $REVOKE_DENOM_HASH)"
    RET=1
else
    echo -n "KEYS-OK"
fi

echo " DONE"
# $! is the last backgrounded process, hence the exchange
kill -TERM $!
wait $!
if [ 0 != $? ]
then
    RET=4
fi

echo "Final cleanup"
# Can't leave revocations around, would mess up next test run
rm -r "$RDIR"
# Also cleaning up live keys, as otherwise we have two for the revoked denomination type next time
KDIR=`taler-config $CONF -f -s exchange -o KEYDIR`
rm -r "$KDIR"
# Clean up our temporary file
rm keys.json

exit $RET
