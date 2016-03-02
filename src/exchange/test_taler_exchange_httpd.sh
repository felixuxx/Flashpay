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
# taler-exchange-httpd.  Basically, the goal is to make sure that the
# HTTP server survives (and produces the 'correct' error code).
#
# We read the JSON snippets to POST from test_taler_exchange_httpd.data
#
# Setup keys.
taler-exchange-keyup -d test-exchange-home -m test-exchange-home/master.priv
# Run Exchange HTTPD (in background)
taler-exchange-httpd -d test-exchange-home &
# Give HTTP time to start
sleep 5
# Run test...
cat test_taler_exchange_httpd.data | grep -v ^\# | awk '{ print "curl -d '\''" $2 "'\'' http://localhost:8081"$1 }' | bash
# Stop HTTP server
kill -TERM %%
# FIXME: not sure this is the 'correct' return code...
exit $?
