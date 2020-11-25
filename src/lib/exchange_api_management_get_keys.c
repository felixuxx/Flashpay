/*
  This file is part of TALER
  Copyright (C) 2015-2020 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file lib/exchange_api_management_get_keys.c
 * @brief functions to obtain future online keys of the exchange
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_signatures.h"


/**
 * @brief Handle for a GET /management/keys request.
 */
struct TALER_EXCHANGE_ManagementGetKeysHandle;


/**
 * Request future keys from the exchange.  The obtained information will be
 * passed to the @a cb.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param cb function to call with the exchange's future keys result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementGetKeysHandle *
TALER_EXCHANGE_get_management_keys (struct GNUNET_CURL_Context *ctx,
                                    const char *url,
                                    TALER_EXCHANGE_ManagementGetKeysCallback cb,
                                    void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_get_management_keys() operation.
 *
 * @param gh handle of the operation to cancel
 */
void
TALER_EXCHANGE_get_management_keys_cancel (
  struct TALER_EXCHANGE_ManagementGetKeysHandle *gh);
