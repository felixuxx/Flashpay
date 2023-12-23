/*
  This file is part of TALER
  Copyright (C) 2018-2022 Taler Systems SA

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
 * @file testing/testing_api_cmd_batch_withdraw.c
 * @brief implements the batch withdraw command
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_exchange_service.h"
#include "taler_json_lib.h"
#include <microhttpd.h>
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_extensions.h"
#include "taler_testing_lib.h"

/**
 * Information we track per withdrawn coin.
 */
struct CoinState
{

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
   * Private key of the coin.
   */
  struct TALER_CoinSpendPrivateKeyP coin_priv;

  /**
   * Public key of the coin.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

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
   * Set (by the interpreter) to the exchange's signature over the
   * coin's public key.
   */
  struct TALER_DenominationSignature sig;

  /**
   * Private key material of the coin, set by the interpreter.
   */
  struct TALER_PlanchetMasterSecretP ps;

  /**
   * If age > 0, put here the corresponding age commitment with its proof and
   * its hash, respectively.
   */
  struct TALER_AgeCommitmentProof age_commitment_proof;
  struct TALER_AgeCommitmentHash h_age_commitment;

  /**
   * Reserve history entry that corresponds to this coin.
   * Will be of type #TALER_EXCHANGE_RTT_WITHDRAWAL.
   */
  struct TALER_EXCHANGE_ReserveHistoryEntry reserve_history;


};


/**
 * State for a "batch withdraw" CMD.
 */
struct BatchWithdrawState
{

  /**
   * Which reserve should we withdraw from?
   */
  const char *reserve_reference;

  /**
   * Exchange base URL.  Only used as offered trait.
   */
  char *exchange_url;

  /**
   * URI if the reserve we are withdrawing from.
   */
  char *reserve_payto_uri;

  /**
   * Private key of the reserve we are withdrawing from.
   */
  struct TALER_ReservePrivateKeyP reserve_priv;

  /**
   * Public key of the reserve we are withdrawing from.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Interpreter state (during command).
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Withdraw handle (while operation is running).
   */
  struct TALER_EXCHANGE_BatchWithdrawHandle *wsh;

  /**
   * Array of coin states.
   */
  struct CoinState *coins;

  /**
   * Set to the KYC requirement payto hash *if* the exchange replied with a
   * request for KYC.
   */
  struct TALER_PaytoHashP h_payto;

  /**
   * Set to the KYC requirement row *if* the exchange replied with
   * a request for KYC.
   */
  uint64_t requirement_row;

  /**
   * Length of the @e coins array.
   */
  unsigned int num_coins;

  /**
   * Expected HTTP response code to the request.
   */
  unsigned int expected_response_code;

  /**
   * An age > 0 signifies age restriction is required.
   * Same for all coins in the batch.
   */
  uint8_t age;

  /**
   * Force a conflict:
   */
  bool force_conflict;
};


/**
 * "batch withdraw" operation callback; checks that the
 * response code is expected and store the exchange signature
 * in the state.
 *
 * @param cls closure.
 * @param wr withdraw response details
 */
static void
reserve_batch_withdraw_cb (void *cls,
                           const struct
                           TALER_EXCHANGE_BatchWithdrawResponse *wr)
{
  struct BatchWithdrawState *ws = cls;
  struct TALER_TESTING_Interpreter *is = ws->is;

  ws->wsh = NULL;
  if (ws->expected_response_code != wr->hr.http_status)
  {
    TALER_TESTING_unexpected_status_with_body (is,
                                               wr->hr.http_status,
                                               ws->expected_response_code,
                                               wr->hr.reply);
    return;
  }
  switch (wr->hr.http_status)
  {
  case MHD_HTTP_OK:
    for (unsigned int i = 0; i<ws->num_coins; i++)
    {
      struct CoinState *cs = &ws->coins[i];
      const struct TALER_EXCHANGE_PrivateCoinDetails *pcd
        = &wr->details.ok.coins[i];

      TALER_denom_sig_deep_copy (&cs->sig,
                                 &pcd->sig);
      cs->coin_priv = pcd->coin_priv;
      GNUNET_CRYPTO_eddsa_key_get_public (&cs->coin_priv.eddsa_priv,
                                          &cs->coin_pub.eddsa_pub);

      cs->bks = pcd->bks;
      cs->exchange_vals = pcd->exchange_vals;
    }
    break;
  case MHD_HTTP_FORBIDDEN:
    /* nothing to check */
    break;
  case MHD_HTTP_NOT_FOUND:
    /* nothing to check */
    break;
  case MHD_HTTP_CONFLICT:
    /* TODO[oec]: Check if age-requirement is the reason */
    break;
  case MHD_HTTP_GONE:
    /* theoretically could check that the key was actually */
    break;
  case MHD_HTTP_UNAVAILABLE_FOR_LEGAL_REASONS:
    /* nothing to check */
    ws->requirement_row
      = wr->details.unavailable_for_legal_reasons.requirement_row;
    ws->h_payto
      = wr->details.unavailable_for_legal_reasons.h_payto;
    break;
  default:
    /* Unsupported status code (by test harness) */
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Batch withdraw test command does not support status code %u\n",
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
batch_withdraw_run (void *cls,
                    const struct TALER_TESTING_Command *cmd,
                    struct TALER_TESTING_Interpreter *is)
{
  struct BatchWithdrawState *ws = cls;
  const struct TALER_EXCHANGE_Keys *keys =  TALER_TESTING_get_keys (is);
  const struct TALER_ReservePrivateKeyP *rp;
  const struct TALER_TESTING_Command *create_reserve;
  const struct TALER_EXCHANGE_DenomPublicKey *dpk;
  struct TALER_EXCHANGE_WithdrawCoinInput wcis[ws->num_coins];
  struct TALER_PlanchetMasterSecretP conflict_ps = {0};
  struct TALER_AgeMask mask = {0};

  (void) cmd;
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

  if (0 < ws->age)
    mask = TALER_extensions_get_age_restriction_mask ();

  if (ws->force_conflict)
    TALER_planchet_master_setup_random (&conflict_ps);

  for (unsigned int i = 0; i<ws->num_coins; i++)
  {
    struct CoinState *cs = &ws->coins[i];
    struct TALER_EXCHANGE_WithdrawCoinInput *wci = &wcis[i];

    if (ws->force_conflict)
      cs->ps = conflict_ps;
    else
      TALER_planchet_master_setup_random (&cs->ps);

    if (0 < ws->age)
    {
      struct GNUNET_HashCode seed = {0};
      GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_WEAK,
                                  &seed,
                                  sizeof(seed));
      TALER_age_restriction_commit (&mask,
                                    ws->age,
                                    &seed,
                                    &cs->age_commitment_proof);
      TALER_age_commitment_hash (&cs->age_commitment_proof.commitment,
                                 &cs->h_age_commitment);
    }


    dpk = TALER_TESTING_find_pk (keys,
                                 &cs->amount,
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
    cs->pk = TALER_EXCHANGE_copy_denomination_key (dpk);
    cs->reserve_history.type = TALER_EXCHANGE_RTT_WITHDRAWAL;
    GNUNET_assert (0 <=
                   TALER_amount_add (&cs->reserve_history.amount,
                                     &cs->amount,
                                     &cs->pk->fees.withdraw));
    cs->reserve_history.details.withdraw.fee = cs->pk->fees.withdraw;

    wci->pk = cs->pk;
    wci->ps = &cs->ps;
    wci->ach = &cs->h_age_commitment;
  }
  ws->wsh = TALER_EXCHANGE_batch_withdraw (
    TALER_TESTING_interpreter_get_context (is),
    TALER_TESTING_get_exchange_url (is),
    keys,
    rp,
    ws->num_coins,
    wcis,
    &reserve_batch_withdraw_cb,
    ws);
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
batch_withdraw_cleanup (void *cls,
                        const struct TALER_TESTING_Command *cmd)
{
  struct BatchWithdrawState *ws = cls;

  if (NULL != ws->wsh)
  {
    TALER_TESTING_command_incomplete (ws->is,
                                      cmd->label);
    TALER_EXCHANGE_batch_withdraw_cancel (ws->wsh);
    ws->wsh = NULL;
  }
  for (unsigned int i = 0; i<ws->num_coins; i++)
  {
    struct CoinState *cs = &ws->coins[i];

    TALER_denom_sig_free (&cs->sig);
    if (NULL != cs->pk)
    {
      TALER_EXCHANGE_destroy_denomination_key (cs->pk);
      cs->pk = NULL;
    }
    if (0 < ws->age)
      TALER_age_commitment_proof_free (&cs->age_commitment_proof);
  }
  GNUNET_free (ws->coins);
  GNUNET_free (ws->exchange_url);
  GNUNET_free (ws->reserve_payto_uri);
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
batch_withdraw_traits (void *cls,
                       const void **ret,
                       const char *trait,
                       unsigned int index)
{
  struct BatchWithdrawState *ws = cls;
  struct CoinState *cs = &ws->coins[index];
  struct TALER_TESTING_Trait traits[] = {
    /* history entry MUST be first due to response code logic below! */
    TALER_TESTING_make_trait_reserve_history (index,
                                              &cs->reserve_history),
    TALER_TESTING_make_trait_coin_priv (index,
                                        &cs->coin_priv),
    TALER_TESTING_make_trait_coin_pub (index,
                                       &cs->coin_pub),
    TALER_TESTING_make_trait_planchet_secrets (index,
                                               &cs->ps),
    TALER_TESTING_make_trait_blinding_key (index,
                                           &cs->bks),
    TALER_TESTING_make_trait_exchange_wd_value (index,
                                                &cs->exchange_vals),
    TALER_TESTING_make_trait_denom_pub (index,
                                        cs->pk),
    TALER_TESTING_make_trait_denom_sig (index,
                                        &cs->sig),
    TALER_TESTING_make_trait_reserve_priv (&ws->reserve_priv),
    TALER_TESTING_make_trait_reserve_pub (&ws->reserve_pub),
    TALER_TESTING_make_trait_amounts (index,
                                      &cs->amount),
    TALER_TESTING_make_trait_legi_requirement_row (&ws->requirement_row),
    TALER_TESTING_make_trait_h_payto (&ws->h_payto),
    TALER_TESTING_make_trait_payto_uri (ws->reserve_payto_uri),
    TALER_TESTING_make_trait_exchange_url (ws->exchange_url),
    TALER_TESTING_make_trait_age_commitment_proof (index,
                                                   ws->age > 0 ?
                                                   &cs->age_commitment_proof:
                                                   NULL),
    TALER_TESTING_make_trait_h_age_commitment (index,
                                               ws->age > 0 ?
                                               &cs->h_age_commitment :
                                               NULL),
    TALER_TESTING_trait_end ()
  };

  if (index >= ws->num_coins)
    return GNUNET_NO;
  return TALER_TESTING_get_trait ((ws->expected_response_code == MHD_HTTP_OK)
                                  ? &traits[0]   /* we have reserve history */
                                  : &traits[1],  /* skip reserve history */
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_batch_withdraw_with_conflict (
  const char *label,
  const char *reserve_reference,
  bool conflict,
  uint8_t age,
  unsigned int expected_response_code,
  const char *amount,
  ...)
{
  struct BatchWithdrawState *ws;
  unsigned int cnt;
  va_list ap;

  ws = GNUNET_new (struct BatchWithdrawState);
  ws->age = age;
  ws->reserve_reference = reserve_reference;
  ws->expected_response_code = expected_response_code;
  ws->force_conflict = conflict;

  cnt = 1;
  va_start (ap,
            amount);
  while (NULL != (va_arg (ap,
                          const char *)))
    cnt++;
  ws->num_coins = cnt;
  ws->coins = GNUNET_new_array (cnt,
                                struct CoinState);
  va_end (ap);
  va_start (ap,
            amount);
  for (unsigned int i = 0; i<ws->num_coins; i++)
  {
    struct CoinState *cs = &ws->coins[i];

    if (GNUNET_OK !=
        TALER_string_to_amount (amount,
                                &cs->amount))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Failed to parse amount `%s' at %s\n",
                  amount,
                  label);
      GNUNET_assert (0);
    }
    /* move on to next vararg! */
    amount = va_arg (ap,
                     const char *);
  }
  GNUNET_assert (NULL == amount);
  va_end (ap);

  {
    struct TALER_TESTING_Command cmd = {
      .cls = ws,
      .label = label,
      .run = &batch_withdraw_run,
      .cleanup = &batch_withdraw_cleanup,
      .traits = &batch_withdraw_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_batch_withdraw.c */
