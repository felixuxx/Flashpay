/*
  This file is part of TALER
  (C) 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of EXCHANGEABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_config.h
 * @brief headers for /config handler
 * @author Christian Grothoff
 */
#ifndef TALER_EXCHANGE_HTTPD_CONFIG_H
#define TALER_EXCHANGE_HTTPD_CONFIG_H
#include <microhttpd.h>
#include "taler-exchange-httpd.h"


/**
 * Taler protocol version in the format CURRENT:REVISION:AGE
 * as used by GNU libtool.  See
 * https://www.gnu.org/software/libtool/manual/html_node/Libtool-versioning.html
 *
 * Please be very careful when updating and follow
 * https://www.gnu.org/software/libtool/manual/html_node/Updating-version-info.html#Updating-version-info
 * precisely.  Note that this version has NOTHING to do with the
 * release version, and the format is NOT the same that semantic
 * versioning uses either.
 *
 * When changing this version, you likely want to also update
 * #TALER_PROTOCOL_CURRENT and #TALER_PROTOCOL_AGE in
 * exchange_api_handle.c!
 *
 * Returned via both /config and /keys endpoints.
 */
#define EXCHANGE_PROTOCOL_VERSION "14:0:2"


/**
 * Manages a /config call.
 *
 * @param rc context of the handler
 * @param[in,out] args remaining arguments (ingored)
 * @return MHD result code
 */
MHD_RESULT
TEH_handler_config (struct TEH_RequestContext *rc,
                    const char *const args[]);

#endif
