/*
  This file is part of TALER
  Copyright (C) 2018-2021 Taler Systems SA

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
 * @file testing/testing_api_cmd_bank_history_debit.c
 * @brief command to check the /history/outgoing API from the bank.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_testing_lib.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"

/**
 * Item in the transaction history, as reconstructed from the
 * command history.
 */
struct History
{

  /**
   * Wire details.
   */
  struct TALER_BANK_DebitDetails details;

  /**
   * Serial ID of the wire transfer.
   */
  uint64_t row_id;

  /**
   * URL to free.
   */
  char *c_url;

};


/**
 * State for a "history" CMD.
 */
struct HistoryState
{
  /**
   * Base URL of the account offering the "history" operation.
   */
  const char *account_url;

  /**
   * Reference to command defining the
   * first row number we want in the result.
   */
  const char *start_row_reference;

  /**
   * How many rows we want in the result, _at most_,
   * and ascending/descending.
   */
  long long num_results;

  /**
   * Login data to use to authenticate.
   */
  struct TALER_BANK_AuthenticationData auth;

  /**
   * Handle to a pending "history" operation.
   */
  struct TALER_BANK_DebitHistoryHandle *hh;

  /**
   * Our interpreter.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Expected number of results (= rows).
   */
  uint64_t results_obtained;

  /**
   * Set to #GNUNET_YES if the callback detects something
   * unexpected.
   */
  int failed;

  /**
   * Expected history.
   */
  struct History *h;

  /**
   * Length of @e h
   */
  unsigned int total;

};


/**
 * Log which history we expected.  Called when an error occurs.
 *
 * @param h what we expected.
 * @param h_len number of entries in @a h.
 * @param off position of the mismatch.
 */
static void
print_expected (struct History *h,
                unsigned int h_len,
                unsigned int off)
{
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Transaction history (debit) mismatch at position %u/%u\n",
              off,
              h_len);
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Expected history:\n");
  for (unsigned int i = 0; i<h_len; i++)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "H(%u): %s (serial: %llu, subject: %s, counterpart: %s)\n",
                i,
                TALER_amount2s (&h[i].details.amount),
                (unsigned long long) h[i].row_id,
                TALER_B2S (&h[i].details.wtid),
                h[i].details.credit_account_uri.full_payto);
  }
}


/**
 * Closure for command_cb().
 */
struct IteratorContext
{
  /**
   * Array of history items to return.
   */
  struct History *h;

  /**
   * Set to the row ID from where on we should actually process history items,
   * or NULL if we should process all of them.
   */
  const uint64_t *row_id_start;

  /**
   * History state we are working on.
   */
  struct HistoryState *hs;

  /**
   * Current length of the @e h array.
   */
  unsigned int total;

  /**
   * Current write position in @e h array.
   */
  unsigned int pos;

  /**
   * Ok equals True whenever a starting row_id was provided AND was found
   * among the CMDs, OR no starting row was given in the first place.
   */
  bool ok;

};


/**
 * Helper function of build_history() that expands
 * the history for each relevant command encountered.
 *
 * @param[in,out] cls our `struct IteratorContext`
 * @param cmd a command to process
 */
static void
command_cb (void *cls,
            const struct TALER_TESTING_Command *cmd)
{
  struct IteratorContext *ic = cls;
  struct HistoryState *hs = ic->hs;
  const uint64_t *row_id;
  const struct TALER_FullPayto *debit_account;
  const struct TALER_FullPayto *credit_account;
  const struct TALER_Amount *amount;
  const struct TALER_WireTransferIdentifierRawP *wtid;
  const char *exchange_base_url;

  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking if command %s is relevant for debit history\n",
              cmd->label);
  if ( (GNUNET_OK !=
        TALER_TESTING_get_trait_bank_row (cmd,
                                          &row_id)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_debit_payto_uri (cmd,
                                                 &debit_account)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_credit_payto_uri (cmd,
                                                  &credit_account)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_amount (cmd,
                                        &amount)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_wtid (cmd,
                                      &wtid)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_exchange_url (cmd,
                                              &exchange_base_url)) )
    return;   /* not an event we care about */
  /* Seek "/history/outgoing" starting row.  */
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Command %s is relevant for debit history!\n",
              cmd->label);
  if ( (NULL != ic->row_id_start) &&
       (*(ic->row_id_start) == *row_id) &&
       (! ic->ok) )
  {
    /* Until here, nothing counted. */
    ic->ok = true;
    return;
  }
  /* when 'start' was _not_ given, then ok == GNUNET_YES */
  if (! ic->ok)
    return;   /* skip until we find the marker */
  if (ic->total >= GNUNET_MAX (hs->num_results,
                               -hs->num_results) )
  {
    TALER_LOG_DEBUG ("Hit history limit\n");
    return;
  }
  TALER_LOG_INFO ("Found history: %s->%s for account %s\n",
                  debit_account->full_payto,
                  credit_account->full_payto,
                  hs->account_url);
  /* found matching record, make sure we have room */
  if (ic->pos == ic->total)
    GNUNET_array_grow (ic->h,
                       ic->total,
                       ic->pos * 2);
  ic->h[ic->pos].c_url = GNUNET_strdup (credit_account->full_payto);
  ic->h[ic->pos].details.credit_account_uri.full_payto
    = ic->h[ic->pos].c_url;
  ic->h[ic->pos].details.amount = *amount;
  ic->h[ic->pos].row_id = *row_id;
  ic->h[ic->pos].details.wtid = *wtid;
  ic->h[ic->pos].details.exchange_base_url = exchange_base_url;
  ic->pos++;
}


/**
 * This function constructs the list of history elements that
 * interest the account number of the caller.  It has two main
 * loops: the first to figure out how many history elements have
 * to be allocated, and the second to actually populate every
 * element.
 *
 * @param hs history state command context
 * @param[out] rh history array to initialize.
 * @return number of entries in @a rh.
 */
static unsigned int
build_history (struct HistoryState *hs,
               struct History **rh)
{
  struct TALER_TESTING_Interpreter *is = hs->is;
  struct IteratorContext ic = {
    .hs = hs
  };

  if (NULL != hs->start_row_reference)
  {
    const struct TALER_TESTING_Command *add_incoming_cmd;

    TALER_LOG_INFO (
      "`%s': start row given via reference `%s'\n",
      TALER_TESTING_interpreter_get_current_label  (is),
      hs->start_row_reference);
    add_incoming_cmd = TALER_TESTING_interpreter_lookup_command (
      is,
      hs->start_row_reference);
    GNUNET_assert (NULL != add_incoming_cmd);
    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_row (add_incoming_cmd,
                                                &ic.row_id_start));
  }

  ic.ok = false;
  if (NULL == ic.row_id_start)
    ic.ok = true;
  GNUNET_array_grow (ic.h,
                     ic.total,
                     4);
  GNUNET_assert (0 != hs->num_results);
  TALER_TESTING_iterate (is,
                         hs->num_results > 0,
                         &command_cb,
                         &ic);
  GNUNET_assert (ic.ok);
  GNUNET_array_grow (ic.h,
                     ic.total,
                     ic.pos);
  if (0 == ic.pos)
    TALER_LOG_DEBUG ("Empty credit history computed\n");
  *rh = ic.h;
  return ic.pos;
}


/**
 * Check that the "/history/outgoing" response matches the
 * CMD whose offset in the list of CMDs is @a off.
 *
 * @param h expected history
 * @param total number of entries in @a h
 * @param off the offset (of the CMD list) where the command
 *        to check is.
 * @param details the expected transaction details.
 * @return #GNUNET_OK if the transaction is what we expect.
 */
static enum GNUNET_GenericReturnValue
check_result (struct History *h,
              uint64_t total,
              unsigned int off,
              const struct TALER_BANK_DebitDetails *details)
{
  if (off >= total)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Test says history has at most %u"
                " results, but got result #%u to check\n",
                (unsigned int) total,
                off);
    print_expected (h,
                    total,
                    off);
    return GNUNET_SYSERR;
  }
  if ( (0 != GNUNET_memcmp (&h[off].details.wtid,
                            &details->wtid)) ||
       (0 != TALER_amount_cmp (&h[off].details.amount,
                               &details->amount)) ||
       (0 != TALER_full_payto_normalize_and_cmp (
          h[off].details.credit_account_uri,
          details->credit_account_uri)) )
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "expected debit_account_uri: %s with %s for %s\n",
                h[off].details.credit_account_uri.full_payto,
                TALER_amount2s (&h[off].details.amount),
                TALER_B2S (&h[off].details.wtid));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "actual debit_account_uri: %s with %s for %s\n",
                details->credit_account_uri.full_payto,
                TALER_amount2s (&details->amount),
                TALER_B2S (&details->wtid));
    print_expected (h,
                    total,
                    off);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


/**
 * This callback will (1) check that the HTTP response code
 * is acceptable and (2) that the history is consistent.  The
 * consistency is checked by going through all the past CMDs,
 * reconstructing then the expected history as of those, and
 * finally check it against what the bank returned.
 *
 * @param cls closure.
 * @param dhr http response details
 */
static void
history_cb (void *cls,
            const struct TALER_BANK_DebitHistoryResponse *dhr)
{
  struct HistoryState *hs = cls;
  struct TALER_TESTING_Interpreter *is = hs->is;

  hs->hh = NULL;
  switch (dhr->http_status)
  {
  case 0:
    GNUNET_break (0);
    goto error;
  case MHD_HTTP_OK:
    for (unsigned int i = 0; i<dhr->details.ok.details_length; i++)
    {
      const struct TALER_BANK_DebitDetails *dd =
        &dhr->details.ok.details[i];

      /* check current element */
      if (GNUNET_OK !=
          check_result (hs->h,
                        hs->total,
                        hs->results_obtained,
                        dd))
      {
        GNUNET_break (0);
        json_dumpf (dhr->response,
                    stderr,
                    JSON_COMPACT);
        hs->failed = true;
        hs->hh = NULL;
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      hs->results_obtained++;
    }
    TALER_TESTING_interpreter_next (is);
    return;
  case MHD_HTTP_NO_CONTENT:
    if (0 == hs->total)
    {
      /* not found is OK for empty history */
      TALER_TESTING_interpreter_next (is);
      return;
    }
    GNUNET_break (0);
    goto error;
  case MHD_HTTP_NOT_FOUND:
    if (0 == hs->total)
    {
      /* not found is OK for empty history */
      TALER_TESTING_interpreter_next (is);
      return;
    }
    GNUNET_break (0);
    goto error;
  default:
    hs->hh = NULL;
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unwanted response code from /history/incoming: %u\n",
                dhr->http_status);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
error:
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Expected history of length %u, got %llu;"
              " HTTP status code: %u/%d, failed: %d\n",
              hs->total,
              (unsigned long long) hs->results_obtained,
              dhr->http_status,
              (int) dhr->ec,
              hs->failed ? 1 : 0);
  print_expected (hs->h,
                  hs->total,
                  UINT_MAX);
  TALER_TESTING_interpreter_fail (is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
history_run (void *cls,
             const struct TALER_TESTING_Command *cmd,
             struct TALER_TESTING_Interpreter *is)
{
  struct HistoryState *hs = cls;
  uint64_t row_id = (hs->num_results > 0) ? 0 : UINT64_MAX;
  const uint64_t *row_ptr;

  (void) cmd;
  hs->is = is;
  /* Get row_id from trait. */
  if (NULL != hs->start_row_reference)
  {
    const struct TALER_TESTING_Command *history_cmd;

    history_cmd
      = TALER_TESTING_interpreter_lookup_command (is,
                                                  hs->start_row_reference);

    if (NULL == history_cmd)
      TALER_TESTING_FAIL (is);
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_row (history_cmd,
                                     &row_ptr))
      TALER_TESTING_FAIL (is);
    else
      row_id = *row_ptr;
    TALER_LOG_DEBUG ("row id (from trait) is %llu\n",
                     (unsigned long long) row_id);
  }
  hs->total = build_history (hs,
                             &hs->h);
  hs->hh = TALER_BANK_debit_history (
    TALER_TESTING_interpreter_get_context (is),
    &hs->auth,
    row_id,
    hs->num_results,
    GNUNET_TIME_UNIT_ZERO,
    &history_cb,
    hs);
  GNUNET_assert (NULL != hs->hh);
}


/**
 * Free the state from a "history" CMD, and possibly cancel
 * a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
history_cleanup (void *cls,
                 const struct TALER_TESTING_Command *cmd)
{
  struct HistoryState *hs = cls;

  (void) cmd;
  if (NULL != hs->hh)
  {
    TALER_TESTING_command_incomplete (hs->is,
                                      cmd->label);
    TALER_BANK_debit_history_cancel (hs->hh);
  }
  for (unsigned int off = 0; off<hs->total; off++)
  {
    GNUNET_free (hs->h[off].c_url);
  }
  GNUNET_free (hs->h);
  GNUNET_free (hs);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_debits (const char *label,
                               const struct TALER_BANK_AuthenticationData *auth,
                               const char *start_row_reference,
                               long long num_results)
{
  struct HistoryState *hs;

  hs = GNUNET_new (struct HistoryState);
  hs->account_url = auth->wire_gateway_url;
  hs->start_row_reference = start_row_reference;
  hs->num_results = num_results;
  hs->auth = *auth;

  {
    struct TALER_TESTING_Command cmd = {
      .label = label,
      .cls = hs,
      .run = &history_run,
      .cleanup = &history_cleanup
    };

    return cmd;
  }
}


/* end of testing_api_cmd_bank_history_debit.c */
