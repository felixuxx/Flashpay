#!/bin/bash
#
# This file is part of TALER
# Copyright (C) 2015 GNUnet e.V.
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
# taler-mint-httpd.  Basically, the goal is to make sure that the
# HTTP server survives (and produces the 'correct' error code).
#
# We read the JSON snippets from afl-tests/
#
PREFIX=
# Uncomment this line to run with valgrind...
PREFIX="valgrind --leak-check=yes --log-file=valgrind.%p"
# Setup keys.
taler-mint-keyup -d test-mint-home -m test-mint-home/master.priv
# Setup database (just to be sure)
taler-mint-dbinit -d test-mint-home &> /dev/null || true
# Only log hard errors, we expect lots of warnings...
export GNUNET_FORCE_LOG="taler-mint-httpd;;;;ERROR/libmicrohttpd;;;;ERROR/util;;;;ERROR/"
# Run test...
for n in afl-tests/*
do
  echo -n "Test $n "
  $PREFIX taler-mint-httpd -d test-mint-home/ -t 1 -f $n -C > /dev/null || { echo "FAIL!"; }
#  $PREFIX taler-mint-httpd -d test-mint-home/ -t 1 -f $n -C > /dev/null || { echo "FAIL!"; exit 1; }
  echo "OK"
done
exit 0
