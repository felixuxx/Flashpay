/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file taler-exchange-httpd_refund.c
 * @brief Handle refund requests; parses the POST and JSON and
 *        verifies the coin signature before handing things off
 *        to the database.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include "platform.h"
#include <gnunet/gnunet_util_lib.h>
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>
#include <microhttpd.h>
#include <pthread.h>
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_refund.h"
#include "taler-exchange-httpd_responses.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Generate successful refund confirmation message.
 *
 * @param connection connection to the client
 * @param coin_pub public key of the coin
 * @param refund details about the successful refund
 * @return MHD result code
 */
static MHD_RESULT
reply_refund_success (struct MHD_Connection *connection,
                      const struct TALER_CoinSpendPublicKeyP *coin_pub,
                      const struct TALER_EXCHANGEDB_RefundListEntry *refund)
{
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  struct TALER_RefundConfirmationPS rc = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_REFUND),
    .purpose.size = htonl (sizeof (rc)),
    .h_contract_terms = refund->h_contract_terms,
    .coin_pub = *coin_pub,
    .merchant = refund->merchant_pub,
    .rtransaction_id = GNUNET_htonll (refund->rtransaction_id)
  };
  enum TALER_ErrorCode ec;

  TALER_amount_hton (&rc.refund_amount,
                     &refund->refund_amount);
  if (TALER_EC_NONE !=
      (ec = TEH_keys_exchange_sign (&rc,
                                    &pub,
                                    &sig)))
  {
    return TALER_MHD_reply_with_ec (connection,
                                    ec,
                                    NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &sig),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &pub));
}


/**
 * Closure for refund_transaction().
 */
struct RefundContext
{
  /**
   * Details about the deposit operation.
   */
  const struct TALER_EXCHANGEDB_Refund *refund;

  /**
   * Deposit fee of the coin.
   */
  struct TALER_Amount deposit_fee;

  /**
   * Unique ID of the coin in known_coins.
   */
  uint64_t known_coin_id;
};


/**
 * Execute a "/refund" transaction.  Returns a confirmation that the
 * refund was successful, or a failure if we are not aware of a
 * matching /deposit or if it is too late to do the refund.
 *
 * IF it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls closure with a `const struct TALER_EXCHANGEDB_Refund *`
 * @param connection MHD request which triggered the transaction
 * @param[out] mhd_ret set to MHD response status for @a connection,
 *             if transaction failed (!)
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
refund_transaction (void *cls,
                    struct MHD_Connection *connection,
                    MHD_RESULT *mhd_ret)
{
  struct RefundContext *rctx = cls;
  const struct TALER_EXCHANGEDB_Refund *refund = rctx->refund;
  enum GNUNET_DB_QueryStatus qs;
  bool not_found;
  bool refund_ok;
  bool conflict;
  bool gone;

  /* Finally, store new refund data */
  qs = TEH_plugin->do_refund (TEH_plugin->cls,
                              refund,
                              &rctx->deposit_fee,
                              rctx->known_coin_id,
                              &not_found,
                              &refund_ok,
                              &gone,
                              &conflict);
  if (0 > qs)
  {
    if (GNUNET_DB_STATUS_HARD_ERROR == qs)
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "do refund");
    return qs;
  }

  if (gone)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_GONE,
                                           TALER_EC_EXCHANGE_REFUND_MERCHANT_ALREADY_PAID,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (conflict)
  {
    TEH_plugin->rollback (TEH_plugin->cls);
    *mhd_ret = TEH_RESPONSE_reply_coin_insufficient_funds (
      connection,
      TALER_EC_EXCHANGE_REFUND_INCONSISTENT_AMOUNT,
      &refund->coin.coin_pub);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (not_found)
  {
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_NOT_FOUND,
                                           TALER_EC_EXCHANGE_REFUND_DEPOSIT_NOT_FOUND,
                                           NULL);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! refund_ok)
  {
    TEH_plugin->rollback (TEH_plugin->cls);
    *mhd_ret = TEH_RESPONSE_reply_coin_insufficient_funds (
      connection,
      TALER_EC_EXCHANGE_REFUND_CONFLICT_DEPOSIT_INSUFFICIENT,
      &refund->coin.coin_pub);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  return qs;
}


/**
 * We have parsed the JSON information about the refund, do some basic
 * sanity checks (especially that the signature on the coin is valid)
 * and then execute the refund.  Note that we need the DB to check
 * the fee structure, so this is not done here.
 *
 * @param connection the MHD connection to handle
 * @param[in,out] refund information about the refund
 * @return MHD result code
 */
static MHD_RESULT
verify_and_execute_refund (struct MHD_Connection *connection,
                           struct TALER_EXCHANGEDB_Refund *refund)
{
  struct TALER_DenominationHashP denom_hash;
  struct RefundContext rctx = {
    .refund = refund
  };

  if (GNUNET_OK !=
      TALER_merchant_refund_verify (&refund->coin.coin_pub,
                                    &refund->details.h_contract_terms,
                                    refund->details.rtransaction_id,
                                    &refund->details.refund_amount,
                                    &refund->details.merchant_pub,
                                    &refund->details.merchant_sig))
  {
    TALER_LOG_WARNING ("Invalid signature on refund request\n");
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_FORBIDDEN,
                                       TALER_EC_EXCHANGE_REFUND_MERCHANT_SIGNATURE_INVALID,
                                       NULL);
  }

  /* Fetch the coin's denomination (hash) */
  {
    enum GNUNET_DB_QueryStatus qs;

    qs = TEH_plugin->get_coin_denomination (TEH_plugin->cls,
                                            &refund->coin.coin_pub,
                                            &rctx.known_coin_id,
                                            &denom_hash);
    if (0 > qs)
    {
      MHD_RESULT res;
      char *dhs;

      GNUNET_break (GNUNET_DB_STATUS_HARD_ERROR == qs);
      dhs = GNUNET_STRINGS_data_to_string_alloc (&denom_hash,
                                                 sizeof (denom_hash));
      res = TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_NOT_FOUND,
                                        TALER_EC_EXCHANGE_REFUND_COIN_NOT_FOUND,
                                        dhs);
      GNUNET_free (dhs);
      return res;
    }
  }

  {
    /* Obtain information about the coin's denomination! */
    struct TEH_DenominationKey *dk;
    MHD_RESULT mret;

    dk = TEH_keys_denomination_by_hash (&denom_hash,
                                        connection,
                                        &mret);
    if (NULL == dk)
    {
      /* DKI not found, but we do have a coin with this DK in our database;
         not good... */
      GNUNET_break (0);
      return mret;
    }
    refund->details.refund_fee = dk->meta.fees.refund;
    rctx.deposit_fee = dk->meta.fees.deposit;
  }

  /* Finally run the actual transaction logic */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "run refund",
                                TEH_MT_OTHER,
                                &mhd_ret,
                                &refund_transaction,
                                &rctx))
    {
      return mhd_ret;
    }
  }
  return reply_refund_success (connection,
                               &refund->coin.coin_pub,
                               &refund->details);
}


/**
 * Handle a "/coins/$COIN_PUB/refund" request.  Parses the JSON, and, if
 * successful, passes the JSON data to #verify_and_execute_refund() to further
 * check the details of the operation specified.  If everything checks out,
 * this will ultimately lead to the refund being executed, or rejected.
 *
 * @param connection the MHD connection to handle
 * @param coin_pub public key of the coin
 * @param root uploaded JSON data
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_refund (struct MHD_Connection *connection,
                    const struct TALER_CoinSpendPublicKeyP *coin_pub,
                    const json_t *root)
{
  struct TALER_EXCHANGEDB_Refund refund = {
    .details.refund_fee.currency = {0}                                        /* set to invalid, just to be sure */
  };
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("refund_amount",
                            TEH_currency,
                            &refund.details.refund_amount),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &refund.details.h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                 &refund.details.merchant_pub),
    GNUNET_JSON_spec_uint64 ("rtransaction_id",
                             &refund.details.rtransaction_id),
    GNUNET_JSON_spec_fixed_auto ("merchant_sig",
                                 &refund.details.merchant_sig),
    GNUNET_JSON_spec_end ()
  };

  refund.coin.coin_pub = *coin_pub;
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
                                     root,
                                     spec);
    if (GNUNET_SYSERR == res)
      return MHD_NO; /* hard failure */
    if (GNUNET_NO == res)
      return MHD_YES; /* failure */
  }
  {
    MHD_RESULT res;

    res = verify_and_execute_refund (connection,
                                     &refund);
    GNUNET_JSON_parse_free (spec);
    return res;
  }
}


/* end of taler-exchange-httpd_refund.c */
