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
echo -n "Launching exchange ..."
PREFIX=
# Uncomment this line to run with valgrind...
# PREFIX="valgrind --leak-check=yes --track-fds=yes --error-exitcode=1 --log-file=valgrind.%p"

# Setup database
taler-exchange-dbinit -c test_taler_exchange_httpd.conf &> /dev/null
# Run Exchange HTTPD (in background)
$PREFIX taler-exchange-httpd -c test_taler_exchange_httpd.conf 2> test-exchange.log &

# Give HTTP time to start

for n in `seq 1 100`
do
    echo -n "."
    sleep 0.1
    OK=1
    wget http://localhost:8081/seed -o /dev/null -O /dev/null >/dev/null && break
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
# We read the JSON snippets to POST from test_taler_exchange_httpd.post
cat test_taler_exchange_httpd.post | grep -v ^\# | awk '{ print "curl -d \47"  $2 "\47 http://localhost:8081" $1 }' | bash &> /dev/null
echo -n .
# We read the JSON snippets to GET from test_taler_exchange_httpd.get
cat test_taler_exchange_httpd.get | grep -v ^\# | awk '{ print "curl http://localhost:8081" $1 }' | bash &> /dev/null
echo -n .
# Also try them with various headers: Language
cat test_taler_exchange_httpd.get | grep -v ^\# | awk '{ print "curl -H \"Accept-Language: fr,en;q=0.4,de\" http://localhost:8081" $1 }' | bash &> /dev/null
echo -n .
# Also try them with various headers: Accept encoding (wildcard #1)
cat test_taler_exchange_httpd.get | grep -v ^\# | awk '{ print "curl -H \"Accept: text/*\" http://localhost:8081" $1 }' | bash &> /dev/null
echo -n .
# Also try them with various headers: Accept encoding (wildcard #2)
cat test_taler_exchange_httpd.get | grep -v ^\# | awk '{ print "curl -H \"Accept: */plain\" http://localhost:8081" $1 }' | bash &> /dev/null

echo " DONE"
# $! is the last backgrounded process, hence the exchange
kill -TERM $!
wait $!
# Return status code from exchange for this script
exit $?
