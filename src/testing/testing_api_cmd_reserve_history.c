/*
  This file is part of TALER
  Copyright (C) 2014-2024 Taler Systems SA

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
 * @file testing/testing_api_cmd_reserve_history.c
 * @brief Implement the /reserve/history test command.
 * @author Marcello Stanisci
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
   * Public key of the reserve being analyzed.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Label to the command which created the reserve to check,
   * needed to resort the reserve key.
   */
  const char *reserve_reference;

  /**
   * Handle to the "reserve history" operation.
   */
  struct TALER_EXCHANGE_ReservesHistoryHandle *rsh;

  /**
   * Expected reserve balance.
   */
  const char *expected_balance;

  /**
   * Private key of the reserve being analyzed.
   */
  const struct TALER_ReservePrivateKeyP *reserve_priv;

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
   * Reserve public key we are looking at.
   */
  const struct TALER_ReservePublicKeyP *reserve_pub;

  /**
   * Length of the @e history array.
   */
  unsigned int history_length;

  /**
   * Array of history items to match.
   */
  const struct TALER_EXCHANGE_ReserveHistoryEntry *history;

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
  const struct TALER_EXCHANGE_ReserveHistoryEntry *h1,
  const struct TALER_EXCHANGE_ReserveHistoryEntry *h2)
{
  if (h1->type != h2->type)
    return 1;
  switch (h1->type)
  {
  case TALER_EXCHANGE_RTT_CREDIT:
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (0 ==
          TALER_full_payto_cmp (h1->details.in_details.sender_url,
                                h2->details.in_details.sender_url)) &&
         (h1->details.in_details.wire_reference ==
          h2->details.in_details.wire_reference) &&
         (GNUNET_TIME_timestamp_cmp (h1->details.in_details.timestamp,
                                     ==,
                                     h2->details.in_details.timestamp)) )
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_WITHDRAWAL:
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (0 ==
          TALER_amount_cmp (&h1->details.withdraw.fee,
                            &h2->details.withdraw.fee)) )
      /* testing_api_cmd_withdraw doesn't set the out_authorization_sig,
         so we cannot test for it here. but if the amount matches,
         that should be good enough. */
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_AGEWITHDRAWAL:
    /* testing_api_cmd_age_withdraw doesn't set the out_authorization_sig,
       so we cannot test for it here. but if the amount matches,
       that should be good enough. */
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (0 ==
          TALER_amount_cmp (&h1->details.age_withdraw.fee,
                            &h2->details.age_withdraw.fee)) &&
         (h1->details.age_withdraw.max_age ==
          h2->details.age_withdraw.max_age))
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_RECOUP:
    /* exchange_sig, exchange_pub and timestamp are NOT available
       from the original recoup response, hence here NOT check(able/ed) */
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.recoup_details.coin_pub,
                         &h2->details.recoup_details.coin_pub)) )
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_CLOSING:
    /* testing_api_cmd_exec_closer doesn't set the
       receiver_account_details, exchange_sig, exchange_pub or wtid or timestamp
       so we cannot test for it here. but if the amount matches,
       that should be good enough. */
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (0 ==
          TALER_amount_cmp (&h1->details.close_details.fee,
                            &h2->details.close_details.fee)) )
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_MERGE:
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (0 ==
          TALER_amount_cmp (&h1->details.merge_details.purse_fee,
                            &h2->details.merge_details.purse_fee)) &&
         (GNUNET_TIME_timestamp_cmp (h1->details.merge_details.merge_timestamp,
                                     ==,
                                     h2->details.merge_details.merge_timestamp))
         &&
         (GNUNET_TIME_timestamp_cmp (h1->details.merge_details.purse_expiration,
                                     ==,
                                     h2->details.merge_details.purse_expiration)
         )
         &&
         (0 ==
          GNUNET_memcmp (&h1->details.merge_details.merge_pub,
                         &h2->details.merge_details.merge_pub)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.merge_details.h_contract_terms,
                         &h2->details.merge_details.h_contract_terms)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.merge_details.purse_pub,
                         &h2->details.merge_details.purse_pub)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.merge_details.reserve_sig,
                         &h2->details.merge_details.reserve_sig)) &&
         (h1->details.merge_details.min_age ==
          h2->details.merge_details.min_age) &&
         (h1->details.merge_details.flags ==
          h2->details.merge_details.flags) )
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_OPEN:
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (GNUNET_TIME_timestamp_cmp (
            h1->details.open_request.request_timestamp,
            ==,
            h2->details.open_request.request_timestamp)) &&
         (GNUNET_TIME_timestamp_cmp (
            h1->details.open_request.reserve_expiration,
            ==,
            h2->details.open_request.reserve_expiration)) &&
         (h1->details.open_request.purse_limit ==
          h2->details.open_request.purse_limit) &&
         (0 ==
          TALER_amount_cmp (&h1->details.open_request.reserve_payment,
                            &h2->details.open_request.reserve_payment)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.open_request.reserve_sig,
                         &h2->details.open_request.reserve_sig)) )
      return 0;
    return 1;
  case TALER_EXCHANGE_RTT_CLOSE:
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (GNUNET_TIME_timestamp_cmp (
            h1->details.close_request.request_timestamp,
            ==,
            h2->details.close_request.request_timestamp)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.close_request.target_account_h_payto,
                         &h2->details.close_request.target_account_h_payto)) &&
         (0 ==
          GNUNET_memcmp (&h1->details.close_request.reserve_sig,
                         &h2->details.close_request.reserve_sig)) )
      return 0;
    return 1;
  }
  GNUNET_assert (0);
  return 1;
}


/**
 * Check if @a cmd changed the reserve, if so, find the
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
  const struct TALER_ReservePublicKeyP *reserve_pub = ac->reserve_pub;
  const struct TALER_EXCHANGE_ReserveHistoryEntry *history = ac->history;
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

  {
    const struct TALER_ReservePublicKeyP *rp;

    if (GNUNET_OK !=
        TALER_TESTING_get_trait_reserve_pub (cmd,
                                             &rp))
      return; /* command does nothing for reserves */
    if (0 !=
        GNUNET_memcmp (rp,
                       reserve_pub))
      return; /* command affects some _other_ reserve */
    for (unsigned int j = 0; true; j++)
    {
      const struct TALER_EXCHANGE_ReserveHistoryEntry *he;
      bool matched = false;

      if (GNUNET_OK !=
          TALER_TESTING_get_trait_reserve_history (cmd,
                                                   j,
                                                   &he))
      {
        /* NOTE: only for debugging... */
        if (0 == j)
          GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
                      "Command `%s' has the reserve_pub, but lacks reserve history trait\n",
                      cmd->label);
        return; /* command does nothing for reserves */
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
                    "Command `%s' reserve history entry #%u not found\n",
                    cmd->label,
                    j);
        ac->failure = true;
        return;
      }
    }
  }
}


/**
 * Check that the reserve balance and HTTP response code are
 * both acceptable.
 *
 * @param cls closure.
 * @param rs HTTP response details
 */
static void
reserve_history_cb (void *cls,
                    const struct TALER_EXCHANGE_ReserveHistory *rs)
{
  struct HistoryState *ss = cls;
  struct TALER_TESTING_Interpreter *is = ss->is;
  struct TALER_Amount eb;

  ss->rsh = NULL;
  if (ss->expected_response_code != rs->hr.http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected HTTP response code: %d in %s:%u\n",
                rs->hr.http_status,
                __FILE__,
                __LINE__);
    json_dumpf (rs->hr.reply,
                stderr,
                0);
    TALER_TESTING_interpreter_fail (ss->is);
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
                "Unexpected amount in reserve: %s\n",
                TALER_amount_to_string (&rs->details.ok.balance));
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Expected balance of: %s\n",
                TALER_amount_to_string (&eb));
    TALER_TESTING_interpreter_fail (ss->is);
    return;
  }
  {
    bool found[rs->details.ok.history_len];
    struct AnalysisContext ac = {
      .reserve_pub = &ss->reserve_pub,
      .history = rs->details.ok.history,
      .history_length = rs->details.ok.history_len,
      .found = found
    };

    memset (found,
            0,
            sizeof (found));
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
    for (unsigned int i = 0; i<rs->details.ok.history_len; i++)
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
  const struct TALER_TESTING_Command *create_reserve;

  ss->is = is;
  create_reserve
    = TALER_TESTING_interpreter_lookup_command (is,
                                                ss->reserve_reference);
  if (NULL == create_reserve)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  if (GNUNET_OK !=
      TALER_TESTING_get_trait_reserve_priv (create_reserve,
                                            &ss->reserve_priv))
  {
    GNUNET_break (0);
    TALER_LOG_ERROR ("Failed to find reserve_priv for history query\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_CRYPTO_eddsa_key_get_public (&ss->reserve_priv->eddsa_priv,
                                      &ss->reserve_pub.eddsa_pub);
  ss->rsh = TALER_EXCHANGE_reserves_history (
    TALER_TESTING_interpreter_get_context (is),
    TALER_TESTING_get_exchange_url (is),
    TALER_TESTING_get_keys (is),
    ss->reserve_priv,
    0,
    &reserve_history_cb,
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
    TALER_TESTING_make_trait_reserve_pub (&hs->reserve_pub),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Cleanup the state from a "reserve history" CMD, and possibly
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
    TALER_EXCHANGE_reserves_history_cancel (ss->rsh);
    ss->rsh = NULL;
  }
  GNUNET_free (ss);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_reserve_history (const char *label,
                                   const char *reserve_reference,
                                   const char *expected_balance,
                                   unsigned int expected_response_code)
{
  struct HistoryState *ss;

  GNUNET_assert (NULL != reserve_reference);
  ss = GNUNET_new (struct HistoryState);
  ss->reserve_reference = reserve_reference;
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
