/*
  This file is part of TALER
  Copyright (C) 2018-2020 Taler Systems SA

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

  /**
   * URL to free.
   */
  char *d_url;
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
 * Offer internal data to other commands.
 *
 * @param cls closure.
 * @param[out] ret set to the wanted data.
 * @param trait name of the trait.
 * @param index index number of the traits to be returned.
 *
 * @return #GNUNET_OK on success
 */
static int
history_traits (void *cls,
                const void **ret,
                const char *trait,
                unsigned int index)
{
  (void) cls;
  (void) ret;
  (void) trait;
  (void) index;
  /* Must define this function because some callbacks
   * look for certain traits on _all_ the commands. */
  return GNUNET_SYSERR;
}


/**
 * Log which history we expected.  Called when an error occurs.
 *
 * @param h what we expected.
 * @param h_len number of entries in @a h.
 * @param off position of the missmatch.
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
                h[i].details.credit_account_url);
  }
}


/**
 * This function constructs the list of history elements that
 * interest the account number of the caller.  It has two main
 * loops: the first to figure out how many history elements have
 * to be allocated, and the second to actually populate every
 * element.
 *
 * @param is interpreter state (supposedly having the
 *        current CMD pointing at a "history" CMD).
 * @param[out] rh history array to initialize.
 * @return number of entries in @a rh.
 */
static unsigned int
build_history (struct TALER_TESTING_Interpreter *is,
               struct History **rh)
{
  struct HistoryState *hs = is->commands[is->ip].cls;
  unsigned int total;
  unsigned int pos;
  struct History *h;
  const struct TALER_TESTING_Command *add_incoming_cmd;
  int inc;
  int start;
  int end;
  /* #GNUNET_YES whenever either no 'start' value was given for the history
   * query, or the given value is found in the list of all the CMDs. */
  int ok;
  const uint64_t *row_id_start = NULL;

  if (NULL != hs->start_row_reference)
  {
    TALER_LOG_INFO
      ("`%s': start row given via reference `%s'\n",
      TALER_TESTING_interpreter_get_current_label  (is),
      hs->start_row_reference);
    add_incoming_cmd = TALER_TESTING_interpreter_lookup_command
                         (is, hs->start_row_reference);
    GNUNET_assert (NULL != add_incoming_cmd);
    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_uint64 (add_incoming_cmd,
                                                   0,
                                                   &row_id_start));
  }

  GNUNET_assert (0 != hs->num_results);
  if (0 == is->ip)
  {
    TALER_LOG_DEBUG ("Checking history at first CMD..\n");
    *rh = NULL;
    return 0;
  }

  /* AKA 'delta' */
  if (hs->num_results > 0)
  {
    inc = 1;  /* _inc_rement: go forwards */
    start = 0;
    end = is->ip;
  }
  else
  {
    inc = -1; /* decrement: we go backwards */
    start = is->ip - 1;
    end = -1; /* range is exclusive, do look at 0! */
  }

  ok = GNUNET_NO;
  if (NULL == row_id_start)
    ok = GNUNET_YES;
  h = NULL;
  total = 0;
  GNUNET_array_grow (h,
                     total,
                     4);
  pos = 0;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Checking commands %u to %u for debit history\n",
              start,
              end);
  for (int off = start; off != end; off += inc)
  {
    const struct TALER_TESTING_Command *cmd = &is->commands[off];
    const uint64_t *row_id;
    const char *debit_account;
    const char *credit_account;
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
          TALER_TESTING_get_trait_payto (cmd,
                                         TALER_TESTING_PT_DEBIT,
                                         &debit_account)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_payto (cmd,
                                         TALER_TESTING_PT_CREDIT,
                                         &credit_account)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_amount_obj (cmd,
                                              0,
                                              &amount)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_wtid (cmd,
                                        0,
                                        &wtid)) ||
         (GNUNET_OK !=
          TALER_TESTING_get_trait_url (cmd,
                                       TALER_TESTING_UT_EXCHANGE_BASE_URL,
                                       &exchange_base_url)) )
      continue; /* not an event we care about */
    /* Seek "/history/outgoing" starting row.  */
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Command %s is relevant for debit history!\n",
                cmd->label);
    if ( (NULL != row_id_start) &&
         (*row_id_start == *row_id) &&
         (GNUNET_NO == ok) )
    {
      /* Until here, nothing counted. */
      ok = GNUNET_YES;
      continue;
    }
    /* when 'start' was _not_ given, then ok == GNUNET_YES */
    if (GNUNET_NO == ok)
      continue; /* skip until we find the marker */
    if (total >= GNUNET_MAX (hs->num_results,
                             -hs->num_results) )
    {
      TALER_LOG_DEBUG ("Hit history limit\n");
      break;
    }
    TALER_LOG_INFO ("Found history: %s->%s for account %s\n",
                    debit_account,
                    credit_account,
                    hs->account_url);
    /* found matching record, make sure we have room */
    if (pos == total)
      GNUNET_array_grow (h,
                         total,
                         pos * 2);
    h[pos].c_url = GNUNET_strdup (credit_account);
    h[pos].d_url = GNUNET_strdup (debit_account);
    h[pos].details.credit_account_url = h[pos].c_url;
    h[pos].details.debit_account_url = h[pos].d_url;
    h[pos].details.amount = *amount;
    h[pos].row_id = *row_id;
    h[pos].details.wtid = *wtid;
    h[pos].details.exchange_base_url = exchange_base_url;
    pos++;
  }
  GNUNET_assert (GNUNET_YES == ok);
  GNUNET_array_grow (h,
                     total,
                     pos);
  if (0 == pos)
    TALER_LOG_DEBUG ("Empty debit history computed\n");
  *rh = h;
  return total;
}


/**
 * Check that the "/history/outgoing" response matches the
 * CMD whose offset in the list of CMDs is @a off.
 *
 * @param is the interpreter state.
 * @param h expected history
 * @param total number of entries in @a h
 * @param off the offset (of the CMD list) where the command
 *        to check is.
 * @param details the expected transaction details.
 * @return #GNUNET_OK if the transaction is what we expect.
 */
static int
check_result (struct TALER_TESTING_Interpreter *is,
              struct History *h,
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
       (0 != strcasecmp (h[off].details.credit_account_url,
                         details->credit_account_url)) )
  {
    GNUNET_break (0);
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
 * @param http_status HTTP response code, #MHD_HTTP_OK (200)
 *        for successful status request 0 if the bank's reply is
 *        bogus (fails to follow the protocol),
 *        #MHD_HTTP_NO_CONTENT if there are no more results; on
 *        success the last callback is always of this status
 *        (even if `abs(num_results)` were already returned).
 * @param ec taler status code.
 * @param row_id monotonically increasing counter corresponding to
 *        the transaction.
 * @param details details about the wire transfer.
 * @param json detailed response from the HTTPD, or NULL if
 *        reply was not in JSON.
 * @return #GNUNET_OK to continue, #GNUNET_SYSERR to abort iteration
 */
static int
history_cb (void *cls,
            unsigned int http_status,
            enum TALER_ErrorCode ec,
            uint64_t row_id,
            const struct TALER_BANK_DebitDetails *details,
            const json_t *json)
{
  struct TALER_TESTING_Interpreter *is = cls;
  struct HistoryState *hs = is->commands[is->ip].cls;

  (void) row_id;
  if (NULL == details)
  {
    hs->hh = NULL;
    if ( (hs->results_obtained != hs->total) ||
         (GNUNET_YES == hs->failed) ||
         (MHD_HTTP_NO_CONTENT != http_status) )
    {
      GNUNET_break (0);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Expected history of length %u, got %llu;"
                  " HTTP status code: %u/%d, failed: %d\n",
                  hs->total,
                  (unsigned long long) hs->results_obtained,
                  http_status,
                  (int) ec,
                  hs->failed);
      print_expected (hs->h,
                      hs->total,
                      UINT_MAX);
      TALER_TESTING_interpreter_fail (is);
      return GNUNET_SYSERR;
    }
    TALER_TESTING_interpreter_next (is);
    return GNUNET_OK;
  }
  if (MHD_HTTP_OK != http_status)
  {
    hs->hh = NULL;
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unwanted response code from /history/outgoing: %u\n",
                http_status);
    TALER_TESTING_interpreter_fail (is);
    return GNUNET_SYSERR;
  }

  /* check current element */
  if (GNUNET_OK != check_result (is,
                                 hs->h,
                                 hs->total,
                                 hs->results_obtained,
                                 details))
  {
    char *acc;

    GNUNET_break (0);
    acc = json_dumps (json,
                      JSON_COMPACT);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Result %u was `%s'\n",
                (unsigned int) hs->results_obtained++,
                acc);
    if (NULL != acc)
      free (acc);
    hs->failed = GNUNET_YES;
    return GNUNET_SYSERR;
  }
  hs->results_obtained++;
  return GNUNET_OK;
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
        TALER_TESTING_get_trait_uint64 (history_cmd,
                                        0,
                                        &row_ptr))
      TALER_TESTING_FAIL (is);
    else
      row_id = *row_ptr;
    TALER_LOG_DEBUG ("row id (from trait) is %llu\n",
                     (unsigned long long) row_id);
  }
  hs->total = build_history (is, &hs->h);
  hs->hh = TALER_BANK_debit_history (is->ctx,
                                     &hs->auth,
                                     row_id,
                                     hs->num_results,
                                     &history_cb,
                                     is);
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
    TALER_LOG_WARNING ("/history/outgoing did not complete\n");
    TALER_BANK_debit_history_cancel (hs->hh);
  }
  for (unsigned int off = 0; off<hs->total; off++)
  {
    GNUNET_free (hs->h[off].c_url);
    GNUNET_free (hs->h[off].d_url);
  }
  GNUNET_free_non_null (hs->h);
  GNUNET_free (hs);
}


/**
 * Make a "history" CMD.
 *
 * @param label command label.
 * @param auth login data to use
 * @param start_row_reference reference to a command that can
 *        offer a row identifier, to be used as the starting row
 *        to accept in the result.
 * @param num_results how many rows we want in the result.
 * @return the command.
 */
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
      .cleanup = &history_cleanup,
      .traits = &history_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_bank_history_debit.c */
