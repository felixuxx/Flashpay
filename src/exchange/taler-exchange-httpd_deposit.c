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
 * @param h_extensions hash of applicable extensions
 * @param h_contract_terms hash of contract details
 * @param exchange_timestamp exchange's timestamp
 * @param refund_deadline until when this deposit be refunded
 * @param wire_deadline until when will the exchange wire the funds
 * @param merchant merchant public key
 * @param amount_without_fee fraction of coin value to deposit, without the fee
 * @return MHD result code
 */
static MHD_RESULT
reply_deposit_success (
  struct MHD_Connection *connection,
  const struct TALER_CoinSpendPublicKeyP *coin_pub,
  const struct TALER_MerchantWireHashP *h_wire,
  const struct TALER_ExtensionContractHashP *h_extensions,
  const struct TALER_PrivateContractHashP *h_contract_terms,
  struct GNUNET_TIME_Timestamp exchange_timestamp,
  struct GNUNET_TIME_Timestamp refund_deadline,
  struct GNUNET_TIME_Timestamp wire_deadline,
  const struct TALER_MerchantPublicKeyP *merchant,
  const struct TALER_Amount *amount_without_fee)
{
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;
  enum TALER_ErrorCode ec;

  if (TALER_EC_NONE !=
      (ec = TALER_exchange_online_deposit_confirmation_sign (
         &TEH_keys_exchange_sign_,
         h_contract_terms,
         h_wire,
         h_extensions,
         exchange_timestamp,
         wire_deadline,
         refund_deadline,
         amount_without_fee,
         coin_pub,
         merchant,
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
    GNUNET_JSON_pack_timestamp ("exchange_timestamp",
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
   * Possibly updated by the transaction if the
   * request is idempotent (was repeated).
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * Hash of the payto URI.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Row of of the coin in the known_coins table.
   */
  uint64_t known_coin_id;

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
  enum GNUNET_DB_QueryStatus qs;
  bool balance_ok;
  bool in_conflict;

  qs = TEH_make_coin_known (&dc->deposit->coin,
                            connection,
                            &dc->known_coin_id,
                            mhd_ret);
  if (qs < 0)
    return qs;
  qs = TEH_plugin->do_deposit (TEH_plugin->cls,
                               dc->deposit,
                               dc->known_coin_id,
                               &dc->h_payto,
                               false, /* FIXME-OEC: extension blocked */
                               &dc->exchange_timestamp,
                               &balance_ok,
                               &in_conflict);
  if (qs < 0)
  {
    if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
      return qs;
    TALER_LOG_WARNING ("Failed to store /deposit information in database\n");
    *mhd_ret = TALER_MHD_reply_with_error (connection,
                                           MHD_HTTP_INTERNAL_SERVER_ERROR,
                                           TALER_EC_GENERIC_DB_STORE_FAILED,
                                           "deposit");
    return qs;
  }
  if (in_conflict)
  {
    /* FIXME: conficting contract != insufficient funds */
    *mhd_ret
      = TEH_RESPONSE_reply_coin_insufficient_funds (
          connection,
          TALER_EC_EXCHANGE_DEPOSIT_CONFLICTING_CONTRACT,
          &dc->deposit->coin.denom_pub_hash,
          &dc->deposit->coin.coin_pub);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! balance_ok)
  {
    *mhd_ret
      = TEH_RESPONSE_reply_coin_insufficient_funds (
          connection,
          TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS,
          &dc->deposit->coin.denom_pub_hash,
          &dc->deposit->coin.coin_pub);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  TEH_METRICS_num_success[TEH_MT_SUCCESS_DEPOSIT]++;
  return qs;
}


MHD_RESULT
TEH_handler_deposit (struct MHD_Connection *connection,
                     const struct TALER_CoinSpendPublicKeyP *coin_pub,
                     const json_t *root)
{
  struct DepositContext dc;
  struct TALER_EXCHANGEDB_Deposit deposit;
  const char *payto_uri;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("merchant_payto_uri",
                             &payto_uri),
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
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &deposit.coin.h_age_commitment),
      &deposit.coin.no_age_commitment),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &deposit.csig),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &deposit.timestamp),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_timestamp ("refund_deadline",
                                  &deposit.refund_deadline),
      NULL),
    GNUNET_JSON_spec_timestamp ("wire_transfer_deadline",
                                &deposit.wire_deadline),
    GNUNET_JSON_spec_end ()
  };
  struct TALER_MerchantWireHashP h_wire;

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

    emsg = TALER_payto_validate (payto_uri);
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
  if (GNUNET_TIME_timestamp_cmp (deposit.refund_deadline,
                                 >,
                                 deposit.wire_deadline))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_DEPOSIT_REFUND_DEADLINE_AFTER_WIRE_DEADLINE,
                                       NULL);
  }
  if (GNUNET_TIME_absolute_is_never (deposit.wire_deadline.abs_time))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_DEPOSIT_WIRE_DEADLINE_IS_NEVER,
                                       NULL);
  }
  deposit.receiver_wire_account = (char *) payto_uri;
  TALER_payto_hash (payto_uri,
                    &dc.h_payto);
  TALER_merchant_wire_signature_hash (payto_uri,
                                      &deposit.wire_salt,
                                      &h_wire);
  dc.deposit = &deposit;

  /* new deposit */
  dc.exchange_timestamp = GNUNET_TIME_timestamp_get ();
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
    if (0 > TALER_amount_cmp (&dk->meta.value,
                              &deposit.amount_with_fee))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_GENERIC_AMOUNT_EXCEEDS_DENOMINATION_VALUE,
                                         NULL);
    }
    if (GNUNET_TIME_absolute_is_past (dk->meta.expire_deposit.abs_time))
    {
      /* This denomination is past the expiration time for deposits */
      GNUNET_JSON_parse_free (spec);
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        connection,
        &deposit.coin.denom_pub_hash,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
        "DEPOSIT");
    }
    if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
    {
      /* This denomination is not yet valid */
      GNUNET_JSON_parse_free (spec);
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        connection,
        &deposit.coin.denom_pub_hash,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
        "DEPOSIT");
    }
    if (dk->recoup_possible)
    {
      /* This denomination has been revoked */
      GNUNET_JSON_parse_free (spec);
      return TEH_RESPONSE_reply_expired_denom_pub_hash (
        connection,
        &deposit.coin.denom_pub_hash,
        TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
        "DEPOSIT");
    }
    if (dk->denom_pub.cipher != deposit.coin.denom_sig.cipher)
    {
      /* denomination cipher and denomination signature cipher not the same */
      GNUNET_JSON_parse_free (spec);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH,
                                         NULL);
    }

    deposit.deposit_fee = dk->meta.fees.deposit;
    /* check coin signature */
    switch (dk->denom_pub.cipher)
    {
    case TALER_DENOMINATION_RSA:
      TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_RSA]++;
      break;
    case TALER_DENOMINATION_CS:
      TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_CS]++;
      break;
    default:
      break;
    }
    if (GNUNET_YES !=
        TALER_test_coin_valid (&deposit.coin,
                               &dk->denom_pub))
    {
      TALER_LOG_WARNING ("Invalid coin passed for /deposit\n");
      GNUNET_JSON_parse_free (spec);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_FORBIDDEN,
                                         TALER_EC_EXCHANGE_DENOMINATION_SIGNATURE_INVALID,
                                         NULL);
    }
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

  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_wallet_deposit_verify (&deposit.amount_with_fee,
                                   &deposit.deposit_fee,
                                   &h_wire,
                                   &deposit.h_contract_terms,
                                   &deposit.coin.h_age_commitment,
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
                                       MHD_HTTP_FORBIDDEN,
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

  /* execute transaction */
  {
    MHD_RESULT mhd_ret;

    if (GNUNET_OK !=
        TEH_DB_run_transaction (connection,
                                "execute deposit",
                                TEH_MT_REQUEST_DEPOSIT,
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
                                 &h_wire,
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
