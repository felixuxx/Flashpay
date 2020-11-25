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
 * @file lib/exchange_api_management_wire_enable.c
 * @brief functions to enable an exchange wire method / bank account
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_signatures.h"
/**
 * @brief Handle for a POST /management/wire request.
 */
struct TALER_EXCHANGE_ManagementWireEnableHandle;


/**
 * Inform the exchange that a wire account should be enabled.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param salt salt to use when hashing the account for the signature
 * @param payto_uri RFC 8905 URI of the exchange's bank account
 * @param validity_start when was this decided?
 * @param master_sig signature affirming the wire addition
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementWireEnableHandle *
TALER_EXCHANGE_management_enable_wire (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const char *salt,
  const char *payto_uri,
  struct GNUNET_TIME_Absolute validity_start,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementWireEnableCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_enable_wire() operation.
 *
 * @param wh handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_enable_wire_cancel (
  struct TALER_EXCHANGE_ManagementWireEnableHandle *wh);
