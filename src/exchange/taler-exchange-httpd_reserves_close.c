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
 * @file taler-exchange-httpd_reserves_close.c
 * @brief Handle /reserves/$RESERVE_PUB/close requests
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
#include "taler-exchange-httpd_reserves_close.h"
#include "taler-exchange-httpd_responses.h"


/**
 * How far do we allow a client's time to be off when
 * checking the request timestamp?
 */
#define TIMESTAMP_TOLERANCE \
  GNUNET_TIME_relative_multiply (GNUNET_TIME_UNIT_MINUTES, 15)


/**
 * Closure for #reserve_close_transaction.
 */
struct ReserveCloseContext
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
   * Global fees applying to the request.
   */
  const struct TEH_GlobalFee *gf;

  /**
   * Amount that will be wired (after closing fees).
   */
  struct TALER_Amount wire_amount;

  /**
   * Where to wire the funds, may be NULL.
   */
  const char *payto_uri;

  /**
   * Hash of the @e payto_uri.
   */
  struct TALER_PaytoHashP h_payto;

};


/**
 * Send reserve close to client.
 *
 * @param connection connection to the client
 * @param rhc reserve close to return
 * @return MHD result code
 */
static MHD_RESULT
reply_reserve_close_success (struct MHD_Connection *connection,
                             const struct ReserveCloseContext *rhc)
{
  const struct TALER_EXCHANGEDB_ReserveClose *rh = rhc->rh;

  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    TALER_JSON_pack_amount ("wire_amount",
                            &rhc->wire_amount));
}


/**
 * Function implementing /reserves/$RID/close transaction.  Given the public
 * key of a reserve, return the associated transaction close.  Runs the
 * transaction logic; IF it returns a non-error code, the transaction logic
 * MUST NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF it
 * returns the soft error code, the function MAY be called again to retry and
 * MUST not queue a MHD response.
 *
 * @param cls a `struct ReserveCloseContext *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!); unused
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserve_close_transaction (void *cls,
                           struct MHD_Connection *connection,
                           MHD_RESULT *mhd_ret)
{
  struct ReserveCloseContext *rcc = cls;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_Amount balance;
  char *payto_uri;

  qs = TEH_plugin->get_reserve_balance (TEH_plugin->cls,
                                        rcc->reserve_pub,
                                        &balance,
                                        &payto_uri);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    *mhd_ret
      = TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_INTERNAL_SERVER_ERROR,
                                    TALER_EC_GENERIC_DB_FETCH_FAILED,
                                    "get_reserve_balance");
    return qs;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    return qs;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    *mhd_ret
      = TALER_MHD_reply_with_error (rc->connection,
                                    MHD_HTTP_NOT_FOUND,
                                    TALER_EC_EXCHANGE_RESERVES_STATUS_UNKNOWN,
                                    NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if ( (NULL == rcc->payto_uri) &&
       (NULL == payto_uri) )
  {
    *mhd_ret
      = TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_CONFLICT,
                                    TALER_EC_RESERVE_CLOSE_NO_TARGET_ACCOUNT,
                                    NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if ( (NULL != rcc->payto_uri) &&
       ( (NULL == payto_uri) ||
         (0 != strcmp (payto_uri,
                       rcc->payto_uri)) ) )
  {
    struct TALER_EXCHANGEDB_KycStatus kyc;
    struct TALER_PaytoHashP kyc_payto;

    /* FIXME: also fetch KYC status from reserve
       in query above, and if payto_uri specified
       and KYC not yet done (check KYC triggers!),
       fail with 451 kyc required! */
    *mhd_ret
      = TEH_RESPONSE_reply_kyc_required (rcc->connection,
                                         &kyc_payto,
                                         &kyc);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if (NULL == rcc->payto_uri)
    rcc->payto_uri = payto_uri;

  if (0 >
      TALER_amount_subtract (&rcc->wire_amount,
                             &balance,
                             &rcc->gf->fees.close))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Client attempted to close reserve with insufficient balance.\n");
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (TEH_currency,
                                          &rcc->wire_amount));
    *mhd_ret = reply_reserve_close_success (rc->connection,
                                            &rcc);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  {
    qs = TEH_plugin->insert_close_request (TEH_plugin->cls,
                                           rcc->reserve_pub,
                                           payto_uri,
                                           &rcc->reserve_sig,
                                           rcc->timestamp,
                                           &rcc->gf->fees.close,
                                           &rcc->wire_amount);
    GNUNET_free (payto_uri);
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
    {
      GNUNET_break (0);
      *mhd_ret
        = TALER_MHD_reply_with_error (connection,
                                      MHD_HTTP_INTERNAL_SERVER_ERROR,
                                      TALER_EC_GENERIC_DB_FETCH_FAILED,
                                      "insert_close_request");
      return qs;
    }
    if (qs <= 0)
    {
      GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR == qs);
      return qs;
    }
  }
  return qs;
}


MHD_RESULT
TEH_handler_reserves_close (struct TEH_RequestContext *rc,
                            const struct TALER_ReservePublicKeyP *reserve_pub,
                            const json_t *root)
{
  struct ReserveCloseContext rcc = {
    .payto_uri = NULL,
    .reserve_pub = reserve_pub
  };
  MHD_RESULT mhd_ret;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_timestamp ("request_timestamp",
                                &rcc.timestamp),
    GNUNET_JSON_spec_allow_null (
      GNUNET_JSON_spec_string ("payto_uri",
                               &rcc.payto_uri),
      NULL),
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &rcc.reserve_sig),
    GNUNET_JSON_spec_end ()
  };

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

  {
    struct GNUNET_TIME_Timestamp now;

    now = GNUNET_TIME_timestamp_get ();
    if (! GNUNET_TIME_absolute_approx_eq (now.abs_time,
                                          rcc.timestamp.abs_time,
                                          TIMESTAMP_TOLERANCE))
    {
      GNUNET_break_op (0);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_GENERIC_CLOCK_SKEW,
                                         NULL);
    }
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
    rcc.gf = TEH_keys_global_fee_by_time (keys,
                                          rcc.timestamp);
  }
  if (NULL == rcc.gf)
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_BAD_CONFIGURATION,
                                       NULL);
  }
  if (NULL != rcc.payto_uri)
    TALER_payto_hash (&rcc.payto_uri,
                      &rcc.h_payto);
  if (GNUNET_OK !=
      TALER_wallet_reserve_close_verify (rcc.timestamp,
                                         &rcc.h_payto,
                                         reserve_pub,
                                         &rcc.reserve_sig))
  {
    GNUNET_break_op (0);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_RESERVES_CLOSE_BAD_SIGNATURE,
                                       NULL);
  }
  if (GNUNET_OK !=
      TEH_DB_run_transaction (rc->connection,
                              "reserve close",
                              TEH_MT_REQUEST_OTHER,
                              &mhd_ret,
                              &reserve_close_transaction,
                              &rcc))
  {
    return mhd_ret;
  }
  return reply_reserve_close_success (rc->connection,
                                      &rcc);
}


/* end of taler-exchange-httpd_reserves_close.c */
