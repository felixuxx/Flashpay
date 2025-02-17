/*
  This file is part of TALER
  Copyright (C) 2018-2024 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 3, or (at your
  option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_withdraw.c
 * @brief main interpreter loop for testcases
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <microhttpd.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_extensions.h"
#include "taler_testing_lib.h"
#include "backoff.h"


/**
 * How often do we retry before giving up?
 */
#define NUM_RETRIES 15

/**
 * How long do we wait AT LEAST if the exchange says the reserve is unknown?
 */
#define UNKNOWN_MIN_BACKOFF GNUNET_TIME_relative_multiply ( \
          GNUNET_TIME_UNIT_MILLISECONDS, 10)

/**
 * How long do we wait AT MOST if the exchange says the reserve is unknown?
 */
#define UNKNOWN_MAX_BACKOFF GNUNET_TIME_relative_multiply ( \
          GNUNET_TIME_UNIT_MILLISECONDS, 100)

/**
 * State for a "withdraw" CMD.
 */
struct WithdrawState
{

  /**
   * Which reserve should we withdraw from?
   */
  const char *reserve_reference;

  /**
   * Reference to a withdraw or reveal operation from which we should
   * reuse the private coin key, or NULL for regular withdrawal.
   */
  const char *reuse_coin_key_ref;

  /**
   * Our command.
   */
  const struct TALER_TESTING_Command *cmd;

  /**
   * String describing the denomination value we should withdraw.
   * A corresponding denomination key must exist in the exchange's
   * offerings.  Can be NULL if @e pk is set instead.
   */
  struct TALER_Amount amount;

  /**
   * If @e amount is NULL, this specifies the denomination key to
   * use.  Otherwise, this will be set (by the interpreter) to the
   * denomination PK matching @e amount.
   */
  struct TALER_EXCHANGE_DenomPublicKey *pk;

  /**
   * Exchange base URL.  Only used as offered trait.
   */
  char *exchange_url;

  /**
   * URI if the reserve we are withdrawing from.
   */
  struct TALER_NormalizedPayto reserve_payto_uri;

  /**
   * Private key of the reserve we are withdrawing from.
   */
  struct TALER_ReservePrivateKeyP reserve_priv;

  /**
   * Public key of the reserve we are withdrawing from.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Blinding key used during the operation.
   */
  union GNUNET_CRYPTO_BlindingSecretP bks;

  /**
   * Values contributed from the exchange during the
   * withdraw protocol.
   */
  struct TALER_ExchangeWithdrawValues exchange_vals;

  /**
   * Interpreter state (during command).
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Set (by the interpreter) to the exchange's signature over the
   * coin's public key.
   */
  struct TALER_DenominationSignature sig;

  /**
   * Private key material of the coin, set by the interpreter.
   */
  struct TALER_PlanchetMasterSecretP ps;

  /**
   * An age > 0 signifies age restriction is required
   */
  uint8_t age;

  /**
   * If age > 0, put here the corresponding age commitment with its proof and
   * its hash, respectively.
   */
  struct TALER_AgeCommitmentProof age_commitment_proof;
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   * Reserve history entry that corresponds to this operation.
   * Will be of type #TALER_EXCHANGE_RTT_WITHDRAWAL.
   */
  struct TALER_EXCHANGE_ReserveHistoryEntry reserve_history;

  /**
   * Withdraw handle (while operation is running).
   */
  struct TALER_EXCHANGE_BatchWithdrawHandle *wsh;

  /**
   * Task scheduled to try later.
   */
  struct GNUNET_SCHEDULER_Task *retry_task;

  /**
   * How long do we wait until we retry?
   */
  struct GNUNET_TIME_Relative backoff;

  /**
   * Total withdraw backoff applied.
   */
  struct GNUNET_TIME_Relative total_backoff;

  /**
   * Set to the KYC requirement payto hash *if* the exchange replied with a
   * request for KYC.
   */
  struct TALER_NormalizedPaytoHashP h_payto;

  /**
   * Set to the KYC requirement row *if* the exchange replied with
   * a request for KYC.
   */
  uint64_t requirement_row;

  /**
   * Expected HTTP response code to the request.
   */
  unsigned int expected_response_code;

  /**
   * Was this command modified via
   * #TALER_TESTING_cmd_withdraw_with_retry to
   * enable retries? How often should we still retry?
   */
  unsigned int do_retry;
};


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the commaind being run.
 * @param is interpreter state.
 */
static void
withdraw_run (void *cls,
              const struct TALER_TESTING_Command *cmd,
              struct TALER_TESTING_Interpreter *is);


/**
 * Task scheduled to re-try #withdraw_run.
 *
 * @param cls a `struct WithdrawState`
 */
static void
do_retry (void *cls)
{
  struct WithdrawState *ws = cls;

  ws->retry_task = NULL;
  TALER_TESTING_touch_cmd (ws->is);
  withdraw_run (ws,
                NULL,
                ws->is);
}


/**
 * "reserve withdraw" operation callback; checks that the
 * response code is expected and store the exchange signature
 * in the state.
 *
 * @param cls closure.
 * @param wr withdraw response details
 */
static void
reserve_withdraw_cb (void *cls,
                     const struct TALER_EXCHANGE_BatchWithdrawResponse *wr)
{
  struct WithdrawState *ws = cls;
  struct TALER_TESTING_Interpreter *is = ws->is;

  ws->wsh = NULL;
  if (ws->expected_response_code != wr->hr.http_status)
  {
    if (0 != ws->do_retry)
    {
      if (TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN != wr->hr.ec)
        ws->do_retry--; /* we don't count reserve unknown as failures here */
      if ( (0 == wr->hr.http_status) ||
           (TALER_EC_GENERIC_DB_SOFT_FAILURE == wr->hr.ec) ||
           (TALER_EC_EXCHANGE_WITHDRAW_INSUFFICIENT_FUNDS == wr->hr.ec) ||
           (TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN == wr->hr.ec) ||
           (MHD_HTTP_INTERNAL_SERVER_ERROR == wr->hr.http_status) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Retrying withdraw failed with %u/%d\n",
                    wr->hr.http_status,
                    (int) wr->hr.ec);
        /* on DB conflicts, do not use backoff */
        if (TALER_EC_GENERIC_DB_SOFT_FAILURE == wr->hr.ec)
          ws->backoff = GNUNET_TIME_UNIT_ZERO;
        else if (TALER_EC_EXCHANGE_GENERIC_RESERVE_UNKNOWN != wr->hr.ec)
          ws->backoff = EXCHANGE_LIB_BACKOFF (ws->backoff);
        else
          ws->backoff = GNUNET_TIME_relative_max (UNKNOWN_MIN_BACKOFF,
                                                  ws->backoff);
        ws->backoff = GNUNET_TIME_relative_min (ws->backoff,
                                                UNKNOWN_MAX_BACKOFF);
        ws->total_backoff = GNUNET_TIME_relative_add (ws->total_backoff,
                                                      ws->backoff);
        TALER_TESTING_inc_tries (ws->is);
        ws->retry_task = GNUNET_SCHEDULER_add_delayed (ws->backoff,
                                                       &do_retry,
                                                       ws);
        return;
      }
    }
    TALER_TESTING_unexpected_status_with_body (is,
                                               wr->hr.http_status,
                                               ws->expected_response_code,
                                               wr->hr.reply);
    return;
  }
  switch (wr->hr.http_status)
  {
  case MHD_HTTP_OK:
    GNUNET_assert (1 == wr->details.ok.num_coins);
    TALER_denom_sig_copy (&ws->sig,
                          &wr->details.ok.coins[0].sig);
    ws->coin_priv = wr->details.ok.coins[0].coin_priv;
    ws->bks = wr->details.ok.coins[0].bks;
    TALER_denom_ewv_copy (&ws->exchange_vals,
                          &wr->details.ok.coins[0].exchange_vals);
    if (0 != ws->total_backoff.rel_value_us)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "Total withdraw backoff for %s was %s\n",
                  ws->cmd->label,
                  GNUNET_STRINGS_relative_time_to_string (ws->total_backoff,
                                                          true));
    }
    break;
  case MHD_HTTP_FORBIDDEN:
    /* nothing to check */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* nothing to check */
    break;
  case MHD_HTTP_CONFLICT:
    /* nothing to check */
    break;
  case MHD_HTTP_GONE:
    /* theoretically could check that the key was actually */
    break;
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
    /* KYC required */
    ws->requirement_row =
      wr->details.unavailable_for_legal_reasons.requirement_row;
    ws->h_payto
      = wr->details.unavailable_for_legal_reasons.h_payto;
    break;
  default:
    /* Unsupported status code (by test harness) */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Withdraw test command does not support status code %u\n",
                wr->hr.http_status);
    GNUNET_break (0);
    break;
  }
  TALER_TESTING_interpreter_next (is);
}


/**
 * Run the command.
 */
static void
withdraw_run (void *cls,
              const struct TALER_TESTING_Command *cmd,
              struct TALER_TESTING_Interpreter *is)
{
  struct WithdrawState *ws = cls;
  const struct TALER_ReservePrivateKeyP *rp;
  const struct TALER_TESTING_Command *create_reserve;
  const struct TALER_EXCHANGE_DenomPublicKey *dpk;

  if (NULL != cmd)
    ws->cmd = cmd;
  ws->is = is;
  create_reserve
    = TALER_TESTING_interpreter_lookup_command (
        is,
        ws->reserve_reference);
  if (NULL == create_reserve)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_priv (create_reserve,
                                            &rp))
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (NULL == ws->exchange_url)
    ws->exchange_url
      = GNUNET_strdup (TALER_TESTING_get_exchange_url (is));
  ws->reserve_priv = *rp;
  GNUNET_CRYPTO_eddsa_key_get_public (&ws->reserve_priv.eddsa_priv,
                                      &ws->reserve_pub.eddsa_pub);
  ws->reserve_payto_uri
    = TALER_reserve_make_payto (ws->exchange_url,
                                &ws->reserve_pub);

  if (NULL == ws->reuse_coin_key_ref)
  {
    TALER_planchet_master_setup_random (&ws->ps);
  }
  else
  {
    const struct TALER_PlanchetMasterSecretP *ps;
    const struct TALER_TESTING_Command *cref;
    char *cstr;
    unsigned int index;

    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_parse_coin_reference (
                     ws->reuse_coin_key_ref,
                     &cstr,
                     &index));
    cref = TALER_TESTING_interpreter_lookup_command (is,
                                                     cstr);
    GNUNET_assert (NULL != cref);
    GNUNET_free (cstr);
    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_planchet_secret (cref,
                                                            &ps));
    ws->ps = *ps;
  }

  if (NULL == ws->pk)
  {
    dpk = TALER_TESTING_find_pk (TALER_TESTING_get_keys (is),
                                 &ws->amount,
                                 ws->age > 0);
    if (NULL == dpk)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to determine denomination key at %s\n",
                  (NULL != cmd) ? cmd->label : "<retried command>");
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    /* We copy the denomination key, as re-querying /keys
     * would free the old one. */
    ws->pk = TALER_EXCHANGE_copy_denomination_key (dpk);
  }
  else
  {
    ws->amount = ws->pk->value;
  }

  ws->reserve_history.type = TALER_EXCHANGE_RTT_WITHDRAWAL;
  GNUNET_assert (0 <=
                 TALER_amount_add (&ws->reserve_history.amount,
                                   &ws->amount,
                                   &ws->pk->fees.withdraw));
  ws->reserve_history.details.withdraw.fee = ws->pk->fees.withdraw;
  {
    struct TALER_EXCHANGE_WithdrawCoinInput wci = {
      .pk = ws->pk,
      .ps = &ws->ps,
      .ach = 0 < ws->age ? &ws->h_age_commitment : NULL
    };

    ws->wsh = TALER_EXCHANGE_batch_withdraw (
      TALER_TESTING_interpreter_get_context (is),
      TALER_TESTING_get_exchange_url (is),
      TALER_TESTING_get_keys (is),
      rp,
      1,
      &wci,
      &reserve_withdraw_cb,
      ws);
  }
  if (NULL == ws->wsh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "withdraw" CMD, and possibly cancel
 * a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command being freed.
 */
static void
withdraw_cleanup (void *cls,
                  const struct TALER_TESTING_Command *cmd)
{
  struct WithdrawState *ws = cls;

  if (NULL != ws->wsh)
  {
    TALER_TESTING_command_incomplete (ws->is,
                                      cmd->label);
    TALER_EXCHANGE_batch_withdraw_cancel (ws->wsh);
    ws->wsh = NULL;
  }
  if (NULL != ws->retry_task)
  {
    GNUNET_SCHEDULER_cancel (ws->retry_task);
    ws->retry_task = NULL;
  }
  TALER_denom_sig_free (&ws->sig);
  TALER_denom_ewv_free (&ws->exchange_vals);
  if (NULL != ws->pk)
  {
    TALER_EXCHANGE_destroy_denomination_key (ws->pk);
    ws->pk = NULL;
  }
  if (ws->age > 0)
    TALER_age_commitment_proof_free (&ws->age_commitment_proof);
  GNUNET_free (ws->exchange_url);
  GNUNET_free (ws->reserve_payto_uri.normalized_payto);
  GNUNET_free (ws);
}


/**
 * Offer internal data to a "withdraw" CMD state to other
 * commands.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static enum GNUNET_GenericReturnValue
withdraw_traits (void *cls,
                 const void **ret,
                 const char *trait,
                 unsigned int index)
{
  struct WithdrawState *ws = cls;
  struct TALER_TESTING_Trait traits[] = {
    /* history entry MUST be first due to response code logic below! */
    TALER_TESTING_make_trait_reserve_history (0,
                                              &ws->reserve_history),
    TALER_TESTING_make_trait_coin_priv (0 /* only one coin */,
                                        &ws->coin_priv),
    TALER_TESTING_make_trait_planchet_secret (&ws->ps),
    TALER_TESTING_make_trait_blinding_key (0 /* only one coin */,
                                           &ws->bks),
    TALER_TESTING_make_trait_exchange_wd_value (0 /* only one coin */,
                                                &ws->exchange_vals),
    TALER_TESTING_make_trait_denom_pub (0 /* only one coin */,
                                        ws->pk),
    TALER_TESTING_make_trait_denom_sig (0 /* only one coin */,
                                        &ws->sig),
    TALER_TESTING_make_trait_reserve_priv (&ws->reserve_priv),
    TALER_TESTING_make_trait_reserve_pub (&ws->reserve_pub),
    TALER_TESTING_make_trait_amount (&ws->amount),
    TALER_TESTING_make_trait_legi_requirement_row (&ws->requirement_row),
    TALER_TESTING_make_trait_h_normalized_payto (&ws->h_payto),
    TALER_TESTING_make_trait_normalized_payto_uri (&ws->reserve_payto_uri),
    TALER_TESTING_make_trait_exchange_url (ws->exchange_url),
    TALER_TESTING_make_trait_age_commitment_proof (0,
                                                   0 < ws->age
                                                   ? &ws->age_commitment_proof
                                                   : NULL),
    TALER_TESTING_make_trait_h_age_commitment (0,
                                               0 < ws->age
                                               ? &ws->h_age_commitment
                                               : NULL),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait ((ws->expected_response_code == MHD_HTTP_OK)
                                  ? &traits[0]   /* we have reserve history */
                                  : &traits[1],  /* skip reserve history */
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_amount (const char *label,
                                   const char *reserve_reference,
                                   const char *amount,
                                   uint8_t age,
                                   unsigned int expected_response_code)
{
  struct WithdrawState *ws;

  ws = GNUNET_new (struct WithdrawState);
  ws->age = age;
  if (0 < age)
  {
    struct GNUNET_HashCode seed;
    struct TALER_AgeMask mask;

    mask = TALER_extensions_get_age_restriction_mask ();
    GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                &seed,
                                sizeof(seed));
    TALER_age_restriction_commit (&mask,
                                  age,
                                  &seed,
                                  &ws->age_commitment_proof);
    TALER_age_commitment_hash (&ws->age_commitment_proof.commitment,
                               &ws->h_age_commitment);
  }

  ws->reserve_reference = reserve_reference;
  if (GNUNET_OK !=
      TALER_string_to_amount (amount,
                              &ws->amount))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse amount `%s' at %s\n",
                amount,
                label);
    GNUNET_assert (0);
  }
  ws->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ws,
      .label = label,
      .run = &withdraw_run,
      .cleanup = &withdraw_cleanup,
      .traits = &withdraw_traits
    };

    return cmd;
  }
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_amount_reuse_key (
  const char *label,
  const char *reserve_reference,
  const char *amount,
  uint8_t age,
  const char *coin_ref,
  unsigned int expected_response_code)
{
  struct TALER_TESTING_Command cmd;

  cmd = TALER_TESTING_cmd_withdraw_amount (label,
                                           reserve_reference,
                                           amount,
                                           age,
                                           expected_response_code);
  {
    struct WithdrawState *ws = cmd.cls;

    ws->reuse_coin_key_ref = coin_ref;
  }
  return cmd;
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_denomination (
  const char *label,
  const char *reserve_reference,
  const struct TALER_EXCHANGE_DenomPublicKey *dk,
  unsigned int expected_response_code)
{
  struct WithdrawState *ws;

  if (NULL == dk)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Denomination key not specified at %s\n",
                label);
    GNUNET_assert (0);
  }
  ws = GNUNET_new (struct WithdrawState);
  ws->reserve_reference = reserve_reference;
  ws->pk = TALER_EXCHANGE_copy_denomination_key (dk);
  ws->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ws,
      .label = label,
      .run = &withdraw_run,
      .cleanup = &withdraw_cleanup,
      .traits = &withdraw_traits
    };

    return cmd;
  }
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_withdraw_with_retry (struct TALER_TESTING_Command cmd)
{
  struct WithdrawState *ws;

  GNUNET_assert (&withdraw_run == cmd.run);
  ws = cmd.cls;
  ws->do_retry = NUM_RETRIES;
  return cmd;
}


/* end of testing_api_cmd_withdraw.c */
