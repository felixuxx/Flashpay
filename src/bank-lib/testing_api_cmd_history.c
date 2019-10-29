/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

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
 * @file bank-lib/testing_api_cmd_history.c
 * @brief command to check the /history API from the bank.
 * @author Marcello Stanisci
 */

#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_exchange_service.h"
#include "taler_testing_lib.h"
#include "taler_testing_bank_lib.h"
#include "taler_fakebank_lib.h"
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"



/**
 * State for a "history" CMD.
 */
struct HistoryState
{
  /**
   * Base URL of the bank offering the "history" operation.
   */
  const char *bank_url;

  /**
   * Account number to ask the history for.
   */
  uint64_t account_no;

  /**
   * Which type of records we are interested: in-transfers
   * / out-transfers / rejected transfers.
   */
  enum TALER_BANK_Direction direction;

  /**
   * First row number we want in the result.
   */
  const char *start_row_reference;

  /**
   * How many rows we want in the result, _at most_.  In
   * the case of /history-range, we fake this value with
   * UINT64_MAX.
   */
  unsigned long long num_results;

  /**
   * Handle to a pending "history" operation.
   */
  struct TALER_BANK_HistoryHandle *hh;

  /**
   * Expected number of results (= rows).
   */
  uint64_t results_obtained;

  /**
   * Set to GNUNET_YES if the callback detects something
   * unexpected.
   */
  int failed;

  /**
   * If GNUNET_YES, this parameter will ask for results in
   * chronological order.
   */
  unsigned int ascending;

  /**********************************
   * Following defs are specific to *
   * the "/history-range" version.  *
   **********************************/

  /**
   * Last row number we want in the result.  Only used
   * as a trait source when using the /history-range API.
   */
  const char *end_row_reference;

  /**
   * Start date for /history-range.
   */
  struct GNUNET_TIME_Absolute start_date;

  /**
   * End date for /history-range.
   */
  struct GNUNET_TIME_Absolute end_date;
};

/**
 * Item in the transaction history, as reconstructed from the
 * command history.
 */
struct History
{

  /**
   * Wire details.
   */
  struct TALER_BANK_TransferDetails details;

  /**
   * Serial ID of the wire transfer.
   */
  uint64_t row_id;

  /**
   * Direction of the transfer.
   */
  enum TALER_BANK_Direction direction;

};


/**
 * Array mapping bank account numbers to login credentials.
 */
extern struct TALER_BANK_AuthenticationData AUTHS[];


/**
 * Offer internal data to other commands.
 *
 * @param cls closure.
 * @param ret[out] set to the wanted data.
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
 * Test if the CMD at offset @a off has been /rejected, and
 * is indeed a wire transfer CMD.
 *
 * @param is interpreter state (where we are right now)
 * @param off offset of the command to test for rejection.
 *
 * @return GNUNET_YES if the command at @a off was cancelled.
 */
static int
test_cancelled (struct TALER_TESTING_Interpreter *is,
                unsigned int off)
{
  const char *rejected_reference;
  const struct TALER_TESTING_Command *current_cmd;

  current_cmd = &is->commands[off];
  TALER_LOG_INFO ("Is `%s' rejected?\n",
                  current_cmd->label);
  for (int i = 0; i<is->ip; i++)
  {
    const struct TALER_TESTING_Command *c = &is->commands[i];


    /* XXX: Errors reported here are NOT fatal */

    /* Rejected wire transfers have a non-NULL reference to a
     * reject command to mark them as rejected. So errors
     * about "reject traits" not found are NOT fatal here */
    if (GNUNET_OK != TALER_TESTING_get_trait_rejected
          (c, 0, &rejected_reference))
      continue;

    TALER_LOG_INFO ("Command `%s' was rejected by `%s'.\n",
                    current_cmd->label,
                    c->label);

    if (0 == strcmp (rejected_reference,
                     current_cmd->label))
      return GNUNET_YES;
  }
  return GNUNET_NO;
}


/**
 * Free history @a h of length @a h_len.
 *
 * @param h history array to free.
 * @param h_len number of entries in @a h.
 */
static void
free_history (struct History *h,
              uint64_t h_len)
{
  for (uint64_t off = 0; off<h_len; off++)
  {
    GNUNET_free (h[off].details.wire_transfer_subject);
    GNUNET_free (h[off].details.account_url);
  }
  GNUNET_free_non_null (h);
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
                uint64_t h_len,
                unsigned int off)
{
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Transaction history missmatch at position %u/%llu\n",
              off,
              (unsigned long long) h_len);
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Expected history:\n");
  for (uint64_t i = 0; i<h_len; i++)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "H(%llu): %s%s (serial: %llu, subject: %s,"
                " counterpart: %s)\n",
                (unsigned long long) i,
                (TALER_BANK_DIRECTION_CREDIT == h[i].direction) ?
                "+" : "-",
                TALER_amount2s (&h[i].details.amount),
                (unsigned long long) h[i].row_id,
                h[i].details.wire_transfer_subject,
                h[i].details.account_url);
  }
}



/**
 * Tell if the current item is beyond the allowed limit.
 *
 * @param total current number of items in the built history list.
 *        Note, this is the list we build locally and compare with
 *        what the server returned.
 * @param hs the history CMD state.
 * @param pos current item to be evaluated or not (if the list
 *        has already enough elements).
 * @return GNUNET_OK / GNUNET_NO.
 */
static int
build_history_hit_limit (uint64_t total,
                         const struct HistoryState *hs,
                         const struct TALER_TESTING_Command *pos)
{
  /* "/history-range" case.  */
  if (GNUNET_TIME_UNIT_FOREVER_ABS.abs_value_us !=
      hs->start_date.abs_value_us)
  {
    const struct GNUNET_TIME_Absolute *timestamp;

    GNUNET_assert (GNUNET_OK ==
                   TALER_TESTING_get_trait_absolute_time (pos,
                                                          0,
                                                          &timestamp));
    GNUNET_assert (GNUNET_TIME_UNIT_FOREVER_ABS.abs_value_us !=
                   hs->end_date.abs_value_us);
    return timestamp->abs_value_us >= hs->end_date.abs_value_us;
  }
  return total >= hs->num_results;
}


/**
 * This function constructs the list of history elements that
 * interest the account number of the caller.  It has two main
 * loops: the first to figure out how many history elements have
 * to be allocated, and the second to actually populate every
 * element.
 *
 * This command has a limitation currently: it orders the history
 * list with descending elements if and only if the 'delta' was
 * given negative; and will order the list with ascending elements
 * if and only if the 'delta' was given positive.  Therefore,
 * for now it is NOT possible to test such a "/history" request:
 * "/history?auth=basic&direction=both&delta=10&ordering=descending"
 *
 * @param is interpreter state (supposedly having the
 *        current CMD pointing at a "history" CMD).
 * @param[out] rh history array to initialize.
 *
 * @return number of entries in @a rh.
 */
static uint64_t
build_history (struct TALER_TESTING_Interpreter *is,
               struct History **rh)
{
  struct HistoryState *hs = is->commands[is->ip].cls;
  uint64_t total;
  struct History *h;
  const struct TALER_TESTING_Command *add_incoming_cmd;
  int inc;
  unsigned int start;
  unsigned int end;

  /**
   * @var turns GNUNET_YES whenever either no 'start' value was
   *      given for the history query, or the given value is found
   *      in the list of all the CMDs.
   */
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
    GNUNET_assert (GNUNET_OK == TALER_TESTING_get_trait_uint64
                     (add_incoming_cmd, 0, &row_id_start));
  }

  GNUNET_assert ((0 != hs->num_results) || /* "/history" */
                 (GNUNET_TIME_UNIT_FOREVER_ABS.abs_value_us != /* "/history-range" */
                  hs->start_date.abs_value_us));

  if (0 == is->ip)
  {
    TALER_LOG_DEBUG ("Checking history at first CMD..\n");
    *rh = NULL;
    return 0;
  }

  /* AKA 'delta'.  */
  if (hs->num_results > 0)
  {
    inc = 1;  /* _inc_rement */
    start = 0;
    end = is->ip - 1;
  }
  else
  {
    inc = -1;
    start = is->ip - 1;
    end = 0;
  }

  total = 0;
  ok = GNUNET_NO;

  if (NULL == row_id_start)
    ok = GNUNET_YES;

  /* This loop counts how many commands _later than "start"_ belong
   * to the history of the caller.  This is stored in the @var total
   * variable.  */
  for (unsigned int off = start; off != end + inc; off += inc)
  {
    const struct TALER_TESTING_Command *pos = &is->commands[off];
    int cancelled;
    const uint64_t *row_id;

    /**
     * The following command allows us to skip over those CMDs
     * that do not offer a "row_id" trait.  Such skipped CMDs are
     * not interesting for building a history.
     */
    if (GNUNET_OK != TALER_TESTING_get_trait_uint64 (pos,
                                                     0,
                                                     &row_id))
      continue;

    /* Seek "/history" starting row.  */
    if (NULL != row_id_start)
    {
      if (*row_id_start == *row_id)
      {
        /* Doesn't count, start is excluded from output. */
        total = 0;
        ok = GNUNET_YES;
        continue;
      }
    }

    /* Seek "/history-range" starting row, _if_ that's the case */
    if ((GNUNET_TIME_UNIT_FOREVER_ABS.abs_value_us !=
         hs->start_date.abs_value_us) && (GNUNET_YES != ok))
    {
      const struct GNUNET_TIME_Absolute *timestamp;

      TALER_TESTING_get_trait_absolute_time (pos,
                                             0,
                                             &timestamp);
      TALER_LOG_DEBUG
        ("Seeking first row, start vs timestamp: %llu vs %llu\n",
        (long long unsigned int) hs->start_date.abs_value_us,
        (long long unsigned int) timestamp->abs_value_us);

      if (hs->start_date.abs_value_us <= timestamp->abs_value_us)
      {
        total = 0;
        ok = GNUNET_YES;
        continue;
      }
    }

    /* when 'start' was _not_ given, then ok == GNUNET_YES */
    if (GNUNET_NO == ok)
      continue; /* skip until we find the marker */

    TALER_LOG_DEBUG ("Found first row\n");

    if (build_history_hit_limit (total,
                                 hs,
                                 pos))
    {
      TALER_LOG_DEBUG ("Hit history limit\n");
      break;
    }

    cancelled = test_cancelled (is, off);

    if ( (GNUNET_YES == cancelled) &&
         (0 == (hs->direction & TALER_BANK_DIRECTION_CANCEL)) )
    {
      TALER_LOG_INFO ("Ignoring canceled wire"
                      " transfer from history\n");
      continue;
    }

    const uint64_t *credit_account_no;
    const uint64_t *debit_account_no;

    GNUNET_assert
      (GNUNET_OK == TALER_TESTING_GET_TRAIT_CREDIT_ACCOUNT
        (pos, &credit_account_no));

    GNUNET_assert
      (GNUNET_OK == TALER_TESTING_GET_TRAIT_DEBIT_ACCOUNT
        (pos, &debit_account_no));

    TALER_LOG_INFO ("Potential history element:"
                    " %llu->%llu; my account: %llu\n",
                    (unsigned long long) *debit_account_no,
                    (unsigned long long) *credit_account_no,
                    (unsigned long long) hs->account_no);

    if ( ( (0 != (hs->direction & TALER_BANK_DIRECTION_CREDIT)) &&
           (hs->account_no == *credit_account_no)) ||
         ( (0 != (hs->direction & TALER_BANK_DIRECTION_DEBIT)) &&
           (hs->account_no == *debit_account_no)) )
    {
      TALER_LOG_INFO ("+1 my history\n");
      total++; /* found matching record */
    }
  }

  GNUNET_assert (GNUNET_YES == ok);

  if (0 == total)
  {
    TALER_LOG_DEBUG ("Checking history at first CMD.. (2)\n");
    *rh = NULL;
    return 0;
  }


  GNUNET_assert (total < UINT_MAX);
  h = GNUNET_new_array ((unsigned int) total,
                        struct History);
  total = 0;
  ok = GNUNET_NO;
  if (NULL == row_id_start)
    ok = GNUNET_YES;

  /**
   * This loop _only_ populates the array of history elements.
   */
  for (unsigned int off = start; off != end + inc; off += inc)
  {
    const struct TALER_TESTING_Command *pos = &is->commands[off];
    int cancelled;
    const uint64_t *row_id;
    char *bank_hostname;
    const uint64_t *credit_account_no;
    const uint64_t *debit_account_no;

    if (GNUNET_OK != TALER_TESTING_GET_TRAIT_ROW_ID
          (pos, &row_id))
      continue;

    if (NULL != row_id_start)
    {

      if (*row_id_start == *row_id)
      {
        /**
         * Warning: this zeroing is superfluous, as
         * total doesn't get incremented if 'start'
         * was given and couldn't be found.
         */
        total = 0;
        ok = GNUNET_YES;
        continue;
      }
    }

    /* Seek "/history-range" starting row, _if_ that's the case */
    if ((GNUNET_TIME_UNIT_FOREVER_ABS.abs_value_us !=
         hs->start_date.abs_value_us) && (GNUNET_YES != ok))
    {
      const struct GNUNET_TIME_Absolute *timestamp;

      TALER_TESTING_get_trait_absolute_time (pos,
                                             0,
                                             &timestamp);
      TALER_LOG_DEBUG
        ("Seeking first row, start vs timestamp (2): %llu vs %llu\n",
        (long long unsigned int) hs->start_date.abs_value_us,
        (long long unsigned int) timestamp->abs_value_us);

      if (hs->start_date.abs_value_us <= timestamp->abs_value_us)
      {
        total = 0;
        ok = GNUNET_YES;
        continue;
      }
    }

    TALER_LOG_INFO ("Found first row (2)\n");

    if (GNUNET_NO == ok)
    {
      TALER_LOG_INFO ("Skip on `%s'\n",
                      pos->label);
      continue; /* skip until we find the marker */
    }

    if (build_history_hit_limit (total,
                                 hs,
                                 pos))
    {
      TALER_LOG_INFO ("Hit history limit (2)\n");
      break;
    }

    GNUNET_assert
      (GNUNET_OK == TALER_TESTING_GET_TRAIT_CREDIT_ACCOUNT
        (pos, &credit_account_no));

    GNUNET_assert
      (GNUNET_OK == TALER_TESTING_GET_TRAIT_DEBIT_ACCOUNT
        (pos, &debit_account_no));

    TALER_LOG_INFO ("Potential history bit:"
                    " %llu->%llu; my account: %llu\n",
                    (unsigned long long) *debit_account_no,
                    (unsigned long long) *credit_account_no,
                    (unsigned long long) hs->account_no);

    /**
     * Discard transactions where the audited account played
     * _both_ the credit and the debit roles, but _only if_
     * the audit goes on both directions..  This needs more
     * explaination!
     */
    if ( ( (0 != (hs->direction & TALER_BANK_DIRECTION_CREDIT)) &&
           (hs->account_no == *credit_account_no)) &&
         ( (0 != (hs->direction & TALER_BANK_DIRECTION_DEBIT)) &&
           (hs->account_no == *debit_account_no)) )
    {
      GNUNET_break (0);
      continue;
    }

    cancelled = test_cancelled (is, off);
    if ( (GNUNET_YES == cancelled) &&
         (0 == (hs->direction & TALER_BANK_DIRECTION_CANCEL)) )
    {
      TALER_LOG_WARNING ("`%s' was cancelled\n",
                         TALER_TESTING_interpreter_get_current_label
                           (is));
      continue;
    }

    bank_hostname = strchr (hs->bank_url, ':');
    GNUNET_assert (NULL != bank_hostname);
    bank_hostname += 3;

    /* Next two blocks only put the 'direction' and 'banking'
     * information.  */

    /* Asked for credit, and account got the credit.  */
    if ( (0 != (hs->direction & TALER_BANK_DIRECTION_CREDIT)) &&
         (hs->account_no == *credit_account_no))
    {
      h[total].direction = TALER_BANK_DIRECTION_CREDIT;
      if (GNUNET_YES == cancelled)
        h[total].direction |= TALER_BANK_DIRECTION_CANCEL;

      GNUNET_asprintf
        (&h[total].details.account_url,
        ('/' == bank_hostname[strlen (bank_hostname) - 1])
        ? "payto://x-taler-bank/%s%llu"
        : "payto://x-taler-bank/%s/%llu",
        bank_hostname,
        (unsigned long long) *debit_account_no);
    }

    /* Asked for debit, and account got the debit.  */
    if ( (0 != (hs->direction & TALER_BANK_DIRECTION_DEBIT)) &&
         (hs->account_no == *debit_account_no))
    {
      h[total].direction = TALER_BANK_DIRECTION_DEBIT;
      if (GNUNET_YES == cancelled)
        h[total].direction |= TALER_BANK_DIRECTION_CANCEL;

      GNUNET_asprintf
        (&h[total].details.account_url,
        ('/' == bank_hostname[strlen (bank_hostname) - 1])
        ? "payto://x-taler-bank/%s%llu"
        : "payto://x-taler-bank/%s/%llu",
        bank_hostname,
        (unsigned long long) *credit_account_no);
    }

    /* This block _completes_ the information of the current item,
     * with amount / subject / exchange URL.  */
    if ( ( (0 != (hs->direction & TALER_BANK_DIRECTION_CREDIT)) &&
           (hs->account_no == *credit_account_no)) ||
         ( (0 != (hs->direction & TALER_BANK_DIRECTION_DEBIT)) &&
           (hs->account_no == *debit_account_no)) )
    {
      const struct TALER_Amount *amount;
      const char *subject;
      const char *exchange_url;

      GNUNET_assert
        (GNUNET_OK == TALER_TESTING_get_trait_amount_obj
          (pos, 0, &amount));

      GNUNET_assert
        (GNUNET_OK == TALER_TESTING_get_trait_transfer_subject
          (pos, 0, &subject));

      GNUNET_assert (GNUNET_OK == TALER_TESTING_get_trait_url
                       (pos, 0, &exchange_url));

      h[total].details.amount = *amount;

      h[total].row_id = *row_id;
      GNUNET_asprintf (&h[total].details.wire_transfer_subject,
                       "%s %s",
                       subject,
                       exchange_url);
      TALER_LOG_INFO ("+1-bit of my history\n");
      total++;
    }
  }
  *rh = h;
  return total;
}


/**
 * Compute how many results we expect to be returned for
 * the current command at @a is.
 *
 * @param is the interpreter state to inspect.
 * @return number of results expected.
 */
static uint64_t
compute_result_count (struct TALER_TESTING_Interpreter *is)
{
  uint64_t total;
  struct History *h;

  total = build_history (is, &h);
  free_history (h, total);
  return total;
}


/**
 * Check that the "/history" response matches the
 * CMD whose offset in the list of CMDs is @a off.
 *
 * @param is the interpreter state.
 * @param off the offset (of the CMD list) where the command
 *        to check is.
 * @param dir the expected direction of the transaction.
 * @param details the expected transaction details.
 *
 * @return #GNUNET_OK if the transaction is what we expect.
 */
static int
check_result (struct TALER_TESTING_Interpreter *is,
              unsigned int off,
              enum TALER_BANK_Direction dir,
              const struct TALER_BANK_TransferDetails *details)
{
  uint64_t total;
  struct History *h;

  total = build_history (is, &h);
  if (off >= total)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Test says history has at most %u"
                " results, but got result #%u to check\n",
                (unsigned int) total,
                off);
    print_expected (h, total, off);
    return GNUNET_SYSERR;
  }
  if (h[off].direction != dir)
  {
    GNUNET_break (0);
    print_expected (h, total, off);
    free_history (h,
                  total);
    return GNUNET_SYSERR;
  }

  if ( (0 != strcmp (h[off].details.wire_transfer_subject,
                     details->wire_transfer_subject)) ||
       (0 != TALER_amount_cmp (&h[off].details.amount,
                               &details->amount)) ||
       (0 != strcasecmp (h[off].details.account_url,
                         details->account_url)) )
  {
    GNUNET_break (0);
    print_expected (h, total, off);
    free_history (h,
                  total);
    return GNUNET_SYSERR;
  }
  free_history (h,
                total);
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
 * @param dir direction of the transfer.
 * @param row_id monotonically increasing counter corresponding to
 *        the transaction.
 * @param details details about the wire transfer.
 * @param json detailed response from the HTTPD, or NULL if
 *        reply was not in JSON.
 */
static void
history_cb (void *cls,
            unsigned int http_status,
            enum TALER_ErrorCode ec,
            enum TALER_BANK_Direction dir,
            uint64_t row_id,
            const struct TALER_BANK_TransferDetails *details,
            const json_t *json)
{
  struct TALER_TESTING_Interpreter *is = cls;
  struct HistoryState *hs = is->commands[is->ip].cls;

  (void) row_id;
  /*NOTE: "204 No Content" is used to signal the end of results.*/
  if (MHD_HTTP_NO_CONTENT == http_status)
  {
    hs->hh = NULL;
    if ( (hs->results_obtained != compute_result_count (is)) ||
         (GNUNET_YES == hs->failed) )
    {
      uint64_t total;
      struct History *h;

      GNUNET_break (0);
      total = build_history (is, &h);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Expected history of length %llu, got %llu;"
                  " HTTP status code: %u/%d, failed: %d\n",
                  (unsigned long long) total,
                  (unsigned long long) hs->results_obtained,
                  http_status,
                  (int) ec,
                  hs->failed);
      print_expected (h,
                      total,
                      UINT_MAX);
      free_history (h,
                    total);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    TALER_TESTING_interpreter_next (is);
    return;
  }

  if (MHD_HTTP_OK != http_status)
  {
    hs->hh = NULL;
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unwanted response code from /history[-range]: %u\n",
                http_status);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  /* check current element */
  if (GNUNET_OK != check_result (is,
                                 hs->results_obtained,
                                 dir,
                                 details))
  {
    GNUNET_break (0);

    {
      char *acc;

      acc = json_dumps (json,
                        JSON_COMPACT);
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Result %u was `%s'\n",
                  (unsigned int) hs->results_obtained++,
                  acc);
      if (NULL != acc)
        free (acc);
    }

    hs->failed = GNUNET_YES;
    return;
  }
  hs->results_obtained++;
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
  uint64_t row_id = UINT64_MAX;
  const uint64_t *row_id_ptr = &row_id;
  struct TALER_BANK_AuthenticationData *auth;

  (void) cmd;
  /* Get row_id from trait. */
  if (NULL != hs->start_row_reference)
  {
    const struct TALER_TESTING_Command *history_cmd;

    history_cmd = TALER_TESTING_interpreter_lookup_command
                    (is, hs->start_row_reference);

    if (NULL == history_cmd)
      TALER_TESTING_FAIL (is);

    if (GNUNET_OK != TALER_TESTING_get_trait_uint64 (history_cmd,
                                                     0,
                                                     &row_id_ptr))
      TALER_TESTING_FAIL (is);
    row_id = *row_id_ptr;

    TALER_LOG_DEBUG ("row id (from trait) is %llu\n",
                     (unsigned long long) row_id);
  }

  auth = &AUTHS[hs->account_no - 1];
  hs->hh = TALER_BANK_history (is->ctx,
                               hs->bank_url,
                               auth,
                               hs->account_no,
                               hs->direction,
                               hs->ascending,
                               row_id,
                               hs->num_results,
                               &history_cb,
                               is);
  GNUNET_assert (NULL != hs->hh);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
history_range_run (void *cls,
                   const struct TALER_TESTING_Command *cmd,
                   struct TALER_TESTING_Interpreter *is)
{
  struct HistoryState *hs = cls;
  const struct GNUNET_TIME_Absolute *start_date;
  const struct GNUNET_TIME_Absolute *end_date;
  struct TALER_BANK_AuthenticationData *auth;

  (void) cmd;
  if (NULL != hs->start_row_reference)
  {
    const struct TALER_TESTING_Command *history_cmd;

    history_cmd = TALER_TESTING_interpreter_lookup_command
                    (is, hs->start_row_reference);

    if (NULL == history_cmd)
      TALER_TESTING_FAIL (is);

    if (GNUNET_OK != TALER_TESTING_get_trait_absolute_time
          (history_cmd, 0, &start_date))
      TALER_TESTING_FAIL (is);
    hs->start_date = *start_date;
  }
  else
  {
    /* no trait wanted.  */
    GNUNET_assert (GNUNET_TIME_UNIT_FOREVER_ABS.abs_value_us !=
                   hs->start_date.abs_value_us);
    start_date = &hs->start_date;
  }

  if (NULL != hs->end_row_reference)
  {
    const struct TALER_TESTING_Command *history_cmd;

    history_cmd = TALER_TESTING_interpreter_lookup_command
                    (is, hs->end_row_reference);

    if (NULL == history_cmd)
      TALER_TESTING_FAIL (is);

    if (GNUNET_OK != TALER_TESTING_get_trait_absolute_time
          (history_cmd, 0, &end_date))
      TALER_TESTING_FAIL (is);
    hs->end_date = *end_date;
  }
  else
  {
    /* no trait wanted.  */
    GNUNET_assert (GNUNET_TIME_UNIT_FOREVER_ABS.abs_value_us !=
                   hs->end_date.abs_value_us);
    end_date = &hs->end_date;
  }

  auth = &AUTHS[hs->account_no - 1];
  hs->hh = TALER_BANK_history_range (is->ctx,
                                     hs->bank_url,
                                     auth,
                                     hs->account_no,
                                     hs->direction,
                                     hs->ascending,
                                     *start_date,
                                     *end_date,
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
    TALER_LOG_WARNING ("/history did not complete\n");
    TALER_BANK_history_cancel (hs->hh);
  }
  GNUNET_free (hs);
}


/**
 * Make a "history" CMD.
 *
 * @param label command label.
 * @param bank_url base URL of the bank offering the "history"
 *        operation.
 * @param account_no bank account number to ask the history for.
 * @param direction which direction this operation is interested.
 * @param ascending if #GNUNET_YES, the bank will return the rows
 *        in ascending (= chronological) order.
 * @param start_row_reference reference to a command that can
 *        offer a row identifier, to be used as the starting row
 *        to accept in the result.
 * @param num_results how many rows we want in the result.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_history (const char *label,
                                const char *bank_url,
                                uint64_t account_no,
                                enum TALER_BANK_Direction direction,
                                unsigned int ascending,
                                const char *start_row_reference,
                                unsigned long long num_results)
{
  struct HistoryState *hs;

  hs = GNUNET_new (struct HistoryState);
  hs->bank_url = bank_url;
  hs->account_no = account_no;
  hs->direction = direction;
  hs->start_row_reference = start_row_reference;
  hs->num_results = num_results;
  hs->ascending = ascending;
  hs->start_date = GNUNET_TIME_UNIT_FOREVER_ABS;
  hs->end_date = GNUNET_TIME_UNIT_FOREVER_ABS;

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


/**
 * Make a "history-range" CMD, picking dates from traits.
 *
 * @param label command label.
 * @param bank_url base URL of the bank offering the "history"
 *        operation.
 * @param account_no bank account number to ask the history for.
 * @param direction which direction this operation is interested.
 * @param ascending if GNUNET_YES, the bank will return the rows
 *        in ascending (= chronological) order.
 * @param start_row_reference reference to a command that can
 *        offer a absolute time to use as the 'start' argument
 *        for "/history-range".
 * @param end_row_reference reference to a command that can
 *        offer a absolute time to use as the 'end' argument
 *        for "/history-range".
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_history_range
  (const char *label,
  const char *bank_url,
  uint64_t account_no,
  enum TALER_BANK_Direction direction,
  unsigned int ascending,
  const char *start_row_reference,
  const char *end_row_reference)
{
  struct HistoryState *hs;

  hs = GNUNET_new (struct HistoryState);
  hs->bank_url = bank_url;
  hs->account_no = account_no;
  hs->direction = direction;
  hs->start_row_reference = start_row_reference;
  hs->end_row_reference = end_row_reference;
  hs->ascending = ascending;
  hs->start_date = GNUNET_TIME_UNIT_FOREVER_ABS;
  hs->end_date = GNUNET_TIME_UNIT_FOREVER_ABS;

  {
    struct TALER_TESTING_Command cmd = {
      .label = label,
      .cls = hs,
      .run = &history_range_run,
      .cleanup = &history_cleanup,
      .traits = &history_traits
    };

    return cmd;
  }
}


/**
 * Make a "history-range" CMD, picking dates from the arguments.
 *
 * @param label command label.
 * @param bank_url base URL of the bank offering the "history"
 *        operation.
 * @param account_no bank account number to ask the history for.
 * @param direction which direction this operation is interested.
 * @param ascending if GNUNET_YES, the bank will return the rows
 *        in ascending (= chronological) order.
 * @param start_date value for the 'start' argument
 *        of "/history-range".
 * @param end_date value for the 'end' argument
 *        of "/history-range".
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_bank_history_range_with_dates
  (const char *label,
  const char *bank_url,
  uint64_t account_no,
  enum TALER_BANK_Direction direction,
  unsigned int ascending,
  struct GNUNET_TIME_Absolute start_date,
  struct GNUNET_TIME_Absolute end_date)
{
  struct HistoryState *hs;

  hs = GNUNET_new (struct HistoryState);
  hs->bank_url = bank_url;
  hs->account_no = account_no;
  hs->direction = direction;
  hs->ascending = ascending;
  hs->start_row_reference = NULL;
  hs->start_date = start_date;
  hs->end_date = end_date;

  {
    struct TALER_TESTING_Command cmd = {
      .label = label,
      .cls = hs,
      .run = &history_range_run,
      .cleanup = &history_cleanup,
      .traits = &history_traits
    };

    return cmd;
  }
}

/* end of testing_api_cmd_history.c */
