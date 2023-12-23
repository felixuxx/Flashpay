/*
  This file is part of TALER
  Copyright (C) 2014-2023 Taler Systems SA

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
#include "taler_extensions_policy.h"
#include "taler_json_lib.h"
#include "taler_mhd_lib.h"
#include "taler-exchange-httpd_batch-deposit.h"
#include "taler-exchange-httpd_responses.h"
#include "taler_exchangedb_lib.h"
#include "taler-exchange-httpd_keys.h"


/**
 * Closure for #batch_deposit_transaction.
 */
struct BatchDepositContext
{

  /**
   * Array with the individual coin deposit fees.
   */
  struct TALER_Amount *deposit_fees;

  /**
   * Our timestamp (when we received the request).
   * Possibly updated by the transaction if the
   * request is idempotent (was repeated).
   */
  struct GNUNET_TIME_Timestamp exchange_timestamp;

  /**
   * Details about the batch deposit operation.
   */
  struct TALER_EXCHANGEDB_BatchDeposit bd;


  /**
   * Total amount that is accumulated with this deposit,
   * without fee.
   */
  struct TALER_Amount accumulated_total_without_fee;

  /**
   * True, if no policy was present in the request. Then
   * @e policy_json is NULL and @e h_policy will be all zero.
   */
  bool has_no_policy;

  /**
   * Additional details for policy extension relevant for this
   * deposit operation, possibly NULL!
   */
  json_t *policy_json;

  /**
   * If @e policy_json was present, the corresponding policy extension
   * calculates these details.  These will be persisted in the policy_details
   * table.
   */
  struct TALER_PolicyDetails policy_details;

  /**
   * Hash over @e policy_details, might be all zero
   */
  struct TALER_ExtensionPolicyHashP h_policy;

  /**
   * Hash over the merchant's payto://-URI with the wire salt.
   */
  struct TALER_MerchantWireHashP h_wire;

  /**
   * When @e policy_details are persisted, this contains the id of the record
   * in the policy_details table.
   */
  uint64_t policy_details_serial_id;

};


/**
 * Send confirmation of batch deposit success to client.  This function will
 * create a signed message affirming the given information and return it to
 * the client.  By this, the exchange affirms that the coins had sufficient
 * (residual) value for the specified transaction and that it will execute the
 * requested batch deposit operation with the given wiring details.
 *
 * @param connection connection to the client
 * @param dc information about the batch deposit
 * @return MHD result code
 */
static MHD_RESULT
reply_batch_deposit_success (
  struct MHD_Connection *connection,
  const struct BatchDepositContext *dc)
{
  const struct TALER_EXCHANGEDB_BatchDeposit *bd = &dc->bd;
  const struct TALER_CoinSpendSignatureP *csigs[GNUNET_NZL (bd->num_cdis)];
  enum TALER_ErrorCode ec;
  struct TALER_ExchangePublicKeyP pub;
  struct TALER_ExchangeSignatureP sig;

  for (unsigned int i = 0; i<bd->num_cdis; i++)
    csigs[i] = &bd->cdis[i].csig;
  if (TALER_EC_NONE !=
      (ec = TALER_exchange_online_deposit_confirmation_sign (
         &TEH_keys_exchange_sign_,
         &bd->h_contract_terms,
         &dc->h_wire,
         dc->has_no_policy ? NULL : &dc->h_policy,
         dc->exchange_timestamp,
         bd->wire_deadline,
         bd->refund_deadline,
         &dc->accumulated_total_without_fee,
         bd->num_cdis,
         csigs,
         &dc->bd.merchant_pub,
         &pub,
         &sig)))
  {
    GNUNET_break (0);
    return TALER_MHD_reply_with_ec (connection,
                                    ec,
                                    NULL);
  }
  return TALER_MHD_REPLY_JSON_PACK (
    connection,
    MHD_HTTP_OK,
    GNUNET_JSON_pack_timestamp ("exchange_timestamp",
                                dc->exchange_timestamp),
    GNUNET_JSON_pack_data_auto ("exchange_pub",
                                &pub),
    GNUNET_JSON_pack_data_auto ("exchange_sig",
                                &sig));
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
  const struct TALER_EXCHANGEDB_BatchDeposit *bd = &dc->bd;
  enum GNUNET_DB_QueryStatus qs = GNUNET_DB_STATUS_HARD_ERROR;
  uint32_t bad_balance_coin_index = UINT32_MAX;
  bool balance_ok;
  bool in_conflict;

  /* If the deposit has a policy associated to it, persist it.  This will
   * insert or update the record. */
  if (! dc->has_no_policy)
  {
    qs = TEH_plugin->persist_policy_details (
      TEH_plugin->cls,
      &dc->policy_details,
      &dc->bd.policy_details_serial_id,
      &dc->accumulated_total_without_fee,
      &dc->policy_details.fulfillment_state);
    if (qs < 0)
      return qs;

    dc->bd.policy_blocked =
      dc->policy_details.fulfillment_state != TALER_PolicyFulfillmentSuccess;
  }

  /* FIXME: replace by batch insert! */
  for (unsigned int i = 0; i<bd->num_cdis; i++)
  {
    const struct TALER_EXCHANGEDB_CoinDepositInformation *cdi
      = &bd->cdis[i];
    uint64_t known_coin_id;

    qs = TEH_make_coin_known (&cdi->coin,
                              connection,
                              &known_coin_id,
                              mhd_ret);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "make coin known (%s) returned %d\n",
                TALER_B2S (&cdi->coin.coin_pub),
                qs);
    if (qs < 0)
      return qs;
  }

  qs = TEH_plugin->do_deposit (
    TEH_plugin->cls,
    bd,
    &dc->exchange_timestamp,
    &balance_ok,
    &bad_balance_coin_index,
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
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "do_deposit returned: %d / %s[%u] / %s\n",
              qs,
              balance_ok ? "balance ok" : "balance insufficient",
              (unsigned int) bad_balance_coin_index,
              in_conflict ? "in conflict" : "no conflict");
  if (in_conflict)
  {
    struct TALER_MerchantWireHashP h_wire;

    if (GNUNET_DB_STATUS_SUCCESS_ONE_RESULT !=
        TEH_plugin->get_wire_hash_for_contract (
          TEH_plugin->cls,
          &bd->merchant_pub,
          &bd->h_contract_terms,
          &h_wire))
    {
      TALER_LOG_WARNING (
        "Failed to retrieve conflicting contract details from database\n");
      *mhd_ret = TALER_MHD_reply_with_error (connection,
                                             MHD_HTTP_INTERNAL_SERVER_ERROR,
                                             TALER_EC_GENERIC_DB_STORE_FAILED,
                                             "batch-deposit");
      return qs;
    }

    *mhd_ret
      = TEH_RESPONSE_reply_coin_conflicting_contract (
          connection,
          TALER_EC_EXCHANGE_DEPOSIT_CONFLICTING_CONTRACT,
          &h_wire);
    return GNUNET_DB_STATUS_HARD_ERROR;
  }
  if (! balance_ok)
  {
    GNUNET_assert (bad_balance_coin_index < bd->num_cdis);
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "returning history of conflicting coin (%s)\n",
                TALER_B2S (&bd->cdis[bad_balance_coin_index].coin.coin_pub));
    *mhd_ret
      = TEH_RESPONSE_reply_coin_insufficient_funds (
          connection,
          TALER_EC_EXCHANGE_GENERIC_INSUFFICIENT_FUNDS,
          &bd->cdis[bad_balance_coin_index].coin.denom_pub_hash,
          &bd->cdis[bad_balance_coin_index].coin.coin_pub);
    return GNUNET_DB_STATUS_HARD_ERROR;
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
 * @param dc information about the overall batch
 * @param jcoin coin data to parse
 * @param[out] cdi where to store the result
 * @param[out] deposit_fee where to write the deposit fee
 * @return #GNUNET_OK on success, #GNUNET_NO if an error was returned,
 *         #GNUNET_SYSERR on failure and no error could be returned
 */
static enum GNUNET_GenericReturnValue
parse_coin (struct MHD_Connection *connection,
            const struct BatchDepositContext *dc,
            json_t *jcoin,
            struct TALER_EXCHANGEDB_CoinDepositInformation *cdi,
            struct TALER_Amount *deposit_fee)
{
  const struct TALER_EXCHANGEDB_BatchDeposit *bd = &dc->bd;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_amount ("contribution",
                            TEH_currency,
                            &cdi->amount_with_fee),
    GNUNET_JSON_spec_fixed_auto ("denom_pub_hash",
                                 &cdi->coin.denom_pub_hash),
    TALER_JSON_spec_denom_sig ("ub_sig",
                               &cdi->coin.denom_sig),
    GNUNET_JSON_spec_fixed_auto ("coin_pub",
                                 &cdi->coin.coin_pub),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("h_age_commitment",
                                   &cdi->coin.h_age_commitment),
      &cdi->coin.no_age_commitment),
    GNUNET_JSON_spec_fixed_auto ("coin_sig",
                                 &cdi->csig),
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

    dk = TEH_keys_denomination_by_hash (&cdi->coin.denom_pub_hash,
                                        connection,
                                        &mret);
    if (NULL == dk)
    {
      GNUNET_JSON_parse_free (spec);
      return (MHD_YES == mret)
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
    if (0 > TALER_amount_cmp (&dk->meta.value,
                              &cdi->amount_with_fee))
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
                &cdi->coin.denom_pub_hash,
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
                &cdi->coin.denom_pub_hash,
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
                &cdi->coin.denom_pub_hash,
                TALER_EC_EXCHANGE_GENERIC_DENOMINATION_REVOKED,
                "DEPOSIT"))
        ? GNUNET_NO
        : GNUNET_SYSERR;
    }
    if (dk->denom_pub.bsign_pub_key->cipher !=
        cdi->coin.denom_sig.unblinded_sig->cipher)
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

    *deposit_fee = dk->meta.fees.deposit;
    /* check coin signature */
    switch (dk->denom_pub.bsign_pub_key->cipher)
    {
    case GNUNET_CRYPTO_BSA_RSA:
      TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_RSA]++;
      break;
    case GNUNET_CRYPTO_BSA_CS:
      TEH_METRICS_num_verifications[TEH_MT_SIGNATURE_CS]++;
      break;
    default:
      break;
    }
    if (GNUNET_YES !=
        TALER_test_coin_valid (&cdi->coin,
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
  if (0 < TALER_amount_cmp (deposit_fee,
                            &cdi->amount_with_fee))
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
      TALER_wallet_deposit_verify (
        &cdi->amount_with_fee,
        deposit_fee,
        &dc->h_wire,
        &bd->h_contract_terms,
        &bd->wallet_data_hash,
        cdi->coin.no_age_commitment
        ? NULL
        : &cdi->coin.h_age_commitment,
        NULL != dc->policy_json ? &dc->h_policy : NULL,
        &cdi->coin.denom_pub_hash,
        bd->wallet_timestamp,
        &bd->merchant_pub,
        bd->refund_deadline,
        &cdi->coin.coin_pub,
        &cdi->csig))
  {
    TALER_LOG_WARNING ("Invalid signature on /batch-deposit request\n");
    GNUNET_JSON_parse_free (spec);
    return (MHD_YES ==
            TALER_MHD_reply_with_error (connection,
                                        MHD_HTTP_FORBIDDEN,
                                        TALER_EC_EXCHANGE_DEPOSIT_COIN_SIGNATURE_INVALID,
                                        TALER_B2S (&cdi->coin.coin_pub)))
      ? GNUNET_NO
      : GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


MHD_RESULT
TEH_handler_batch_deposit (struct TEH_RequestContext *rc,
                           const json_t *root,
                           const char *const args[])
{
  struct MHD_Connection *connection = rc->connection;
  struct BatchDepositContext dc = { 0 };
  struct TALER_EXCHANGEDB_BatchDeposit *bd = &dc.bd;
  const json_t *coins;
  bool no_refund_deadline = true;
  struct GNUNET_JSON_Specification spec[] = {
    TALER_JSON_spec_payto_uri ("merchant_payto_uri",
                               &bd->receiver_wire_account),
    GNUNET_JSON_spec_fixed_auto ("wire_salt",
                                 &bd->wire_salt),
    GNUNET_JSON_spec_fixed_auto ("merchant_pub",
                                 &bd->merchant_pub),
    GNUNET_JSON_spec_fixed_auto ("h_contract_terms",
                                 &bd->h_contract_terms),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_fixed_auto ("wallet_data_hash",
                                   &bd->wallet_data_hash),
      &bd->no_wallet_data_hash),
    GNUNET_JSON_spec_array_const ("coins",
                                  &coins),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_json ("policy",
                             &dc.policy_json),
      &dc.has_no_policy),
    GNUNET_JSON_spec_timestamp ("timestamp",
                                &bd->wallet_timestamp),
    GNUNET_JSON_spec_mark_optional (
      GNUNET_JSON_spec_timestamp ("refund_deadline",
                                  &bd->refund_deadline),
      &no_refund_deadline),
    GNUNET_JSON_spec_timestamp ("wire_transfer_deadline",
                                &bd->wire_deadline),
    GNUNET_JSON_spec_end ()
  };

  (void) args;
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

    emsg = TALER_payto_validate (bd->receiver_wire_account);
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
  if (GNUNET_TIME_timestamp_cmp (bd->refund_deadline,
                                 >,
                                 bd->wire_deadline))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_DEPOSIT_REFUND_DEADLINE_AFTER_WIRE_DEADLINE,
                                       NULL);
  }
  if (GNUNET_TIME_absolute_is_never (bd->wire_deadline.abs_time))
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_EXCHANGE_DEPOSIT_WIRE_DEADLINE_IS_NEVER,
                                       NULL);
  }
  TALER_payto_hash (bd->receiver_wire_account,
                    &bd->wire_target_h_payto);
  TALER_merchant_wire_signature_hash (bd->receiver_wire_account,
                                      &bd->wire_salt,
                                      &dc.h_wire);

  GNUNET_assert (GNUNET_OK ==
                 TALER_amount_set_zero (TEH_currency,
                                        &dc.accumulated_total_without_fee));

  /* handle policy, if present */
  if (! dc.has_no_policy)
  {
    const char *error_hint = NULL;

    if (GNUNET_OK !=
        TALER_extensions_create_policy_details (
          TEH_currency,
          dc.policy_json,
          &dc.policy_details,
          &error_hint))
    {
      GNUNET_break_op (0);
      GNUNET_JSON_parse_free (spec);
      return TALER_MHD_reply_with_error (connection,
                                         MHD_HTTP_BAD_REQUEST,
                                         TALER_EC_EXCHANGE_DEPOSITS_POLICY_NOT_ACCEPTED,
                                         error_hint);
    }

    TALER_deposit_policy_hash (dc.policy_json,
                               &dc.h_policy);
  }

  bd->num_cdis = json_array_size (coins);
  if (0 == bd->num_cdis)
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       "coins");
  }
  if (TALER_MAX_FRESH_COINS < bd->num_cdis)
  {
    GNUNET_break_op (0);
    GNUNET_JSON_parse_free (spec);
    return TALER_MHD_reply_with_error (connection,
                                       MHD_HTTP_BAD_REQUEST,
                                       TALER_EC_GENERIC_PARAMETER_MALFORMED,
                                       "coins");
  }

  {
    struct TALER_EXCHANGEDB_CoinDepositInformation cdis[
      GNUNET_NZL (bd->num_cdis)];
    struct TALER_Amount deposit_fees[GNUNET_NZL (bd->num_cdis)];
    enum GNUNET_GenericReturnValue res;
    unsigned int i;

    bd->cdis = cdis;
    dc.deposit_fees = deposit_fees;
    for (i = 0; i<bd->num_cdis; i++)
    {
      struct TALER_Amount amount_without_fee;

      res = parse_coin (connection,
                        &dc,
                        json_array_get (coins,
                                        i),
                        &cdis[i],
                        &deposit_fees[i]);
      if (GNUNET_OK != res)
        break;
      GNUNET_assert (0 <=
                     TALER_amount_subtract (
                       &amount_without_fee,
                       &cdis[i].amount_with_fee,
                       &deposit_fees[i]));

      GNUNET_assert (0 <=
                     TALER_amount_add (
                       &dc.accumulated_total_without_fee,
                       &dc.accumulated_total_without_fee,
                       &amount_without_fee));
    }
    if (GNUNET_OK != res)
    {
      for (unsigned int j = 0; j<i; j++)
        TALER_denom_sig_free (&cdis[j].coin.denom_sig);
      GNUNET_JSON_parse_free (spec);
      return (GNUNET_NO == res) ? MHD_YES : MHD_NO;
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
        for (unsigned int j = 0; j<bd->num_cdis; j++)
          TALER_denom_sig_free (&cdis[j].coin.denom_sig);
        GNUNET_JSON_parse_free (spec);
        return mhd_ret;
      }
    }

    /* generate regular response */
    {
      MHD_RESULT mhd_ret;

      mhd_ret = reply_batch_deposit_success (connection,
                                             &dc);
      for (unsigned int j = 0; j<bd->num_cdis; j++)
        TALER_denom_sig_free (&cdis[j].coin.denom_sig);
      GNUNET_JSON_parse_free (spec);
      return mhd_ret;
    }
  }
}


/* end of taler-exchange-httpd_batch-deposit.c */
