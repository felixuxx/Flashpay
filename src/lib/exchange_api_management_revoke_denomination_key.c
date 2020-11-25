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
 * @file lib/exchange_api_management_revoke_denomination_key.c
 * @brief functions to revoke an exchange denomination key
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_signatures.h"


/**
 * @brief Handle for a POST /management/denominations/$H_DENOM_PUB/revoke request.
 */
struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle
{

  /**
   * The url for this request.
   */
  char *url;

  /**
   * Handle for the request.
   */
  struct GNUNET_CURL_Job *job;

  /**
   * Function to call with the result.
   */
  TALER_EXCHANGE_ManagementRevokeDenominationKeyCallback cb;

  /**
   * Closure for @a cb.
   */
  void *cb_cls;

  /**
   * Reference to the execution context.
   */
  struct GNUNET_CURL_Context *ctx;
};


/**
 * Inform the exchange that a denomination key was revoked.
 *
 * @param ctx the context
 * @param url HTTP base URL for the exchange
 * @param h_denom_pub hash of the denomination public key that was revoked
 * @param master_sig signature affirming the revocation
 * @param cb function to call with the exchange's result
 * @param cb_cls closure for @a cb
 * @return the request handle; NULL upon error
 */
struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle *
TALER_EXCHANGE_management_revoke_denomination_key (
  struct GNUNET_CURL_Context *ctx,
  const char *url,
  const struct GNUNET_HashCode *h_denom_pub,
  const struct TALER_MasterSignatureP *master_sig,
  TALER_EXCHANGE_ManagementRevokeDenominationKeyCallback cb,
  void *cb_cls);


/**
 * Cancel #TALER_EXCHANGE_management_revoke_denomination_key() operation.
 *
 * @param rh handle of the operation to cancel
 */
void
TALER_EXCHANGE_management_revoke_denomination_key_cancel (
  struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle *rh)
{
  if (NULL != rh->job)
  {
    GNUNET_CURL_job_cancel (rh->job);
    rh->job = NULL;
  }
  GNUNET_free (rh->url);
  GNUNET_free (rh);
}
