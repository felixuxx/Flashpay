#!/bin/bash
#
# This file is part of TALER
# Copyright (C) 2015, 2016 Inria and GNUnet e.V.
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
# Setup keys.
taler-exchange-keyup -c test_taler_exchange_httpd.conf
# Run Exchange HTTPD (in background)
taler-exchange-httpd -c test_taler_exchange_httpd.conf -i &
# Give HTTP time to start
sleep 5
# Finally run test...
# We read the JSON snippets to POST from test_taler_exchange_httpd.data
cat test_taler_exchange_httpd.data | grep -v ^\# | awk '{ print "curl -d \47"  $2 "\47 http://localhost:8081" $1 }' | bash
# Stop HTTP server
kill -TERM %%
# FIXME: not sure this is the 'correct' return code...
exit $?
