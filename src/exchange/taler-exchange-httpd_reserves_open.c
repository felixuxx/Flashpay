/*
  This file is part of TALER
  Copyright (C) 2022 Taler Systems SA

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
#include "taler-exchange-httpd_common_deposit.h"
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
   * Desired (minimum) expiration time for the reserve.
   */
  struct GNUNET_TIME_Timestamp desired_expiration;

  /**
   * Actual expiration time for the reserve.
   */
  struct GNUNET_TIME_Timestamp reserve_expiration;

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
   * Amount to be paid from the reserve.
   */
  struct TALER_Amount reserve_payment;

  /**
   * Actual cost to open the reserve.
   */
  struct TALER_Amount open_cost;

  /**
   * Total amount that was deposited.
   */
  struct TALER_Amount total;

  /**
   * Information about payments by coin.
   */
  struct TEH_PurseDepositedCoin *payments;

  /**
   * Length of the @e payments array.
   */
  unsigned int payments_len;

  /**
   * Desired minimum purse limit.
   */
  uint32_t purse_limit;

  /**
   * Set to true if the reserve balance is too low
   * for the operation.
   */
  bool no_funds;
};


/**
 * Send reserve open to client.
 *
 * @param connection connection to the client
 * @param rsc reserve open data to return
 * @return MHD result code
 */
static MHD_RESULT
reply_reserve_open_success (struct MHD_Connection *connection,
                            const struct ReserveOpenContext *rsc)
{
  unsigned int status;

  status = MHD_HTTP_OK;
  if (GNUNET_TIME_timestamp_cmp (rsc->reserve_expiration,
                                 <,
                                 rsc->desired_expiration))
    status = MHD_HTTP_PAYMENT_REQUIRED;
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    status,
    GNUNET_JSON_pack_timestamp ("reserve_expiration",
                                rsc->reserve_expiration),
    TALER_JSON_pack_amount ("open_cost",
                            &rsc->open_cost));
}


/**
 * Cleans up information in @a rsc, but does not
 * free @a rsc itself (allocated on the stack!).
 *
 * @param[in] rsc struct with information to clean up
 */
static void
cleanup_rsc (struct ReserveOpenContext *rsc)
{
  for (unsigned int i = 0; i<rsc->payments_len; i++)
  {
    TEH_common_purse_deposit_free_coin (&rsc->payments[i]);
  }
  GNUNET_free (rsc->payments);
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
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
reserve_open_transaction (void *cls,
                          struct MHD_Connection *connection,
                          MHD_RESULT *mhd_ret)
{
  struct ReserveOpenContext *rsc = cls;
  enum GNUNET_DB_QueryStatus qs;

  for (unsigned int i = 0; i<rsc->payments_len; i++)
  {
    struct TEH_PurseDepositedCoin *coin = &rsc->payments[i];
    bool insufficient_funds = true;

    qs = TEH_make_coin_known (&coin->cpi,
                              connection,
                              &coin->known_coin_id,
                              mhd_ret);
    if (qs < 0)
      return qs;
    qs = TEH_plugin->insert_reserve_open_deposit (
      TEH_plugin->cls,
      &coin->cpi,
      &coin->coin_sig,
      coin->known_coin_id,
      &coin->amount,
      &rsc->reserve_sig,
      rsc->reserve_pub,
      &insufficient_funds);
    /* 0 == qs is fine, then the coin was already
       spent for this very operation as identified
       by reserve_sig! */
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      GNUNET_break (0);
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "insert_reserve_open_deposit");
      return qs;
    }
    if (insufficient_funds)
    {
      *mhd_ret
        = TEH_RESPONSE_reply_coin_insufficient_funds (
            connection,
            TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS,
            &coin->cpi.denom_pub_hash,
            &coin->cpi.coin_pub);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }

  qs = TEH_plugin->do_reserve_open (TEH_plugin->cls,
                                    /* inputs */
                                    rsc->reserve_pub,
                                    &rsc->total,
                                    &rsc->reserve_payment,
                                    rsc->purse_limit,
                                    &rsc->reserve_sig,
                                    rsc->desired_expiration,
                                    rsc->timestamp,
                                    &rsc->gf->fees.account,
                                    /* outputs */
                                    &rsc->no_funds,
                                    &rsc->open_cost,
                                    &rsc->reserve_expiration);
  switch (qs)
  {
  case GNUNET_DB_STATUS_HARD_ERROR:
    GNUNET_break (0);
    *mhd_ret
      = TALER_MHD_reply_with_error (connection,
                                    MHD_HTTP_INTERNAL_SERVER_ERROR,
                                    TALER_EC_GENERIC_DB_FETCH_FAILED,
                                    "do_reserve_open");
    return GNUNET_DB_STATUS_HARD_ERROR;
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
  if (rsc->no_funds)
  {
    *mhd_ret
      = TEH_RESPONSE_reply_reserve_insufficient_balance (
          connection,
          &rsc->reserve_payment,
          rsc->reserve_pub);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}


MHD_RESULT
TEH_handler_reserves_open (struct TEH_RequestContext *rc,
                           const struct TALER_ReservePublicKeyP *reserve_pub,
                           const json_t *root)
{
  struct ReserveOpenContext rsc;
  json_t *payments;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_timestamp ("request_timestamp",
                                &rsc.timestamp),
    GNUNET_JSON_spec_timestamp ("reserve_expiration",
                                &rsc.desired_expiration),
    GNUNET_JSON_spec_fixed_auto ("reserve_sig",
                                 &rsc.reserve_sig),
    GNUNET_JSON_spec_uint32 ("purse_limit",
                             &rsc.purse_limit),
    GNUNET_JSON_spec_json ("payments",
                           &payments),
    TALER_JSON_spec_amount ("reserve_payment",
                            TEH_currency,
                            &rsc.reserve_payment),
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

  {
    struct GNUNET_TIME_Timestamp now;

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
  }

  rsc.payments_len = json_array_size (payments);
  rsc.payments = GNUNET_new_array (rsc.payments_len,
                                   struct TEH_PurseDepositedCoin);
  rsc.total = rsc.reserve_payment;
  for (unsigned int i = 0; i<rsc.payments_len; i++)
  {
    struct TEH_PurseDepositedCoin *coin = &rsc.payments[i];
    enum GNUNET_GenericReturnValue res;

    res = TEH_common_purse_deposit_parse_coin (
      rc->connection,
      coin,
      json_array_get (payments,
                      i));
    if (GNUNET_SYSERR == res)
    {
      GNUNET_break (0);
      cleanup_rsc (&rsc);
      return MHD_NO;   /* hard failure */
    }
    if (GNUNET_NO == res)
    {
      GNUNET_break_op (0);
      cleanup_rsc (&rsc);
      return MHD_YES;   /* failure */
    }
    if (0 >
        TALER_amount_add (&rsc.total,
                          &rsc.total,
                          &coin->amount_minus_fee))
    {
      GNUNET_break (0);
      cleanup_rsc (&rsc);
      return TALER_MHD_reply_with_error (rc->connection,
                                         MHD_HTTP_INTERNAL_SERVER_ERROR,
                                         TALER_EC_GENERIC_FAILED_COMPUTE_AMOUNT,
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
      cleanup_rsc (&rsc);
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
    cleanup_rsc (&rsc);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_EXCHANGE_GENERIC_BAD_CONFIGURATION,
                                       NULL);
  }

  if (GNUNET_OK !=
      TALER_wallet_reserve_open_verify (&rsc.reserve_payment,
                                        rsc.timestamp,
                                        rsc.desired_expiration,
                                        rsc.purse_limit,
                                        reserve_pub,
                                        &rsc.reserve_sig))
  {
    GNUNET_break_op (0);
    cleanup_rsc (&rsc);
    return TALER_MHD_reply_with_error (rc->connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_RESERVES_OPEN_BAD_SIGNATURE,
                                       NULL);
  }

  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (rc->connection,
                                "reserve open",
                                TEH_MT_REQUEST_OTHER,
                                &mhd_ret,
                                &reserve_open_transaction,
                                &rsc))
    {
      cleanup_rsc (&rsc);
      return mhd_ret;
    }
  }

  {
    MHD_RESULT mhd_ret;

    mhd_ret = reply_reserve_open_success (rc->connection,
                                          &rsc);
    cleanup_rsc (&rsc);
    return mhd_ret;
  }
}


/* end of taler-exchange-httpd_reserves_open.c */
