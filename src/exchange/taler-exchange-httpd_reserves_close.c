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
#include "taler_kyclogic_lib.h"
#include "taler_mhd_lib.h"
#include "taler_json_lib.h"
#include "taler_dbevents.h"
#include "taler-exchange-httpd_keys.h"
#include "taler-exchange-httpd_reserves_close.h"
#include "taler-exchange-httpd_withdraw.h"
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
   * Amount that will be wired (after closing fees).
   */
  struct TALER_Amount wire_amount;

  /**
   * Current balance of the reserve.
   */
  struct TALER_Amount balance;

  /**
   * Where to wire the funds, may be NULL.
   */
  const char *payto_uri;

  /**
   * Hash of the @e payto_uri, if given (otherwise zero).
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * KYC status for the request.
   */
  struct TALER_EXCHANGEDB_KycStatus kyc;

  /**
   * Hash of the payto-URI that was used for the KYC decision.
   */
  struct TALER_PaytoHashP kyc_payto;

  /**
   * Query status from the amount_it() helper function.
   */
  enum GNUNET_DB_QueryStatus qs;
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
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    TALER_JSON_pack_amount ("wire_amount",
                            &rhc->wire_amount));
}


/**
 * Function called to iterate over KYC-relevant
 * transaction amounts for a particular time range.
 * Called within a database transaction, so must
 * not start a new one.
 *
 * @param cls closure, identifies the event type and
 *        account to iterate over events for
 * @param limit maximum time-range for which events
 *        should be fetched (timestamp in the past)
 * @param cb function to call on each event found,
 *        events must be returned in reverse chronological
 *        order
 * @param cb_cls closure for @a cb
 */
static void
amount_it (void *cls,
           struct GNUNET_TIME_Absolute limit,
           TALER_EXCHANGEDB_KycAmountCallback cb,
           void *cb_cls)
{
  struct ReserveCloseContext *rcc = cls;
  enum GNUNET_GenericReturnValue ret;

  ret = cb (cb_cls,
            &rcc->balance,
            GNUNET_TIME_absolute_get ());
  GNUNET_break (GNUNET_SYSERR != ret);
  if (GNUNET_OK != ret)
    return;
  rcc->qs
    = TEH_plugin->iterate_reserve_close_info (
        TEH_plugin->cls,
        &rcc->kyc_payto,
        limit,
        cb,
        cb_cls);
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
  char *payto_uri = NULL;
  const struct TALER_WireFeeSet *wf;

  qs = TEH_plugin->select_reserve_close_info (
    TEH_plugin->cls,
    rcc->reserve_pub,
    &rcc->balance,
    &payto_uri);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    *mhd_ret
      = TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_INTERNAL_SERVER_ERROR,
                                    TALER_EC_GENERIC_DB_FETCH_FAILED,
                                    "select_reserve_close_info");
    return qs;
  case GNUNET_DB_STATUS_SOFT_ERROR:
    return qs;
  case GNUNET_DB_STATUS_SUCCESS_NO_RESULTS:
    *mhd_ret
      = TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_NOT_FOUND,
                                    TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN,
                                    NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  case GNUNET_DB_STATUS_SUCCESS_ONE_RESULT:
    break;
  }

  if ( (NULL == rcc->payto_uri) &&
       (NULL == payto_uri) )
  {
    *mhd_ret
      = TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_CONFLICT,
                                    TALER_EC_EXCHANGE_RESERVES_CLOSE_NO_TARGET_ACCOUNT,
                                    NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  if ( (NULL != rcc->payto_uri) &&
       ( (NULL == payto_uri) ||
         (0 != strcmp (payto_uri,
                       rcc->payto_uri)) ) )
  {
    /* KYC check may be needed: we're not returning
       the money to the account that funded the reserve
       in the first place. */
    union TALER_AccountPublicKeyP account_pub = {
      /* FIXME: not the correct account pub, should extract
         from inbound wire transfer! Or pass NULL here? */
      .reserve_pub = *rcc->reserve_pub
    };

    TALER_payto_hash (rcc->payto_uri,
                      &rcc->kyc_payto);
    rcc->qs = GNUNET_DB_STATUS_SUCCESS_NO_RESULTS;
    qs = TEH_legitimization_check (
      &rcc->kyc,
      connection,
      mhd_ret,
      TALER_KYCLOGIC_KYC_TRIGGER_RESERVE_CLOSE,
      &rcc->kyc_payto,
      &account_pub,
      &amount_it,
      rcc);
    if ( (qs < 0) ||
         (! rcc->kyc.ok) )
      return qs;
  }
  else
  {
    rcc->kyc.ok = true;
  }
  if (NULL == rcc->payto_uri)
    rcc->payto_uri = payto_uri;

  {
    char *method;

    method = TALER_payto_get_method (rcc->payto_uri);
    wf = TEH_wire_fees_by_time (rcc->timestamp,
                                method);
    if (NULL == wf)
    {
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_EXCHANGE_WIRE_FEES_NOT_CONFIGURED,
                                             method);
      GNUNET_free (method);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    GNUNET_free (method);
  }

  if (0 >
      TALER_amount_subtract (&rcc->wire_amount,
                             &rcc->balance,
                             &wf->closing))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Client attempted to close reserve with insufficient balance.\n");
    GNUNET_assert (GNUNET_OK ==
                   TALER_amount_set_zero (TEH_currency,
                                          &rcc->wire_amount));
    *mhd_ret = reply_reserve_close_success (connection,
                                            rcc);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }

  qs = TEH_plugin->insert_close_request (TEH_plugin->cls,
                                         rcc->reserve_pub,
                                         payto_uri,
                                         &rcc->reserve_sig,
                                         rcc->timestamp,
                                         &rcc->balance,
                                         &wf->closing);
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
    GNUNET_JSON_spec_mark_optional (
      TALER_JSON_spec_payto_uri ("payto_uri",
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

  if (NULL != rcc.payto_uri)
    TALER_payto_hash (rcc.payto_uri,
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
  if (! rcc.kyc.ok)
    return TEH_RESPONSE_reply_kyc_required (rc->connection,
                                            &rcc.kyc_payto,
                                            &rcc.kyc);

  return reply_reserve_close_success (rc->connection,
                                      &rcc);
}


/* end of taler-exchange-httpd_reserves_close.c */
