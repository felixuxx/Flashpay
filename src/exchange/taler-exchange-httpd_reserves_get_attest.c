/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU Affero General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-exchange-httpd_reserves_get_attest.c
 * @brief Handle GET /reserves/$RESERVE_PUB/attest requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_mhd_lib.h"
#include "taler_json_lib.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_reserves_get_attest.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Closure for #reserve_attest_transaction.
 */
struct ReserveAttestContext
{
  /**
   * Public key of the reserve the inquiry is about.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Available attributes.
   */
  json_t *attributes;

  /**
   * Set to true if we did not find the reserve.
   */
  bool not_found;
};


/**
 * Function implementing GET /reserves/$RID/attest transaction.
 * Execute a /reserves/ get attest.  Given the public key of a reserve,
 * return the associated transaction attest.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * @param cls a `struct ReserveAttestContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserve_attest_transaction (void *cls,
                            struct MHD_Connection *connection,
                            MHD_RESULT *mhd_ret)
{
  struct ReserveAttestContext *rsc = cls;
  enum GNUNET_DB_QueryStatus qs;

#if FIXME
  qs = TEH_plugin->get_reserve_attributes (TEH_plugin->cls,
                                           &rsc->reserve_pub,
                                           &rsc->attributes);
#else
  qs = GNUNET_DB_STATUS_HARD_ERROR;
#endif
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_break (0);
    *mhd_ret
      = TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_INTERNAL_SERVER_ERROR,
                                    TALER_EC_GENERIC_DB_FETCH_FAILED,
                                    "get_reserve_attributes");
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    rsc->not_found = true;
  if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT == qs)
    rsc->not_found = false;
  return qs;
}


MHD_RESULT
TEH_handler_reserves_get_attest (struct TEH_RequestContext *rc,
                                 const char *const args[1])
{
  struct ReserveAttestContext rsc;

  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (args[0],
                                     strlen (args[0]),
                                     &rsc.reserve_pub,
                                     sizeof (rsc.reserve_pub)))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_RESERVE_PUB_MALFORMED,
                                       args[0]);
  }
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (rc->connection,
                                "get-attestable",
                                TEH_MT_REQUEST_OTHER,
                                &mhd_ret,
                                &reserve_attest_transaction,
                                &rsc))
    {
      return mhd_ret;
    }
  }
  /* generate proper response */
  if (rsc.not_found)
  {
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
                                       args[0]);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    rc->connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_object_steal ("attributes",
                                   rsc.attributes));
}


/* end of taler-exchange-httpd_reserves_get_attest.c */
