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
 * @file taler-exchange-httpd_batch-deposit.c
 * @brief Handle /batch-deposit requests; parses the POST and JSON and
 *        verifies the coin signatures before handing things off
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
 * Closure for #batch_deposit_transaction.
 */
struct BatchDepositContext
{
  /**
   * Information about the individual coin deposits.
   */
  struct TALER_EXCHANGEDB_Deposit *deposits;

  /**
   * Our timestamp (when we received the request).
   * Possibly updated by the transaction if the
   * request is idempotent (was repeated).
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * Hash over the proposal data between merchant and customer
   * (remains unknown to the Exchange).
   */
  struct TALER_PrivateContractHashP h_contract_terms;

  /**
   * Public key of the merchant.  Enables later identification
   * of the merchant in case of a need to rollback transactions.
   */
  struct TALER_MerchantPublicKeyP merchant_pub;

  /**
   * Salt used by the merchant to compute @e h_wire.
   */
  struct TALER_WireSaltP wire_salt;

  /**
   * Hash over the wire details (with @e wire_salt).
   */
  struct TALER_MerchantWireHashP h_wire;

  /**
   * Hash of the payto URI.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Information about the receiver for executing the transaction.  URI in
   * payto://-format.
   */
  const char *payto_uri;

  /**
   * Additional details for extensions relevant for this
   * deposit operation, possibly NULL!
   */
  json_t *extension_details;

  /**
   * Hash over @e extension_details.
   */
  struct TALER_ExtensionContractHashP h_extensions;

  /**
   * Time when this request was generated.  Used, for example, to
   * assess when (roughly) the income was achieved for tax purposes.
   * Note that the Exchange will only check that the timestamp is not "too
   * far" into the future (i.e. several days).  The fact that the
   * timestamp falls within the validity period of the coin's
   * denomination key is irrelevant for the validity of the deposit
   * request, as obviously the customer and merchant could conspire to
   * set any timestamp.  Also, the Exchange must accept very old deposit
   * requests, as the merchant might have been unable to transmit the
   * deposit request in a timely fashion (so back-dating is not
   * prevented).
   */
  struct GNUNET_TIME_Timestamp timestamp;

  /**
   * How much time does the merchant have to issue a refund request?
   * Zero if refunds are not allowed.  After this time, the coin
   * cannot be refunded.
   */
  struct GNUNET_TIME_Timestamp refund_deadline;

  /**
   * How much time does the merchant have to execute the wire transfer?
   * This time is advisory for aggregating transactions, not a hard
   * constraint (as the merchant can theoretically pick any time,
   * including one in the past).
   */
  struct GNUNET_TIME_Timestamp wire_deadline;

  /**
   * Number of coins in the batch.
   */
  unsigned int num_coins;
};


/**
 * Send confirmation of batch deposit success to client.  This function will
 * create a signed message affirming the given information and return it to
 * the client.  By this, the exchange affirms that the coins had sufficient
 * (residual) value for the specified transaction and that it will execute the
 * requested batch deposit operation with the given wiring details.
 *
 * @param connection connection to the client
 * @param bdc information about the batch deposit
 * @return MHD result code
 */
static MHD_RESULT
reply_batch_deposit_success (
  struct MHD_Connection *connection,
  const struct BatchDepositContext *bdc)
{
  json_t *arr;
  struct TALER_ExchangePublicKeyP pub;

again:
  arr = json_array ();
  GNUNET_assert (NULL != arr);
  for (unsigned int i = 0; i<bdc->num_coins; i++)
  {
    const struct TALER_EXCHANGEDB_Deposit *deposit = &bdc->deposits[i];
    struct TALER_ExchangePublicKeyP pubi;
    struct TALER_ExchangeSignatureP sig;
    enum TALER_ErrorCode ec;
    struct TALER_Amount amount_without_fee;

    GNUNET_assert (0 <=
                   TALER_amount_subtract (&amount_without_fee,
                                          &deposit->amount_with_fee,
                                          &deposit->deposit_fee));
    if (TALER_EC_NONE !=
        (ec = TALER_exchange_online_deposit_confirmation_sign (
           &TEH_keys_exchange_sign_,
           &bdc->h_contract_terms,
           &bdc->h_wire,
           &bdc->h_extensions,
           bdc->exchange_timestamp,
           bdc->wire_deadline,
           bdc->refund_deadline,
           &amount_without_fee,
           &deposit->coin.coin_pub,
           &bdc->merchant_pub,
           &pubi,
           &sig)))
    {
      GNUNET_break (0);
      return TALER_MHD_reply_with_ec (connection,
                                      ec,
                                      NULL);
    }
    if (0 == i)
      pub = pubi;
    if (0 !=
        GNUNET_memcmp (&pub,
                       &pubi))
    {
      /* note: in the future, maybe have batch
         sign API to avoid having to handle
         key rollover... */
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Exchange public key changed during batch deposit, trying again\n");
      json_decref (arr);
      goto again;
    }
    GNUNET_assert (
      0 ==
      json_array_append_new (arr,
                             GNUNET_JSON_PACK (
                               GNUNET_JSON_pack_data_auto (
                                 "exchange_sig",
                                 &sig))));
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_timestamp ("exchange_timestamp",
                                bdc->exchange_timestamp),
    GNUNET_JSON_pack_data_auto (
      "exchange_pub",
      &pub),
    GNUNET_JSON_pack_array_steal ("exchange_sigs",
                                  arr));
}


/**
 * Execute database transaction for /batch-deposit.  Runs the transaction
 * logic; IF it returns a non-error code, the transaction logic MUST
 * NOT queue a MHD response.  IF it returns an hard error, the
 * transaction logic MUST queue a MHD response and set @a mhd_ret.  IF
 * it returns the soft error code, the function MAY be called again to
 * retry and MUST not queue a MHD response.
 *
 * @param cls a `struct BatchDepositContext`
 * @param connection MHD request context
 * @param[out] mhd_ret set to MHD status on error
 * @return transaction status
 */
static enum GNUNET_DB_QueryStatus
batch_deposit_transaction (void *cls,
                           struct MHD_Connection *connection,
                           MHD_RESULT *mhd_ret)
{
  struct BatchDepositContext *dc = cls;
  enum GNUNET_DB_QueryStatus qs;
  bool balance_ok;
  bool in_conflict;

  for (unsigned int i = 0; i<dc->num_coins; i++)
  {
    const struct TALER_EXCHANGEDB_Deposit *deposit = &dc->deposits[i];
    uint64_t known_coin_id;

    qs = TEH_make_coin_known (&deposit->coin,
                              connection,
                              &known_coin_id,
                              mhd_ret);
    if (qs < 0)
      return qs;
    qs = TEH_plugin->do_deposit (TEH_plugin->cls,
                                 deposit,
                                 known_coin_id,
                                 &dc->h_payto,
                                 false, /* FIXME-OEC: #7270 extension blocked */
                                 &dc->exchange_timestamp,
                                 &balance_ok,
                                 &in_conflict);
    if (qs < 0)
    {
      if (GNUNET_DB_STATUS_SOFT_ERROR == qs)
        return qs;
      TALER_LOG_WARNING (
        "Failed to store /batch-deposit information in database\n");
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "batch-deposit");
      return qs;
    }
    if (in_conflict)
    {
      /* FIXME: #7267 conficting contract != insufficient funds */
      *mhd_ret
        = TEH_RESPONSE_reply_coin_insufficient_funds (
            connection,
            TALER_EC_EXCHANGE_DEPOSIT_CONFLICTING_CONTRACT,
            &deposit->coin.denom_pub_hash,
            &deposit->coin.coin_pub);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
    if (! balance_ok)
    {
      *mhd_ret
        = TEH_RESPONSE_reply_coin_insufficient_funds (
            connection,
            TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS,
            &deposit->coin.denom_pub_hash,
            &deposit->coin.coin_pub);
      return GNUNET_DB_STATUS_HARD_ERROR;
    }
  }
  TEH_METRICS_num_success[TEH_MT_SUCCESS_DEPOSIT]++;
  return qs;
}


/**
 * Parse per-coin deposit information from @a jcoin
 * into @a deposit. Fill in generic information from
 * @a ctx.
 *
 * @param connection connection we are handling
 * @param jcoin coin data to parse
 * @param dc overall batch deposit context information to use
 * @param[out] deposit where to store the result
 * @return #GNUNET_OK on success, #GNUNET_NO if an error was returned,
 *         #GNUNET_SYSERR on failure and no error could be returned
 */
static enum GNUNET_GenericReturnValue
parse_coin (struct MHD_Connection *connection,
            json_t *jcoin,
            const struct BatchDepositContext *dc,
            struct TALER_EXCHANGEDB_Deposit *deposit)
{
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("contribution",
                            TEH_currency,
                            &deposit->amount_with_fee),
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &deposit->coin.denom_pub_hash),
    TALER_JSON_spec_denom_sig ("ub_sig",
                               &deposit->coin.denom_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 &deposit->coin.coin_pub),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &deposit->coin.h_age_commitment),
      &deposit->coin.no_age_commitment),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &deposit->csig),
    GNUNET_JSON_spec_end ()
  };
  enum GNUNET_GenericReturnValue res;

  if (GNUNET_OK !=
      (res = TALER_MHD_parse_json_data (connection,
                                        jcoin,
                                        spec)))
    return res;
  /* check denomination exists and is valid */
  {
    struct TEH_DenominationKey *dk;
    MHD_RESULT mret;

    dk = TEH_keys_denomination_by_hash (&deposit->coin.denom_pub_hash,
                                        connection,
                                        &mret);
    if (NULL == dk)
    {
      GNUNET_JSON_parse_free (spec);
      return mret;
    }
    if (0 > TALER_amount_cmp (&dk->meta.value,
                              &deposit->amount_with_fee))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_BAD_REQUEST,
                                          TALER_EC_EXCHANGE_GENERIC_AMOUNT_EXCEEDS_DENOMINATION_VALUE,
                                          NULL))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
    if (GNUNET_TIME_absolute_is_past (dk->meta.expire_deposit.abs_time))
    {
      /* This denomination is past the expiration time for deposits */
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TEH_RESPONSE_reply_expired_denom_pub_hash (
                connection,
                &deposit->coin.denom_pub_hash,
                TALER_EC_EXCHANGE_GENERIC_DENOMINATION_EXPIRED,
                "DEPOSIT"))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
    if (GNUNET_TIME_absolute_is_future (dk->meta.start.abs_time))
    {
      /* This denomination is not yet valid */
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TEH_RESPONSE_reply_expired_denom_pub_hash (
                connection,
                &deposit->coin.denom_pub_hash,
                TALER_EC_EXCHANGE_GENERIC_DENOMINATION_VALIDITY_IN_FUTURE,
                "DEPOSIT"))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
    if (dk->recoup_possible)
    {
      /* This denomination has been revoked */
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TEH_RESPONSE_reply_expired_denom_pub_hash (
                connection,
                &deposit->coin.denom_pub_hash,
                TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
                "DEPOSIT"))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
    if (dk->denom_pub.cipher != deposit->coin.denom_sig.cipher)
    {
      /* denomination cipher and denomination signature cipher not the same */
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_BAD_REQUEST,
                                          TALER_EC_EXCHANGE_GENERIC_CIPHER_MISMATCH,
                                          NULL))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }

    deposit->deposit_fee = dk->meta.fees.deposit;
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
        TALER_test_coin_valid (&deposit->coin,
                               &dk->denom_pub))
    {
      TALER_LOG_WARNING ("Invalid coin passed for /batch-deposit\n");
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES ==
              TALER_MHD_reply_with_error (connection,
                                          MHD_HTTP_FORBIDDEN,
                                          TALER_EC_EXCHANGE_DENOMINATION_SIGNATURE_INVALID,
                                          NULL))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
  }
  if (0 < TALER_amount_cmp (&deposit->deposit_fee,
                            &deposit->amount_with_fee))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_BAD_REQUEST,
                                        TALER_EC_EXCHANGE_DEPOSIT_NEGATIVE_VALUE_AFTER_FEE,
                                        NULL))
        ? GNUNET_NO
        : GNUNET_SYSERR;
  }

  TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_EDDSA]++;
  if (GNUNET_OK !=
      TALER_wallet_deposit_verify (&deposit->amount_with_fee,
                                   &deposit->deposit_fee,
                                   &dc->h_wire,
                                   &dc->h_contract_terms,
                                   &deposit->coin.h_age_commitment,
                                   &dc->h_extensions,
                                   &deposit->coin.denom_pub_hash,
                                   dc->timestamp,
                                   &dc->merchant_pub,
                                   dc->refund_deadline,
                                   &deposit->coin.coin_pub,
                                   &deposit->csig))
  {
    TALER_LOG_WARNING ("Invalid signature on /batch-deposit request\n");
    GNUNET_JSON_parse_free (spec);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_FORBIDDEN,
                                        TALER_EC_EXCHANGE_DEPOSIT_COIN_SIGNATURE_INVALID,
                                        NULL))
      ? GNUNET_NO
      : GNUNET_SYSERR;
  }
  deposit->merchant_pub = dc->merchant_pub;
  deposit->h_contract_terms = dc->h_contract_terms;
  deposit->wire_salt = dc->wire_salt;
  deposit->receiver_wire_account = (char *) dc->payto_uri;
  /* FIXME-OEC: #7270 should NOT insert the extension details N times,
     but rather insert them ONCE and then per-coin only use
     the resulting extension UUID/serial; so the data structure
     here should be changed once we look at extensions in earnest.  */
  deposit->extension_details = dc->extension_details;
  deposit->timestamp = dc->timestamp;
  deposit->refund_deadline = dc->refund_deadline;
  deposit->wire_deadline = dc->wire_deadline;
  return GNUNET_OK;
}


MHD_RESULT
TEH_handler_batch_deposit (struct TEH_RequestContext *rc,
                           const json_t *root,
                           const char *const args[])
{
  struct MHD_Connection *connection = rc->connection;
  struct BatchDepositContext dc;
  json_t *coins;
  bool no_refund_deadline = true;
  bool no_extensions = true;
  struct GNUNET_JSON_Specification spec[] = {
    GNUNET_JSON_spec_string ("merchant_payto_uri",
                             &dc.payto_uri),
    GNUNET_JSON_spec_fixed_auto ("wire_salt",
                                 &dc.wire_salt),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                 &dc.merchant_pub),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &dc.h_contract_terms),
    GNUNET_JSON_spec_json ("coins",
                           &coins),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_json ("extension_details",
                             &dc.extension_details),
      &no_extensions),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &dc.timestamp),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_timestamp ("refund_deadline",
                                  &dc.refund_deadline),
      &no_refund_deadline),
    GNUNET_JSON_spec_timestamp ("wire_transfer_deadline",
                                &dc.wire_deadline),
    GNUNET_JSON_spec_end ()
  };
  enum GNUNET_GenericReturnValue res;

  memset (&dc,
          0,
          sizeof (dc));
  res = TALER_MHD_parse_json_data (connection,
                                   root,
                                   spec);
  if (GNUNET_SYSERR == res)
  {
    GNUNET_break (0);
    return MHD_NO;   /* hard failure */
  }
  if (GNUNET_NO == res)
  {
    GNUNET_break_op (0);
    return MHD_YES;   /* failure */
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
  if (GNUNET_TIME_timestamp_cmp (dc.refund_deadline,
                                 >,
                                 dc.wire_deadline))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_DEPOSIT_REFUND_DEADLINE_AFTER_WIRE_DEADLINE,
                                       NULL);
  }
  if (GNUNET_TIME_absolute_is_never (dc.wire_deadline.abs_time))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_DEPOSIT_WIRE_DEADLINE_IS_NEVER,
                                       NULL);
  }
  TALER_payto_hash (dc.payto_uri,
                    &dc.h_payto);
  TALER_merchant_wire_signature_hash (dc.payto_uri,
                                      &dc.wire_salt,
                                      &dc.h_wire);
  /* FIXME-OEC: #7270 hash actual extension JSON object here */
  // if (! no_extensions)
  memset (&dc.h_extensions,
          0,
          sizeof (dc.h_extensions));
  dc.num_coins = json_array_size (coins);
  if (0 == dc.num_coins)
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       "coins");
  }
  if (TALER_MAX_FRESH_COINS < dc.num_coins)
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       "coins");
  }
  dc.deposits = GNUNET_new_array (dc.num_coins,
                                  struct TALER_EXCHANGEDB_Deposit);
  for (unsigned int i = 0; i<dc.num_coins; i++)
  {
    if (GNUNET_OK !=
        (res = parse_coin (connection,
                           json_array_get (coins,
                                           i),
                           &dc,
                           &dc.deposits[i])))
    {
      for (unsigned int j = 0; j<i; j++)
        TALER_denom_sig_free (&dc.deposits[j].coin.denom_sig);
      GNUNET_free (dc.deposits);
      GNUNET_JSON_parse_free (spec);
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
    }
  }

  dc.exchange_timestamp = GNUNET_TIME_timestamp_get ();
  if (GNUNET_SYSERR ==
      TEH_plugin->preflight (TEH_plugin->cls))
  {
    GNUNET_break (0);
    GNUNET_JSON_parse_free (spec);
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
                                "execute batch deposit",
                                TEH_MT_REQUEST_BATCH_DEPOSIT,
                                &mhd_ret,
                                &batch_deposit_transaction,
                                &dc))
    {
      GNUNET_JSON_parse_free (spec);
      for (unsigned int j = 0; j<dc.num_coins; j++)
        TALER_denom_sig_free (&dc.deposits[j].coin.denom_sig);
      GNUNET_free (dc.deposits);
      GNUNET_JSON_parse_free (spec);
      return mhd_ret;
    }
  }

  /* generate regular response */
  {
    MHD_RESULT res;

    res = reply_batch_deposit_success (connection,
                                       &dc);
    for (unsigned int j = 0; j<dc.num_coins; j++)
      TALER_denom_sig_free (&dc.deposits[j].coin.denom_sig);
    GNUNET_free (dc.deposits);
    GNUNET_JSON_parse_free (spec);
    return res;
  }
}


/* end of taler-exchange-httpd_batch-deposit.c */
