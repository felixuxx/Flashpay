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
echo "Testing for jq"
jq -h > /dev/null || exit_skip "jq required"

echo -n "Launching exchange ..."
PREFIX=
# Uncomment this line to run with valgrind...
# PREFIX="valgrind --leak-check=yes --track-fds=yes --error-exitcode=1 --log-file=valgrind.%p"

# Setup database
taler-exchange-dbinit -c test_taler_exchange_httpd.conf &> /dev/null
# Setup keys.
taler-exchange-keyup -c test_taler_exchange_httpd.conf || exit 1
# Setup wire accounts.
taler-exchange-wire -c test_taler_exchange_httpd.conf > /dev/null || exit 1
# Run Exchange HTTPD (in background)
$PREFIX taler-exchange-httpd -c test_taler_exchange_httpd.conf 2> test-exchange.log &

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
echo -n "Running tests ..."

# Revoke active denomination key



echo " DONE"
# $! is the last backgrounded process, hence the exchange
kill -TERM $!
wait $!
# Return status code from exchange for this script
exit $?
