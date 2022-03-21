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
 * @file taler-exchange-httpd_reserves_status.c
 * @brief Handle /reserves/$RESERVE_PUB STATUS requests
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_mhd_lib.h"
#include "taler_json_lib.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_reserves_status.h"
#include "taler-exchange-httpd_responses.h"


/**
 * Closure for #reserve_status_transaction.
 */
struct ReserveStatusContext
{
  /**
   * Public key of the reserve the inquiry is about.
   */
  const struct TALER_ReservePublicKeyP *reserve_pub;

  /**
   * History of the reserve, set in the callback.
   */
  struct TALER_EXCHANGEDB_ReserveHistory *rh;

  /**
   * Current reserve balance.
   */
  struct TALER_Amount balance;
};


/**
 * Send reserve status to client.
 *
 * @param connection connection to the client
 * @param rh reserve history to return
 * @return MHD result code
 */
static MHD_RESULT
reply_reserve_status_success (struct MHD_Connection *connection,
                              const struct ReserveStatusContext *rhc)
{
  const struct TALER_EXCHANGEDB_ReserveHistory *rh = rhc->rh;
  json_t *json_history;

  json_history = TEH_RESPONSE_compile_reserve_history (rh);
  if (NULL == json_history)
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_JSON_ALLOCATION_FAILURE,
                                       NULL);
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    TALER_JSON_pack_amount ("balance",
                            &rhc->balance),
    GNUNET_JSON_pack_array_steal ("history",
                                  json_history));
}


/**
 * Function implementing /reserves/ STATUS transaction.
 * Execute a /reserves/ STATUS.  Given the public key of a reserve,
 * return the associated transaction history.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction
 * logic MUST NOT queue a MHD response.  IF it returns an hard error,
 * the transaction logic MUST queue a MHD response and set @a mhd_ret.
 * IF it returns the soft error code, the function MAY be called again
 * to retry and MUST not queue a MHD response.
 *
 * @param cls a `struct ReserveStatusContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!); unused
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserve_status_transaction (void *cls,
                            struct MHD_Connection *connection,
                            MHD_RESULT *mhd_ret)
{
  struct ReserveStatusContext *rsc = cls;
  enum GNUNET_DB_QueryStatus qs;

  qs = TEH_plugin->get_reserve_history (TEH_plugin->cls,
                                        rsc->reserve_pub,
                                        &rsc->balance,
                                        &rsc->rh);
  if (GNUNET_DB_STATUS_HARD_ERROR == qs)
  {
    GNUNET_break (0);
    *mhd_ret
      = TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_INTERNAL_SERVER_ERROR,
                                    TALER_EC_GENERIC_DB_FETCH_FAILED,
                                    "get_reserve_status");
  }
  return qs;
}


MHD_RESULT
TEH_handler_reserves_status (struct TEH_RequestContext *rc,
                             const struct TALER_ReservePublicKeyP *reserve_pub,
                             const json_t *root)
{
  struct ReserveStatusContext rsc;
  MHD_RESULT mhd_ret;
  struct GNUNET_TIME_Timestamp timestamp;
  struct TALER_ReserveSignatureP reserve_sig;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_timestamp ("request_timestamp",
                                &timestamp),
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &reserve_sig),
    GNUNET_JSON_spec_end ()
  };

  rsc.reserve_pub = reserve_pub;
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (rc->connection,
                                     root,
                                     spec);
    if (GNUNET_SYSERR == res)
    {
      GNUNET_break (0);
      return MHD_NO; /* hard failure */
    }
    if (GNUNET_NO == res)
    {
      GNUNET_break_op (0);
      return MHD_YES; /* failure */
    }
  }
  if (GNUNET_OK !=
      TALER_wallet_reserve_status_verify (timestamp,
                                          reserve_pub,
                                          &reserve_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_RESERVES_STATUS_BAD_SIGNATURE,
                                       NULL);
  }
  rsc.rh = NULL;
  if (GNUNET_OK !=
      TEH_DB_run_transaction (rc->connection,
                              "get reserve status",
                              TEH_MT_REQUEST_OTHER,
                              &mhd_ret,
                              &reserve_status_transaction,
                              &rsc))
  {
    return mhd_ret;
  }
  if (NULL == rsc.rh)
  {
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_NOT_FOUND,
                                       TALER_EC_EXCHANGE_RESERVES_STATUS_UNKNOWN,
                                       NULL);
  }
  mhd_ret = reply_reserve_status_success (rc->connection,
                                          &rsc);
  TEH_plugin->free_reserve_history (TEH_plugin->cls,
                                    rsc.rh);
  return mhd_ret;
}


/* end of taler-exchange-httpd_reserves_status.c */
