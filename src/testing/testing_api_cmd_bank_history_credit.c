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
 * @file testing/testing_api_cmd_bank_history_credit.c
 * @brief command to check the /history/incoming API from the bank.
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
  struct TALER_BANK_CreditDetails details;

  /**
   * Serial ID of the wire transfer.
   */
  uint64_t row_id;

  /**
   * URL to free.
   */
  char *url;
};


/**
 * State for a "history" CMD.
 */
struct HistoryState
{
  /**
   * Base URL of the account offering the "history" operation.
   */
  char *account_url;

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
   * Handle to a pending "history" operation.
   */
  struct TALER_BANK_CreditHistoryHandle *hh;

  /**
   * The interpreter.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Authentication data for the operation.
   */
  struct TALER_BANK_AuthenticationData auth;

  /**
   * Expected number of results (= rows).
   */
  uint64_t results_obtained;

  /**
   * Set to true if the callback detects something
   * unexpected.
   */
  bool failed;

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
              "Transaction history (credit) mismatch at position %u/%u\n",
              off,
              h_len);
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Expected history:\n");
  for (unsigned int i = 0; i<h_len; i++)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "H(%u): %s (serial: %llu, subject: %s,"
                " counterpart: %s)\n",
                i,
                TALER_amount2s (&h[i].details.amount),
                (unsigned long long) h[i].row_id,
                TALER_B2S (&h[i].details.reserve_pub),
                h[i].details.debit_account_uri);
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
  const char *credit_account;
  const char *debit_account;
  const struct TALER_Amount *amount;
  const struct TALER_ReservePublicKeyP *reserve_pub;
  const char *exchange_credit_url;

  /**
   * The following command allows us to skip over those CMDs
   * that do not offer a "row_id" trait.  Such skipped CMDs are
   * not interesting for building a history.
   */
  if ( (GNUNET_OK !=
        TALER_TESTING_get_trait_bank_row (cmd,
                                          &row_id)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_credit_payto_uri (cmd,
                                                  &credit_account)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_debit_payto_uri (cmd,
                                                 &debit_account)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_amount (cmd,
                                        &amount)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_reserve_pub (cmd,
                                             &reserve_pub)) ||
       (GNUNET_OK !=
        TALER_TESTING_get_trait_exchange_bank_account_url (
          cmd,
          &exchange_credit_url)) )
    return;   // Not an interesting event

  /**
   * Is the interesting event a match with regard to
   * the row_id value?  If yes, store this condition
   * to the state and analyze the next CMDs.
   */
  if ( (NULL != ic->row_id_start) &&
       (*(ic->row_id_start) == *row_id) &&
       (! ic->ok) )
  {
    ic->ok = true;
    return;
  }
  /**
   * The interesting event didn't match the wanted
   * row_id value, analyze the next CMDs.  Note: this
   * branch is relevant only when row_id WAS given.
   */
  if (! ic->ok)
    return;
  if (0 != strcasecmp (hs->account_url,
                       exchange_credit_url))
    return;   // Account mismatch
  if (ic->total >= GNUNET_MAX (hs->num_results,
                               -hs->num_results) )
  {
    TALER_LOG_DEBUG ("Hit history limit\n");
    return;
  }
  TALER_LOG_INFO ("Found history: %s->%s for account %s\n",
                  debit_account,
                  credit_account,
                  hs->account_url);
  /* found matching record, make sure we have room */
  if (ic->pos == ic->total)
    GNUNET_array_grow (ic->h,
                       ic->total,
                       ic->pos * 2);
  ic->h[ic->pos].url = GNUNET_strdup (debit_account);
  ic->h[ic->pos].details.debit_account_uri = ic->h[ic->pos].url;
  ic->h[ic->pos].details.amount = *amount;
  ic->h[ic->pos].row_id = *row_id;
  ic->h[ic->pos].details.reserve_pub = *reserve_pub;
  ic->pos++;
}


/**
 * This function constructs the list of history elements that
 * interest the account number of the caller.  It has two main
 * loops: the first to figure out how many history elements have
 * to be allocated, and the second to actually populate every
 * element.
 *
 * @param hs history state
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

    TALER_LOG_INFO ("`%s': start row given via reference `%s'\n",
                    TALER_TESTING_interpreter_get_current_label (is),
                    hs->start_row_reference);
    add_incoming_cmd
      = TALER_TESTING_interpreter_lookup_command (is,
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
 * Normalize IBAN-based payto URI in @a in.
 *
 * @param in input payto://-URI to normalize
 * @return normalized IBAN for the test
 */
static char *
normalize (const char *in)
{
  char *npt;
  const char *q = strchr (in,
                          '?');
  const char *mptr;
  const char *bic;
  const char *iban;

  if (NULL == q)
    npt = GNUNET_strdup (in);
  else
    npt = GNUNET_strndup (in,
                          q - in);
  if (0 != strncasecmp (npt,
                        "payto://",
                        strlen ("payto://")))
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Invalid payto: %s\n",
                npt);
    GNUNET_free (npt);
    return NULL;
  }
  mptr = npt + strlen ("payto://");
  bic = strchr (mptr, '/');
  if (NULL == bic)
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Invalid payto: %s\n",
                npt);
    GNUNET_free (npt);
    return NULL;
  }
  bic++;
  iban = strchr (bic, '/');
  if (NULL != iban)
  {
    /* need to remove bic */
    char *n;

    iban++;
    GNUNET_asprintf (&n,
                     "payto://%.*s/%s",
                     (int) ((bic - mptr) - 1),
                     mptr,
                     iban);
    GNUNET_free (npt);
    npt = n;
  }
  return npt;
}


/**
 * Check that the "/history/incoming" response matches the
 * CMD whose offset in the list of CMDs is @a off.
 *
 * @param h expected history (array)
 * @param total length of @a h
 * @param off the offset (of the CMD list) where the command
 *        to check is.
 * @param details the expected transaction details.
 * @return #GNUNET_OK if the transaction is what we expect.
 */
static enum GNUNET_GenericReturnValue
check_result (struct History *h,
              unsigned int total,
              unsigned int off,
              const struct TALER_BANK_CreditDetails *details)
{
  char *u1;
  char *u2;

  if (off >= total)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Test says history has at most %u"
                " results, but got result #%u to check\n",
                total,
                off);
    print_expected (h,
                    total,
                    off);
    return GNUNET_SYSERR;
  }
  u1 = normalize (h[off].details.debit_account_uri);
  if (NULL == u1)
    return GNUNET_SYSERR;
  u2 = normalize (details->debit_account_uri);
  if (NULL == u2)
  {
    GNUNET_free (u1);
    return GNUNET_SYSERR;
  }
  if ( (0 != GNUNET_memcmp (&h[off].details.reserve_pub,
                            &details->reserve_pub)) ||
       (0 != TALER_amount_cmp (&h[off].details.amount,
                               &details->amount)) ||
       (0 != strcasecmp (u1,
                         u2)) )
  {
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "expected debit_account_uri: %s with %s for %s\n",
                u1,
                TALER_amount2s (&h[off].details.amount),
                TALER_B2S (&h[off].details.reserve_pub));
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "actual debit_account_uri: %s with %s for %s\n",
                u2,
                TALER_amount2s (&details->amount),
                TALER_B2S (&details->reserve_pub));
    print_expected (h,
                    total,
                    off);
    GNUNET_free (u1);
    GNUNET_free (u2);
    return GNUNET_SYSERR;
  }
  GNUNET_free (u1);
  GNUNET_free (u2);
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
 * @param chr http response details
 */
static void
history_cb (void *cls,
            const struct TALER_BANK_CreditHistoryResponse *chr)
{
  struct HistoryState *hs = cls;
  struct TALER_TESTING_Interpreter *is = hs->is;

  hs->hh = NULL;
  switch (chr->http_status)
  {
  case 0:
    GNUNET_break (0);
    goto error;
  case MHD_HTTP_OK:
    for (unsigned int i = 0; i<chr->details.ok.details_length; i++)
    {
      const struct TALER_BANK_CreditDetails *cd =
        &chr->details.ok.details[i];

      /* check current element */
      if (GNUNET_OK !=
          check_result (hs->h,
                        hs->total,
                        hs->results_obtained,
                        cd))
      {
        GNUNET_break (0);
        json_dumpf (chr->response,
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
                chr->http_status);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
error:
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Expected history of length %u, got %llu;"
              " HTTP status code: %u/%d, failed: %d\n",
              hs->total,
              (unsigned long long) hs->results_obtained,
              chr->http_status,
              (int) chr->ec,
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

    history_cmd = TALER_TESTING_interpreter_lookup_command (
      is,
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
  hs->hh = TALER_BANK_credit_history (
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
    TALER_BANK_credit_history_cancel (hs->hh);
  }
  GNUNET_free (hs->account_url);
  for (unsigned int off = 0; off<hs->total; off++)
    GNUNET_free (hs->h[off].url);
  GNUNET_free (hs->h);
  GNUNET_free (hs);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_credits (
  const char *label,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *start_row_reference,
  long long num_results)
{
  struct HistoryState *hs;

  hs = GNUNET_new (struct HistoryState);
  hs->account_url = GNUNET_strdup (auth->wire_gateway_url);
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


/* end of testing_api_cmd_credit_history.c */
