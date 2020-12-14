#!/bin/bash
#
# This file is part of TALER
# Copyright (C) 2020 Taler Systems SA
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
# This script launches an exchange (binding to a UNIX domain socket) and then
# restarts it in various ways (SIGHUP to re-read configuration, and SIGUSR1 to
# re-spawn a new binary).  Basically, the goal is to make sure that the HTTP
# server survives these less common operations.
#
#
set -eu

# Exit, with status code "skip" (no 'real' failure)
function exit_skip() {
    echo $1
    exit 77
}

# Exit, with error message (hard failure)
function exit_fail() {
    echo $1
    kill `jobs -p` >/dev/null 2>/dev/null || true
    wait
    exit 1
}

echo -n "Testing for curl"
curl --version >/dev/null </dev/null || exit_skip " MISSING"
echo " FOUND"


# Clear environment from variables that override config.
unset XDG_DATA_HOME
unset XDG_CONFIG_HOME
#
echo -n "Launching exchange ..."
PREFIX=
# Uncomment this line to run with valgrind...
# PREFIX="valgrind --trace-children=yes --leak-check=yes --track-fds=yes --error-exitcode=1 --log-file=valgrind.%p"

# Setup database
taler-exchange-dbinit -c test_taler_exchange_unix.conf &> /dev/null
# Run Exchange HTTPD (in background)
$PREFIX taler-exchange-httpd -c test_taler_exchange_unix.conf 2> test-exchange.log &

# Where should we be bound to?
UNIXPATH=`taler-config -s exchange -f -o UNIXPATH`

# Give HTTP time to start

for n in `seq 1 100`
do
    echo -n "."
    sleep 0.1
    OK=1
    curl --unix-socket "${UNIXPATH}" "http://ignored/" >/dev/null 2> /dev/null && break
    OK=0
done
if [ 1 != $OK ]
then
    exit_fail "Failed to launch exchange"
fi
echo " DONE"

# Finally run test...
echo -n "Restarting program ..."
kill -SIGHUP $!
sleep 1
curl --unix-socket "${UNIXPATH}" "http://ignored/" >/dev/null 2> /dev/null || exit_fail "SIGHUP killed HTTP service"
echo " DONE"

echo -n "Waiting for parent to die ..."
wait $!
echo " DONE"

echo -n "Testing child still alive ..."
curl --unix-socket "${UNIXPATH}" "http://ignored/" >/dev/null 2> /dev/null || exit_fail "SIGHUP killed HTTP service"
echo " DONE"


echo -n "Killing grandchild ..."
CPID=`ps x | grep taler-exchange-httpd | grep -v grep | awk '{print $1}'`
kill -TERM $CPID
while true
do
    ps x | grep -v grep | grep taler-exchange-httpd > /dev/null || break
    sleep 0.1
done
echo " DONE"

# Return status code from exchange for this script
exit 0
