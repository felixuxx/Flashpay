#!/bin/bash
#
# This file is part of TALER
# Copyright (C) 2015, 2020 Taler Systems SA
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
# We read the JSON snippets from afl-tests/
#
# The afl-tests are generated as follows:
# 1) Capture all TCP traffic from 'test-auditor.sh'
# 2) Use 'tcpflow -e http -r $PCAP -o $OUTPUT' to get the HTTP streams
# 3) Remove HTTP streams unrelated to the exchange as well as the replies
# 4) Compile the exchange with AFL instrumentation
# 5) Run afl-fuzz -i $OUTPUT/ -o afl-tests/ ~/bin/taler-exchange-httpd \
#     -c test_taler_exchange_httpd.conf -t 1 -f @@

set -eu

PREFIX=
# Uncomment this line to run with valgrind...
# PREFIX="valgrind --leak-check=yes --log-file=valgrind.%p"
# Setup keys.
taler-exchange-keyup -c test_taler_exchange_httpd.conf
# Setup database (just to be sure)
taler-exchange-dbinit -c test_taler_exchange_httpd.conf &> /dev/null
# Only log hard errors, we expect lots of warnings...
export GNUNET_FORCE_LOG="taler-exchange-httpd;;;;ERROR/libmicrohttpd;;;;ERROR/util;;;;ERROR/"
# Run test...
for n in afl-tests/*
do
  echo -n "Test $n "
  $PREFIX taler-exchange-httpd -c test_taler_exchange_httpd.conf -t 1 -f $n -C > /dev/null || { echo "FAIL!"; }
  echo "OK"
done
exit 0
