#!/bin/sh
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
# This will generate testcases in a directory 'afl-tests', which can then
# be moved into src/exchange/afl-tests/ to be run during exchange-testing.
#
# This script uses American Fuzzy Loop (AFL) to fuzz the exchange to
# automatically create tests with good coverage.  You must install
# AFL and set AFL_HOME to the directory where AFL is installed
# before running.  Also, a directory "baseline/" should exist with
# templates for inputs for AFL to fuzz.  These can be generated
# by running wireshark on loopback while running 'make check' in
# this directory.  Save each HTTP request to a new file.
#
# Note that you want to switch 'TESTRUN = NO' and pre-init the
# database before running this, otherwise it will be awfully slow.
#
# Must be run from this directory.
#
$AFL_HOME/afl-fuzz -i baseline/ -m 250 -o afl-tests/ -f /tmp/afl-input taler-exchange-httpd -f /tmp/afl-input -d test-exchange-home/ -C
