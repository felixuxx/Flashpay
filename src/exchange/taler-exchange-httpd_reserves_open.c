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
 * @file taler-exchange-httpd_reserves_open.c
 * @brief Handle /reserves/$RESERVE_PUB/open requests
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <jansson.h>
#include "taler_mhd_lib.h"
#include "taler_json_lib.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_reserves_open.h"
#include "taler-exchange-httpd_responses.h"


/**
 * How far do we allow a client's time to be off when
 * checking the request timestamp?
 */
#define TIMESTAMP_TOLERANCE \
  GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MINUTES, 15)


/**
 * Closure for #reserve_open_transaction.
 */
struct ReserveOpenContext
{
  /**
   * Public key of the reserve the inquiry is about.
   */
  const struct TALER_ReservePublicKeyP *reserve_pub;

  /**
   * Timestamp of the request.
   */
  struct GNUNET_TIME_Timestamp timestamp;

  /**
   * Client signature approving the request.
   */
  struct TALER_ReserveSignatureP reserve_sig;

  /**
   * Open of the reserve, set in the callback.
   */
  struct TALER_EXCHANGEDB_ReserveOpen *rh;

  /**
   * Global fees applying to the request.
   */
  const struct TEH_GlobalFee *gf;

  /**
   * Current reserve balance.
   */
  struct TALER_Amount balance;
};


/**
 * Send reserve open to client.
 *
 * @param connection connection to the client
 * @param rhc reserve open to return
 * @return MHD result code
 */
static MHD_RESULT
reply_reserve_open_success (struct MHD_Connection *connection,
                            const struct ReserveOpenContext *rhc)
{
  const struct TALER_EXCHANGEDB_ReserveOpen *rh = rhc->rh;

  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    TALER_JSON_pack_amount ("balance",
                            &rhc->balance));
}


/**
 * Function implementing /reserves/$RID/open transaction.  Given the public
 * key of a reserve, return the associated transaction open.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction logic
 * MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls a `struct ReserveOpenContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!); unused
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserve_open_transaction (void *cls,
                          struct MHD_Connection *connection,
                          MHD_RESULT *mhd_ret)
{
  struct ReserveOpenContext *rsc = cls;
  enum GNUNET_DB_QueryStatus qs;

  if (! TALER_amount_is_zero (&rsc->gf->fees.open))
  {
    bool balance_ok = false;
    bool idempotent = true;

    qs = TEH_plugin->insert_open_request (TEH_plugin->cls,
                                          rsc->reserve_pub,
                                          &rsc->reserve_sig,
                                          rsc->timestamp,
                                          &rsc->gf->fees.open,
                                          &balance_ok,
                                          &idempotent);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      *mhd_ret
        = TALER_MHD_reply_with_error (connection,
                                      MHD_HTTP_INTERNAL_SERVER_ERROR,
                                      TALER_EC_GENERIC_DB_FETCH_FAILED,
                                      "get_reserve_open");
    }
    if (qs <= 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return qs;
    }
    if (! balance_ok)
    {
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_CONFLICT,
                                         TALER_EC_EXCHANGE_WITHDRAW_OPEN_ERROR_INSUFFICIENT_FUNDS,
                                         NULL);
    }
    if (idempotent)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                  "Idempotent /reserves/open request observed. Is caching working?\n");
    }
  }
  qs = TEH_plugin->get_reserve_open (TEH_plugin->cls,
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
                                    "get_reserve_open");
  }
  return qs;
}


MHD_RESULT
TEH_handler_reserves_open (struct TEH_RequestContext *rc,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           const json_t *root)
{
  struct ReserveOpenContext rsc;
  MHD_RESULT mhd_ret;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_timestamp ("request_timestamp",
                                &rsc.timestamp),
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &rsc.reserve_sig),
    GNUNET_JSON_spec_end ()
  };
  struct GNUNET_TIME_Timestamp now;

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
  now = GNUNET_TIME_timestamp_get ();
  if (! GNUNET_TIME_absolute_approx_eq (now.abs_time,
                                        rsc.timestamp.abs_time,
                                        TIMESTAMP_TOLERANCE))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_GENERIC_CLOCK_SKEW,
                                       NULL);
  }
  {
    struct TEH_KeyStateHandle *keys;

    keys = TEH_keys_get_state ();
    if (NULL == keys)
    {
      GNUNET_break (0);
      GNUNET_JSON_parse_free (spec);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_EXCHANGE_GENERIC_KEYS_MISSING,
                                         NULL);
    }
    rsc.gf = TEH_keys_global_fee_by_time (keys,
                                          rsc.timestamp);
  }
  if (NULL == rsc.gf)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_BAD_CONFIGURATION,
                                       NULL);
  }
  if (GNUNET_OK !=
      TALER_wallet_reserve_open_verify (rsc.timestamp,
                                        &rsc.gf->fees.open,
                                        reserve_pub,
                                        &rsc.reserve_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_RESERVES_OPEN_BAD_SIGNATURE,
                                       NULL);
  }
  rsc.rh = NULL;
  if (GNUNET_OK !=
      TEH_DB_run_transaction (rc->connection,
                              "reserve open",
                              TEH_MT_REQUEST_OTHER,
                              &mhd_ret,
                              &reserve_open_transaction,
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
  return reply_reserve_open_success (rc->connection,
                                     &rsc);
}


/* end of taler-exchange-httpd_reserves_open.c */
