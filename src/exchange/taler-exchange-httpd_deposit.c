/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

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
 * @file taler-exchange-httpd_deposit.c
 * @brief Handle /deposit requests; parses the POST and JSON and
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
#include "taler-exchange-httpd_deposit.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_exchangedb_lib.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Send confirmation of deposit success to client.  This function
 * will create a signed message affirming the given information
 * and return it to the client.  By this, the exchange affirms that
 * the coin had sufficient (residual) value for the specified
 * transaction and that it will execute the requested deposit
 * operation with the given wiring details.
 *
 * @param connection connection to the client
 * @param coin_pub public key of the coin
 * @param h_wire hash of wire details
 * @param h_contract_terms hash of contract details
 * @param exchange_timestamp exchange's timestamp
 * @param refund_deadline until when this deposit be refunded
 * @param merchant merchant public key
 * @param amount_without_fee fraction of coin value to deposit, without the fee
 * @return MHD result code
 */
static MHD_RESULT
reply_deposit_success (struct MHD_Connection *connection,
                       const struct TALER_CoinSpendPublicKeyP *coin_pub,
                       const struct TALER_MerchantWireHash *h_wire,
                       const struct TALER_ExtensionContractHash *h_extensions,
                       const struct TALER_PrivateContractHash *h_contract_terms,
                       struct GNUNET_TIME_Absolute exchange_timestamp,
                       struct GNUNET_TIME_Absolute refund_deadline,
                       struct GNUNET_TIME_Absolute wire_deadline,
                       const struct TALER_MerchantPublicKeyP *merchant,
                       const struct TALER_Amount *amount_without_fee)
{
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  struct TALER_DepositConfirmationPS dc = {
    .purpose.purpose = htonl (TALER_SIGNATURE_EXCHANGE_CONFIRM_DEPOSIT),
    .purpose.size = htonl (sizeof (dc)),
    .h_contract_terms = *h_contract_terms,
    .h_wire = *h_wire,
    .exchange_timestamp = GNUNET_TIME_absolute_hton (exchange_timestamp),
    .refund_deadline = GNUNET_TIME_absolute_hton (refund_deadline),
    .wire_deadline = GNUNET_TIME_absolute_hton (wire_deadline),
    .coin_pub = *coin_pub,
    .merchant_pub = *merchant
  };
  enum TALER_ErrorCode ec;

  if (NULL != h_extensions)
    dc.h_extensions = *h_extensions;
  TALER_amount_hton (&dc.amount_without_fee,
                     amount_without_fee);
  if (TALER_EC_NONE !=
      (ec = TEH_keys_exchange_sign (&dc,
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
    GNUNET_JSON_pack_time_abs ("exchange_timestamp",
                               exchange_timestamp),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &sig),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &pub));
}


/**
 * Closure for #deposit_transaction.
 */
struct DepositContext
{
  /**
   * Information about the deposit request.
   */
  const struct TALER_EXCHANGEDB_Deposit *deposit;

  /**
   * Our timestamp (when we received the request).
   */
  struct GNUNET_TIME_Absolute exchange_timestamp;

  /**
   * Calculated hash over the wire details.
   */
  struct TALER_MerchantWireHash h_wire;

  /**
   * Value of the coin.
   */
  struct TALER_Amount value;

  /**
   * payto:// URI of the credited account.
   */
  const char *payto_uri;
};


/**
 * Execute database transaction for /deposit.  Runs the transaction
 * logic; IF it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls a `struct DepositContext`
 * @param connection MHD request context
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
deposit_transaction (void *cls,
                     struct MHD_Connection *connection,
                     MHD_RESULT *mhd_ret)
{
  struct DepositContext *dc = cls;
  const struct TALER_EXCHANGEDB_Deposit *deposit = dc->deposit;
  struct TALER_Amount spent;
  enum GNUNET_DB_QueryStatus qs;
  struct TALER_Amount deposit_fee;

  /* begin optimistically: assume this is a new deposit */
  qs = TEH_plugin->insert_deposit (TEH_plugin->cls,
                                   dc->exchange_timestamp,
                                   deposit);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    TALER_LOG_WARNING ("Failed to store /deposit information in database\n");
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_STORE_FAILED,
                                           NULL);
    return qs;
  }
  if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
  {
    /* Check for idempotency: did we get this request before? */
    qs = TEH_plugin->have_deposit (TEH_plugin->cls,
                                   deposit,
                                   &deposit_fee,
                                   &dc->exchange_timestamp);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_FETCH_FAILED,
                                             "have_deposit");
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (GNUNET_DB_STATUS_SUCCESS_NO_RESULTS == qs)
    {
      /* Conflict on insert, but record does not exist?
         That makes no sense. */
      GNUNET_break (0);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }

    {
      struct TALER_Amount amount_without_fee;

      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "/deposit replay, accepting again!\n");
      GNUNET_assert (0 <=
                     TALER_amount_subtract (&amount_without_fee,
                                            &deposit->amount_with_fee,
                                            &deposit_fee));
      *mhd_ret = reply_deposit_success (connection,
                                        &deposit->coin.coin_pub,
                                        &dc->h_wire,
                                        NULL /* h_extensions! */,
                                        &deposit->h_contract_terms,
                                        dc->exchange_timestamp,
                                        deposit->refund_deadline,
                                        deposit->wire_deadline,
                                        &deposit->merchant_pub,
                                        &amount_without_fee);
      /* Note: we return "hard error" to ensure the wrapper
         does not retry the transaction, and to also not generate
         a "fresh" response (as we would on "success") */
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }

  /* Start with zero cost, as we already added this melt transaction
     to the DB, so we will see it again during the queries below. */
  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &spent));

  return TEH_check_coin_balance (connection,
                                 &deposit->coin.coin_pub,
                                 &dc->value,
                                 &deposit->amount_with_fee,
                                 false, /* no need for recoup */
                                 false, /* no need for zombie */
                                 mhd_ret);
}


/**
 * Handle a "/coins/$COIN_PUB/deposit" request.  Parses the JSON, and, if
 * successful, passes the JSON data to #deposit_transaction() to
 * further check the details of the operation specified.  If everything checks
 * out, this will ultimately lead to the "/deposit" being executed, or
 * rejected.
 *
 * @param connection the MHD connection to handle
 * @param coin_pub public key of the coin
 * @param root uploaded JSON data
 * @return MHD result code
  */
MHD_RESULT
TEH_handler_deposit (struct MHD_Connection *connection,
                     const struct TALER_CoinSpendPublicKeyP *coin_pub,
                     const json_t *root)
{
  struct DepositContext dc;
  struct TALER_EXCHANGEDB_Deposit deposit;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("merchant_payto_uri",
                             &dc.payto_uri),
    GNUNET_JSON_spec_fixed_auto ("wire_salt",
                                 &deposit.wire_salt),
    TALER_JSON_spec_amount ("contribution",
                            TEH_currency,
                            &deposit.amount_with_fee),
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &deposit.coin.denom_pub_hash),
    TALER_JSON_spec_denom_sig ("ub_sig",
                               &deposit.coin.denom_sig),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                 &deposit.merchant_pub),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &deposit.h_contract_terms),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &deposit.csig),
    TALER_JSON_spec_absolute_time ("timestamp",
                                   &deposit.timestamp),
    GNUNET_JSON_spec_mark_optional (
      TALER_JSON_spec_absolute_time ("refund_deadline",
                                     &deposit.refund_deadline)),
    TALER_JSON_spec_absolute_time ("wire_transfer_deadline",
                                   &deposit.wire_deadline),
    GNUNET_JSON_spec_end ()
  };

  memset (&deposit,
          0,
          sizeof (deposit));
  deposit.coin.coin_pub = *coin_pub;
  {
    enum GNUNET_GenericReturnValue res;

    res = TALER_MHD_parse_json_data (connection,
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
  /* validate merchant's wire details (as far as we can) */
  {
    char *emsg;

    emsg = TALER_payto_validate (dc.payto_uri);
    if (NULL != emsg)
    {
      MHD_RESULT ret;

      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      ret = TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                        emsg);
      GNUNET_free (emsg);
      return ret;
    }
  }
  deposit.receiver_wire_account = (char *) dc.payto_uri;
  if (deposit.refund_deadline.abs_value_us > deposit.wire_deadline.abs_value_us)
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_DEPOSIT_REFUND_DEADLINE_AFTER_WIRE_DEADLINE,
                                       NULL);
  }
  TALER_merchant_wire_signature_hash (dc.payto_uri,
                                      &deposit.wire_salt,
                                      &dc.h_wire);
  dc.deposit = &deposit;

  /* new deposit */
  dc.exchange_timestamp = GNUNET_TIME_absolute_get ();
  (void) GNUNET_TIME_round_abs (&dc.exchange_timestamp);
  /* check denomination exists and is valid */
  {
    struct TEH_DenominationKey *dk;
    MHD_RESULT mret;

    dk = TEH_keys_denomination_by_hash (&deposit.coin.denom_pub_hash,
                                        connection,
                                        &mret);
    if (NULL == dk)
    {
      GNUNET_JSON_parse_free (spec);
      return mret;
    }
    if (GNUNET_TIME_absolute_is_past (dk->meta.expire_deposit))
    {
      /* This denomination is past the expiration time for deposits */
      struct GNUNET_TIME_Absolute now;

      now = GNUNET_TIME_absolute_get ();
      (void) GNUNET_TIME_round_abs (&now);
      GNUNET_JSON_parse_free (spec);
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        connection,
        &deposit.coin.denom_pub_hash,
        now,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
        "DEPOSIT");
    }
    if (GNUNET_TIME_absolute_is_future (dk->meta.start))
    {
      /* This denomination is not yet valid */
      struct GNUNET_TIME_Absolute now;

      now = GNUNET_TIME_absolute_get ();
      (void) GNUNET_TIME_round_abs (&now);
      GNUNET_JSON_parse_free (spec);
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        connection,
        &deposit.coin.denom_pub_hash,
        now,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
        "DEPOSIT");
    }
    if (dk->recoup_possible)
    {
      struct GNUNET_TIME_Absolute now;

      now = GNUNET_TIME_absolute_get ();
      (void) GNUNET_TIME_round_abs (&now);
      /* This denomination has been revoked */
      GNUNET_JSON_parse_free (spec);
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        connection,
        &deposit.coin.denom_pub_hash,
        now,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
        "DEPOSIT");
    }

    deposit.deposit_fee = dk->meta.fee_deposit;
    /* check coin signature */
    if (GNUNET_YES !=
        TALER_test_coin_valid (&deposit.coin,
                               &dk->denom_pub))
    {
      TALER_LOG_WARNING ("Invalid coin passed for /deposit\n");
      GNUNET_JSON_parse_free (spec);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_UNAUTHORIZED,
                                         TALER_EC_EXCHANGE_DENOMINATION_SIGNATURE_INVALID,
                                         NULL);
    }
    dc.value = dk->meta.value;
  }
  if (0 < TALER_amount_cmp (&deposit.deposit_fee,
                            &deposit.amount_with_fee))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_DEPOSIT_NEGATIVE_VALUE_AFTER_FEE,
                                       NULL);
  }

  if (GNUNET_OK !=
      TALER_wallet_deposit_verify (&deposit.amount_with_fee,
                                   &deposit.deposit_fee,
                                   &dc.h_wire,
                                   &deposit.h_contract_terms,
                                   NULL /* h_extensions! */,
                                   &deposit.coin.denom_pub_hash,
                                   deposit.timestamp,
                                   &deposit.merchant_pub,
                                   deposit.refund_deadline,
                                   &deposit.coin.coin_pub,
                                   &deposit.csig))
  {
    TALER_LOG_WARNING ("Invalid signature on /deposit request\n");
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_UNAUTHORIZED,
                                       TALER_EC_EXCHANGE_DEPOSIT_COIN_SIGNATURE_INVALID,
                                       NULL);
  }

  if (GNUNET_SYSERR ==
      TEH_plugin->preflight (TEH_plugin->cls))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_INTERNAL_SERVER_ERROR,
                                       TALER_EC_GENERIC_DB_START_FAILED,
                                       "preflight failure");
  }

  {
    MHD_RESULT mhd_ret = MHD_NO;
    enum GNUNET_DB_QueryStatus qs;

    /* make sure coin is 'known' in database */
    qs = TEH_make_coin_known (&deposit.coin,
                              connection,
                              &mhd_ret);
    /* no transaction => no serialization failures should be possible */
    GNUNET_break (GNUNET_DB_STATUS_SOFT_ERROR != qs);
    if (qs < 0)
      return mhd_ret;
  }


  /* execute transaction */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "execute deposit",
                                TEH_MT_DEPOSIT,
                                &mhd_ret,
                                &deposit_transaction,
                                &dc))
    {
      GNUNET_JSON_parse_free (spec);
      return mhd_ret;
    }
  }

  /* generate regular response */
  {
    struct TALER_Amount amount_without_fee;
    MHD_RESULT res;

    GNUNET_assert (0 <=
                   TALER_amount_subtract (&amount_without_fee,
                                          &deposit.amount_with_fee,
                                          &deposit.deposit_fee));
    res = reply_deposit_success (connection,
                                 &deposit.coin.coin_pub,
                                 &dc.h_wire,
                                 NULL /* h_extensions! */,
                                 &deposit.h_contract_terms,
                                 dc.exchange_timestamp,
                                 deposit.refund_deadline,
                                 deposit.wire_deadline,
                                 &deposit.merchant_pub,
                                 &amount_without_fee);
    GNUNET_JSON_parse_free (spec);
    return res;
  }
}


/* end of taler-exchange-httpd_deposit.c */
