/*
  This file is part of TALER
  Copyright (C) 2014-2022 Taler Systems SA

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
 * @file testing/testing_api_cmd_history.c
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
   * Reserve history entry that corresponds to this operation.
   * Will be of type #TALER_EXCHANGE_RTT_HISTORY.
   */
  struct TALER_EXCHANGE_ReserveHistoryEntry reserve_history;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

};


/**
 * Check if @a cmd changed the reserve, if so, find the
 * entry in @a history and set the respective index in @a found
 * to #GNUNET_YES. If the entry is not found, return #GNUNET_SYSERR.
 *
 * @param reserve_pub public key of the reserve for which we have the @a history
 * @param cmd command to analyze for impact on history
 * @param history_length number of entries in @a history and @a found
 * @param history history to check
 * @param[in,out] found array to update
 * @return #GNUNET_OK if @a cmd action on reserve was found in @a history
 */
static enum GNUNET_GenericReturnValue
analyze_command (const struct TALER_ReservePublicKeyP *reserve_pub,
                 const struct TALER_TESTING_Command *cmd,
                 unsigned int history_length,
                 const struct TALER_EXCHANGE_ReserveHistoryEntry *history,
                 bool *found)
{
  if (TALER_TESTING_cmd_is_batch (cmd))
  {
    struct TALER_TESTING_Command *cur;
    struct TALER_TESTING_Command **bcmd;

    cur = TALER_TESTING_cmd_batch_get_current (cmd);
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_batch_cmds (cmd,
                                            &bcmd))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    for (unsigned int i = 0; NULL != (*bcmd)[i].label; i++)
    {
      struct TALER_TESTING_Command *step = &(*bcmd)[i];

      if (GNUNET_OK !=
          analyze_command (reserve_pub,
                           step,
                           history_length,
                           history,
                           found))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Entry for batch step `%s' missing in history\n",
                    step->label);
        return GNUNET_SYSERR;
      }
      if (step == cur)
        break; /* if *we* are in a batch, make sure not to analyze commands past 'now' */
    }
    return GNUNET_OK;
  }

  {
    const struct TALER_ReservePublicKeyP *rp;

    if (GNUNET_OK !=
        TALER_TESTING_get_trait_reserve_pub (cmd,
                                             &rp))
      return GNUNET_OK; /* command does nothing for reserves */
    if (0 !=
        GNUNET_memcmp (rp,
                       reserve_pub))
      return GNUNET_OK; /* command affects some _other_ reserve */
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
                      "Command `%s' has the reserve_pub trait, but does not reserve history trait\n",
                      cmd->label);
        return GNUNET_OK; /* command does nothing for reserves */
      }
      for (unsigned int i = 0; i<history_length; i++)
      {
        if (found[i])
          continue; /* already found, skip */
        if (0 ==
            TALER_TESTING_history_entry_cmp (he,
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
        return GNUNET_SYSERR;
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
  if (MHD_HTTP_OK == rs->hr.http_status)
  {
    const struct TALER_EXCHANGE_Keys *keys;
    const struct TALER_EXCHANGE_GlobalFee *gf;

    ss->reserve_history.type = TALER_EXCHANGE_RTT_HISTORY;
    keys = TALER_EXCHANGE_get_keys (ss->is->exchange);
    GNUNET_assert (NULL != keys);
    gf = TALER_EXCHANGE_get_global_fee (keys,
                                        rs->ts);
    GNUNET_assert (NULL != gf);
    ss->reserve_history.amount = gf->fees.history;
    ss->reserve_history.details.history_details.request_timestamp = rs->ts;
    ss->reserve_history.details.history_details.reserve_sig = *rs->reserve_sig;
  }
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

    memset (found,
            0,
            sizeof (found));
    for (unsigned int i = 0; i<= (unsigned int) is->ip; i++)
    {
      struct TALER_TESTING_Command *cmd = &is->commands[i];

      if (GNUNET_OK !=
          analyze_command (&ss->reserve_pub,
                           cmd,
                           rs->details.ok.history_len,
                           rs->details.ok.history,
                           found))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Entry for command `%s' missing in history\n",
                    cmd->label);
        json_dumpf (rs->hr.reply,
                    stderr,
                    JSON_INDENT (2));
        TALER_TESTING_interpreter_fail (ss->is);
        return;
      }
    }
    for (unsigned int i = 0; i<rs->details.ok.history_len; i++)
      if (! found[i])
      {
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
  ss->rsh = TALER_EXCHANGE_reserves_history (is->exchange,
                                             ss->reserve_priv,
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
    /* history entry MUST be first due to response code logic below! */
    TALER_TESTING_make_trait_reserve_history (0,
                                              &hs->reserve_history),
    TALER_TESTING_make_trait_reserve_pub (&hs->reserve_pub),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait ((hs->expected_response_code == MHD_HTTP_OK)
                                  ? &traits[0]   /* we have reserve history */
                                  : &traits[1],  /* skip reserve history */
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
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ss->is->ip,
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
