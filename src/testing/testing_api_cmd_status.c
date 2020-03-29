/*
  This file is part of TALER
  Copyright (C) 2014-2020 Taler Systems SA

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
 * @file testing/testing_api_cmd_status.c
 * @brief Implement the /reserve/status test command.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"


/**
 * State for a "status" CMD.
 */
struct StatusState
{
  /**
   * Label to the command which created the reserve to check,
   * needed to resort the reserve key.
   */
  const char *reserve_reference;

  /**
   * Handle to the "reserve status" operation.
   */
  struct TALER_EXCHANGE_ReservesGetHandle *rsh;

  /**
   * Expected reserve balance.
   */
  const char *expected_balance;

  /**
   * Public key of the reserve being analyzed.
   */
  const struct TALER_ReservePublicKeyP *reserve_pubp;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;
};


/**
 * Compare @a h1 and @a h2.
 *
 * @param h1 a history entry
 * @param h2 a history entry
 * @return 0 if @a h1 and @a h2 are equal
 */
static int
history_entry_cmp (const struct TALER_EXCHANGE_ReserveHistory *h1,
                   const struct TALER_EXCHANGE_ReserveHistory *h2)
{
  if (h1->type != h2->type)
    return 1;
  switch (h1->type)
  {
  case TALER_EXCHANGE_RTT_CREDIT:
    if ( (0 ==
          TALER_amount_cmp (&h1->amount,
                            &h2->amount)) &&
         (h1->details.in_details.wire_reference_size ==
          h2->details.in_details.wire_reference_size) &&
         (0 == strcasecmp (h1->details.in_details.sender_url,
                           h2->details.in_details.sender_url)) &&
         (0 == memcmp (h1->details.in_details.wire_reference,
                       h2->details.in_details.wire_reference,
                       h1->details.in_details.wire_reference_size)) &&
         (h1->details.in_details.timestamp.abs_value_us ==
          h2->details.in_details.timestamp.abs_value_us) )
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
  case TALER_EXCHANGE_RTT_CLOSE:
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
  }
  GNUNET_assert (0);
  return 1;
}


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
static int
analyze_command (const struct TALER_ReservePublicKeyP *reserve_pub,
                 const struct TALER_TESTING_Command *cmd,
                 unsigned int history_length,
                 const struct TALER_EXCHANGE_ReserveHistory *history,
                 int *found)
{
  if (TALER_TESTING_cmd_is_batch (cmd))
  {
#define BATCH_INDEX 1
    struct TALER_TESTING_Command *cur;
    struct TALER_TESTING_Command *bcmd;

    cur = TALER_TESTING_cmd_batch_get_current (cmd);
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_cmd (cmd,
                                     BATCH_INDEX,
                                     &bcmd))
    {
      GNUNET_break (0);
      return GNUNET_SYSERR;
    }
    for (unsigned int i = 0; NULL != bcmd[i].label; i++)
    {
      struct TALER_TESTING_Command *step = &bcmd[i];

      if (step == cur)
        break; /* if *we* are in a batch, make sure not to analyze commands past 'now' */
      if (GNUNET_OK !=
          analyze_command (reserve_pub,
                           step,
                           history_length,
                           history,
                           found))
        return GNUNET_SYSERR;
    }
    return GNUNET_OK;
  }
  else
  {
    const struct TALER_ReservePublicKeyP *rp;
    const struct TALER_EXCHANGE_ReserveHistory *he;

    if (GNUNET_OK !=
        TALER_TESTING_get_trait_reserve_pub (cmd,
                                             0,
                                             &rp))
      return GNUNET_OK; /* command does nothing for reserves */
    if (0 !=
        GNUNET_memcmp (rp,
                       reserve_pub))
      return GNUNET_OK; /* command affects some _other_ reserve */
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_reserve_history (cmd,
                                                 0,
                                                 &he))
    {
      /* NOTE: only for debugging... */
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
          history_entry_cmp (he,
                             &history[i]))
      {
        found[i] = GNUNET_YES;
        return GNUNET_OK;
      }
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Command `%s' reserve history entry not found\n",
                cmd->label);
    return GNUNET_SYSERR;
  }
}


/**
 * Check that the reserve balance and HTTP response code are
 * both acceptable.
 *
 * @param cls closure.
 * @param http_status HTTP response code.
 * @param ec taler-specific error code.
 * @param json original JSON response from the exchange
 * @param balance current balance in the reserve, NULL on error.
 * @param history_length number of entries in the transaction
 *        history, 0 on error.
 * @param history detailed transaction history, NULL on error.
 */
static void
reserve_status_cb (void *cls,
                   unsigned int http_status,
                   enum TALER_ErrorCode ec,
                   const json_t *json,
                   const struct TALER_Amount *balance,
                   unsigned int history_length,
                   const struct TALER_EXCHANGE_ReserveHistory *history)
{
  struct StatusState *ss = cls;
  struct TALER_TESTING_Interpreter *is = ss->is;
  struct TALER_Amount eb;

  ss->rsh = NULL;
  if (ss->expected_response_code != http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected HTTP response code: %d in %s:%u\n",
                http_status,
                __FILE__,
                __LINE__);
    json_dumpf (json, stderr, 0);
    TALER_TESTING_interpreter_fail (ss->is);
    return;
  }

  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (ss->expected_balance,
                                         &eb));

  if (0 != TALER_amount_cmp (&eb,
                             balance))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected amount in reserve: %s\n",
                TALER_amount_to_string (balance));
    TALER_TESTING_interpreter_fail (ss->is);
    return;
  }
  {
    int found[history_length];

    memset (found, 0, sizeof (found));
    for (unsigned int i = 0; i<=is->ip; i++)
    {
      struct TALER_TESTING_Command *cmd = &is->commands[i];

      if (GNUNET_OK !=
          analyze_command (ss->reserve_pubp,
                           cmd,
                           history_length,
                           history,
                           found))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Entry for command `%s' missing in history\n",
                    cmd->label);
        TALER_TESTING_interpreter_fail (ss->is);
        return;
      }
    }
    for (unsigned int i = 0; i<history_length; i++)
      if (! found[i])
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "History entry at index %u of type %d not justified by command history\n",
                    i,
                    history[i].type);
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
status_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct StatusState *ss = cls;
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
      TALER_TESTING_get_trait_reserve_pub (create_reserve,
                                           0,
                                           &ss->reserve_pubp))
  {
    GNUNET_break (0);
    TALER_LOG_ERROR ("Failed to find reserve_pub for status query\n");
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  ss->rsh = TALER_EXCHANGE_reserves_get (is->exchange,
                                         ss->reserve_pubp,
                                         &reserve_status_cb,
                                         ss);
}


/**
 * Cleanup the state from a "reserve status" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
status_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct StatusState *ss = cls;

  if (NULL != ss->rsh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                ss->is->ip,
                cmd->label);
    TALER_EXCHANGE_reserves_get_cancel (ss->rsh);
    ss->rsh = NULL;
  }
  GNUNET_free (ss);
}


/**
 * Create a "reserve status" command.
 *
 * @param label the command label.
 * @param reserve_reference reference to the reserve to check.
 * @param expected_balance expected balance for the reserve.
 * @param expected_response_code expected HTTP response code.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_status (const char *label,
                          const char *reserve_reference,
                          const char *expected_balance,
                          unsigned int expected_response_code)
{
  struct StatusState *ss;

  GNUNET_assert (NULL != reserve_reference);
  ss = GNUNET_new (struct StatusState);
  ss->reserve_reference = reserve_reference;
  ss->expected_balance = expected_balance;
  ss->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = ss,
      .label = label,
      .run = &status_run,
      .cleanup = &status_cleanup
    };

    return cmd;
  }
}
