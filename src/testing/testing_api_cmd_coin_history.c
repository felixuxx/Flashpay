/*
  This file is part of TALER
  Copyright (C) 2023 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as
  published by the Free Software Foundation; either version 3, or
  (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public
  License along with TALER; see the file COPYING.  If not, see
  <http://www.gnu.org/licenses/>
*/
/**
 * @file testing/testing_api_cmd_coin_history.c
 * @brief Implement the /coins/$COIN_PUB/history test command.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "history" CMD.
 */
struct HistoryState
{

  /**
   * Public key of the coin being analyzed.
   */
  struct TALER_CoinSpendPublicKeyP coin_pub;

  /**
   * Label to the command which created the coin to check,
   * needed to resort the coin key.
   */
  const char *coin_reference;

  /**
   * Handle to the "coin history" operation.
   */
  struct TALER_EXCHANGE_CoinsHistoryHandle *rsh;

  /**
   * Expected coin balance.
   */
  const char *expected_balance;

  /**
   * Private key of the coin being analyzed.
   */
  const struct TALER_CoinSpendPrivateKeyP *coin_priv;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

};


/**
 * Closure for analysis_cb().
 */
struct AnalysisContext
{
  /**
   * Coin public key we are looking at.
   */
  const struct TALER_CoinSpendPublicKeyP *coin_pub;

  /**
   * Length of the @e history array.
   */
  unsigned int history_length;

  /**
   * Array of history items to match.
   */
  const struct TALER_EXCHANGE_CoinHistoryEntry *history;

  /**
   * Array of @e history_length of matched entries.
   */
  bool *found;

  /**
   * Set to true if an entry could not be found.
   */
  bool failure;
};


/**
 * Compare @a h1 and @a h2.
 *
 * @param h1 a history entry
 * @param h2 a history entry
 * @return 0 if @a h1 and @a h2 are equal
 */
static int
history_entry_cmp (
  const struct TALER_EXCHANGE_CoinHistoryEntry *h1,
  const struct TALER_EXCHANGE_CoinHistoryEntry *h2)
{
  if (h1->type != h2->type)
    return 1;
  if (0 != TALER_amount_cmp (&h1->amount,
                             &h2->amount))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                "Amount mismatch (%s)\n",
                TALER_amount2s (&h1->amount));
    return 1;
  }
  switch (h1->type)
  {
  case TALER_EXCHANGE_CTT_NONE:
    GNUNET_break (0);
    break;
  case TALER_EXCHANGE_CTT_DEPOSIT:
    if (0 != GNUNET_memcmp (&h1->details.deposit.h_contract_terms,
                            &h2->details.deposit.h_contract_terms))
      return 1;
    if (0 != GNUNET_memcmp (&h1->details.deposit.merchant_pub,
                            &h2->details.deposit.merchant_pub))
      return 1;
    if (0 != GNUNET_memcmp (&h1->details.deposit.h_wire,
                            &h2->details.deposit.h_wire))
      return 1;
    if (0 != GNUNET_memcmp (&h1->details.deposit.sig,
                            &h2->details.deposit.sig))
      return 1;
    return 0;
  case TALER_EXCHANGE_CTT_MELT:
    if (0 != GNUNET_memcmp (&h1->details.melt.h_age_commitment,
                            &h2->details.melt.h_age_commitment))
      return 1;
    /* Note: most other fields are not initialized
       in the trait as they are hard to extract from
       the API */
    return 0;
  case TALER_EXCHANGE_CTT_REFUND:
    if (0 != GNUNET_memcmp (&h1->details.refund.sig,
                            &h2->details.refund.sig))
      return 1;
    return 0;
  case TALER_EXCHANGE_CTT_RECOUP:
    if (0 != GNUNET_memcmp (&h1->details.recoup.coin_sig,
                            &h2->details.recoup.coin_sig))
      return 1;
    /* Note: exchange_sig, exchange_pub and timestamp are
       fundamentally not available in the initiating command */
    return 0;
  case TALER_EXCHANGE_CTT_RECOUP_REFRESH:
    if (0 != GNUNET_memcmp (&h1->details.recoup_refresh.coin_sig,
                            &h2->details.recoup_refresh.coin_sig))
      return 1;
    /* Note: exchange_sig, exchange_pub and timestamp are
       fundamentally not available in the initiating command */
    return 0;
  case TALER_EXCHANGE_CTT_OLD_COIN_RECOUP:
    if (0 != GNUNET_memcmp (&h1->details.old_coin_recoup.new_coin_pub,
                            &h2->details.old_coin_recoup.new_coin_pub))
      return 1;
    /* Note: exchange_sig, exchange_pub and timestamp are
       fundamentally not available in the initiating command */
    return 0;
  case TALER_EXCHANGE_CTT_PURSE_DEPOSIT:
    /* coin_sig is not initialized */
    if (0 != GNUNET_memcmp (&h1->details.purse_deposit.purse_pub,
                            &h2->details.purse_deposit.purse_pub))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Purse public key mismatch\n");
      return 1;
    }
    if (0 != strcmp (h1->details.purse_deposit.exchange_base_url,
                     h2->details.purse_deposit.exchange_base_url))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Exchange base URL mismatch (%s/%s)\n",
                  h1->details.purse_deposit.exchange_base_url,
                  h2->details.purse_deposit.exchange_base_url);
      GNUNET_break (0);
      return 1;
    }
    return 0;
  case TALER_EXCHANGE_CTT_PURSE_REFUND:
    /* NOTE: not supported yet (trait not returned) */
    return 0;
  case TALER_EXCHANGE_CTT_RESERVE_OPEN_DEPOSIT:
    /* NOTE: not supported yet (trait not returned) */
    if (0 != GNUNET_memcmp (&h1->details.reserve_open_deposit.coin_sig,
                            &h2->details.reserve_open_deposit.coin_sig))
      return 1;
    return 0;
  }
  GNUNET_assert (0);
  return -1;
}


/**
 * Check if @a cmd changed the coin, if so, find the
 * entry in our history and set the respective index in found
 * to true. If the entry is not found, set failure.
 *
 * @param cls our `struct AnalysisContext *`
 * @param cmd command to analyze for impact on history
 */
static void
analyze_command (void *cls,
                 const struct TALER_TESTING_Command *cmd)
{
  struct AnalysisContext *ac = cls;
  const struct TALER_CoinSpendPublicKeyP *coin_pub = ac->coin_pub;
  const struct TALER_EXCHANGE_CoinHistoryEntry *history = ac->history;
  unsigned int history_length = ac->history_length;
  bool *found = ac->found;

  if (TALER_TESTING_cmd_is_batch (cmd))
  {
    struct TALER_TESTING_Command *cur;
    struct TALER_TESTING_Command *bcmd;

    cur = TALER_TESTING_cmd_batch_get_current (cmd);
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_batch_cmds (cmd,
                                            &bcmd))
    {
      GNUNET_break (0);
      ac->failure = true;
      return;
    }
    for (unsigned int i = 0; NULL != bcmd[i].label; i++)
    {
      struct TALER_TESTING_Command *step = &bcmd[i];

      analyze_command (ac,
                       step);
      if (ac->failure)
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Entry for batch step `%s' missing in history\n",
                    step->label);
        return;
      }
      if (step == cur)
        break; /* if *we* are in a batch, make sure not to analyze commands past 'now' */
    }
    return;
  }

  for (unsigned int j = 0; true; j++)
  {
    const struct TALER_CoinSpendPublicKeyP *rp;
    const struct TALER_EXCHANGE_CoinHistoryEntry *he;
    bool matched = false;

    if (GNUNET_OK !=
        TALER_TESTING_get_trait_coin_pub (cmd,
                                          j,
                                          &rp))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Command `%s#%u' has no public key for a coin\n",
                  cmd->label,
                  j);
      break; /* command does nothing for coins */
    }
    if (0 !=
        GNUNET_memcmp (rp,
                       coin_pub))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                  "Command `%s#%u' is about another coin\n",
                  cmd->label,
                  j);
      continue; /* command affects some _other_ coin */
    }
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_coin_history (cmd,
                                              j,
                                              &he))
    {
      /* NOTE: only for debugging... */
      if (0 == j)
        GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                    "Command `%s' has the coin_pub, but lacks coin history trait\n",
                    cmd->label);
      return; /* command does nothing for coins */
    }
    for (unsigned int i = 0; i<history_length; i++)
    {
      if (found[i])
        continue; /* already found, skip */
      if (0 ==
          history_entry_cmp (he,
                             &history[i]))
      {
        found[i] = true;
        matched = true;
        break;
      }
    }
    if (! matched)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Command `%s' coin history entry #%u not found\n",
                  cmd->label,
                  j);
      ac->failure = true;
      return;
    }
  }
}


/**
 * Check that the coin balance and HTTP response code are
 * both acceptable.
 *
 * @param cls closure.
 * @param rs HTTP response details
 */
static void
coin_history_cb (void *cls,
                 const struct TALER_EXCHANGE_CoinHistory *rs)
{
  struct HistoryState *ss = cls;
  struct TALER_TESTING_Interpreter *is = ss->is;
  struct TALER_Amount eb;
  unsigned int hlen;

  ss->rsh = NULL;
  if (ss->expected_response_code != rs->hr.http_status)
  {
    TALER_TESTING_unexpected_status (ss->is,
                                     rs->hr.http_status,
                                     ss->expected_response_code);
    return;
  }
  if (MHD_HTTP_OK != rs->hr.http_status)
  {
    TALER_TESTING_interpreter_next (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (ss->expected_balance,
                                         &eb));

  if (0 != TALER_amount_cmp (&eb,
                             &rs->details.ok.balance))
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected balance for coin: %s\n",
                TALER_amount_to_string (&rs->details.ok.balance));
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Expected balance of: %s\n",
                TALER_amount_to_string (&eb));
    TALER_TESTING_interpreter_fail (ss->is);
    return;
  }
  hlen = json_array_size (rs->details.ok.history);
  {
    bool found[GNUNET_NZL (hlen)];
    struct TALER_EXCHANGE_CoinHistoryEntry rhist[GNUNET_NZL (hlen)];
    struct AnalysisContext ac = {
      .coin_pub = &ss->coin_pub,
      .history = rhist,
      .history_length = hlen,
      .found = found
    };
    const struct TALER_EXCHANGE_DenomPublicKey *dk;
    struct TALER_Amount total_in;
    struct TALER_Amount total_out;
    struct TALER_Amount hbal;

    dk = TALER_EXCHANGE_get_denomination_key_by_hash (
      TALER_TESTING_get_keys (is),
      &rs->details.ok.h_denom_pub);
    memset (found,
            0,
            sizeof (found));
    memset (rhist,
            0,
            sizeof (rhist));
    if (GNUNET_OK !=
        TALER_EXCHANGE_parse_coin_history (
          TALER_TESTING_get_keys (is),
          dk,
          rs->details.ok.history,
          &ss->coin_pub,
          &total_in,
          &total_out,
          hlen,
          rhist))
    {
      GNUNET_break (0);
      json_dumpf (rs->hr.reply,
                  stderr,
                  JSON_INDENT (2));
      TALER_TESTING_interpreter_fail (ss->is);
      return;
    }
    if (0 >
        TALER_amount_subtract (&hbal,
                               &total_in,
                               &total_out))
    {
      GNUNET_break (0);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Coin credits: %s\n",
                  TALER_amount2s (&total_in));
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Coin debits: %s\n",
                  TALER_amount2s (&total_out));
      TALER_TESTING_interpreter_fail (ss->is);
      return;
    }
    if (0 != TALER_amount_cmp (&hbal,
                               &rs->details.ok.balance))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (ss->is);
      return;
    }
    (void) ac;
    TALER_TESTING_iterate (is,
                           true,
                           &analyze_command,
                           &ac);
    if (ac.failure)
    {
      json_dumpf (rs->hr.reply,
                  stderr,
                  JSON_INDENT (2));
      TALER_TESTING_interpreter_fail (ss->is);
      return;
    }
#if 1
    for (unsigned int i = 0; i<hlen; i++)
    {
      if (found[i])
        continue;
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "History entry at index %u of type %d not justified by command history\n",
                  i,
                  rs->details.ok.history[i].type);
      json_dumpf (rs->hr.reply,
                  stderr,
                  JSON_INDENT (2));
      TALER_TESTING_interpreter_fail (ss->is);
      return;
    }
#endif
  }
  TALER_TESTING_interpreter_next (is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command being executed.
 * @param is the interpreter state.
 */
static void
history_run (void *cls,
             const struct TALER_TESTING_Command *cmd,
             struct TALER_TESTING_Interpreter *is)
{
  struct HistoryState *ss = cls;
  const struct TALER_TESTING_Command *create_coin;
  char *cref;
  unsigned int idx;

  ss->is = is;
  GNUNET_assert (
    GNUNET_OK ==
    TALER_TESTING_parse_coin_reference (
      ss->coin_reference,
      &cref,
      &idx));
  create_coin
    = TALER_TESTING_interpreter_lookup_command (is,
                                                cref);
  GNUNET_free (cref);
  if (NULL == create_coin)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_coin_priv (create_coin,
                                         idx,
                                         &ss->coin_priv))
  {
    GNUNET_break (0);
    TALER_LOG_ERROR ("Failed to find coin_priv for history query\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_CRYPTO_eddsa_key_get_public (&ss->coin_priv->eddsa_priv,
                                      &ss->coin_pub.eddsa_pub);
  ss->rsh = TALER_EXCHANGE_coins_history (
    TALER_TESTING_interpreter_get_context (is),
    TALER_TESTING_get_exchange_url (is),
    ss->coin_priv,
    0,
    &coin_history_cb,
    ss);
}


/**
 * Offer internal data from a "history" CMD, to other commands.
 *
 * @param cls closure.
 * @param[out] ret result.
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
history_traits (void *cls,
                const void **ret,
                const char *trait,
                unsigned int index)
{
  struct HistoryState *hs = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_coin_pub (0,
                                       &hs->coin_pub),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Cleanup the state from a "coin history" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
history_cleanup (void *cls,
                 const struct TALER_TESTING_Command *cmd)
{
  struct HistoryState *ss = cls;

  if (NULL != ss->rsh)
  {
    TALER_TESTING_command_incomplete (ss->is,
                                      cmd->label);
    TALER_EXCHANGE_coins_history_cancel (ss->rsh);
    ss->rsh = NULL;
  }
  GNUNET_free (ss);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_coin_history (const char *label,
                                const char *coin_reference,
                                const char *expected_balance,
                                unsigned int expected_response_code)
{
  struct HistoryState *ss;

  GNUNET_assert (NULL != coin_reference);
  ss = GNUNET_new (struct HistoryState);
  ss->coin_reference = coin_reference;
  ss->expected_balance = expected_balance;
  ss->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ss,
      .label = label,
      .run = &history_run,
      .cleanup = &history_cleanup,
      .traits = &history_traits
    };

    return cmd;
  }
}
