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
 * @file testing/testing_api_cmd_transfer_get.c
 * @brief Implement the testing CMDs for the /transfer GET operation.
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"

/**
 * State for a "track transfer" CMD.
 */
struct TrackTransferState
{

  /**
   * Expected amount for the WTID being tracked.
   */
  const char *expected_total_amount;

  /**
   * Expected fee for this WTID.
   */
  const char *expected_wire_fee;

  /**
   * Reference to any operation that can provide a WTID.
   * Will be the WTID to track.
   */
  const char *wtid_reference;

  /**
   * Reference to any operation that can provide wire details.
   * Those wire details will then be matched against the credit
   * bank account of the tracked WTID.  This way we can test that
   * a wire transfer paid back one particular bank account.
   */
  const char *wire_details_reference;

  /**
   * Reference to any operation that can provide an amount.
   * This way we can check that the transferred amount matches
   * our expectations.
   */
  const char *total_amount_reference;

  /**
   * Handle to a pending "track transfer" operation.
   */
  struct TALER_EXCHANGE_TransfersGetHandle *tth;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Index to the WTID to pick, in case @a wtid_reference has
   * many on offer.
   */
  unsigned int index;
};


/**
 * Cleanup the state for a "track transfer" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure.
 * @param cmd the command which is being cleaned up.
 */
static void
track_transfer_cleanup (void *cls,
                        const struct TALER_TESTING_Command *cmd)
{

  struct TrackTransferState *tts = cls;

  if (NULL != tts->tth)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                tts->is->ip,
                cmd->label);
    TALER_EXCHANGE_transfers_get_cancel (tts->tth);
    tts->tth = NULL;
  }
  GNUNET_free (tts);
}


/**
 * Check whether the HTTP response code from a "track transfer"
 * operation is acceptable, and all other values like total amount,
 * wire fees and hashed wire details as well.
 *
 * @param cls closure.
 * @param hr HTTP response details
 * @param ta transfer data returned by the exchange
 */
static void
track_transfer_cb (void *cls,
                   const struct TALER_EXCHANGE_HttpResponse *hr,
                   const struct TALER_EXCHANGE_TransferData *ta)
{
  struct TrackTransferState *tts = cls;
  struct TALER_TESTING_Interpreter *is = tts->is;
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];
  struct TALER_Amount expected_amount;

  tts->tth = NULL;
  if (tts->expected_response_code != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d to command %s in %s:%u\n",
                hr->http_status,
                (int) hr->ec,
                cmd->label,
                __FILE__,
                __LINE__);
    json_dumpf (hr->reply,
                stderr,
                0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  switch (hr->http_status)
  {
  case MHD_HTTP_OK:
    if (NULL == tts->expected_total_amount)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (NULL == tts->expected_wire_fee)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }

    if (GNUNET_OK !=
        TALER_string_to_amount (tts->expected_total_amount,
                                &expected_amount))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (0 != TALER_amount_cmp (&ta->total_amount,
                               &expected_amount))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Total amount mismatch to command %s - "
                  "%s vs %s\n",
                  cmd->label,
                  TALER_amount_to_string (&ta->total_amount),
                  TALER_amount_to_string (&expected_amount));
      json_dumpf (hr->reply,
                  stderr,
                  0);
      fprintf (stderr, "\n");
      TALER_TESTING_interpreter_fail (is);
      return;
    }

    if (GNUNET_OK !=
        TALER_string_to_amount (tts->expected_wire_fee,
                                &expected_amount))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }

    if (0 != TALER_amount_cmp (&ta->wire_fee,
                               &expected_amount))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Wire fee mismatch to command %s\n",
                  cmd->label);
      json_dumpf (hr->reply,
                  stderr,
                  0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }

    /**
     * Optionally checking: (1) wire-details for this transfer
     * match the ones from a referenced "deposit" operation -
     * or any operation that could provide wire-details.  (2)
     * Total amount for this transfer matches the one from any
     * referenced command that could provide one.
     */if (NULL != tts->wire_details_reference)
    {
      const struct TALER_TESTING_Command *wire_details_cmd;
      const json_t *wire_details;
      struct GNUNET_HashCode h_wire_details;

      wire_details_cmd
        = TALER_TESTING_interpreter_lookup_command (is,
                                                    tts->wire_details_reference);
      if (NULL == wire_details_cmd)
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      if (GNUNET_OK !=
          TALER_TESTING_get_trait_wire_details (wire_details_cmd,
                                                0,
                                                &wire_details))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      GNUNET_assert (GNUNET_OK ==
                     TALER_JSON_merchant_wire_signature_hash (wire_details,
                                                              &h_wire_details));
      if (0 != GNUNET_memcmp (&h_wire_details,
                              &ta->h_wire))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Wire hash missmath to command %s\n",
                    cmd->label);
        json_dumpf (hr->reply,
                    stderr,
                    0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
    }
    if (NULL != tts->total_amount_reference)
    {
      const struct TALER_TESTING_Command *total_amount_cmd;
      const struct TALER_Amount *total_amount_from_reference;

      total_amount_cmd
        = TALER_TESTING_interpreter_lookup_command (is,
                                                    tts->total_amount_reference);
      if (NULL == total_amount_cmd)
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      if (GNUNET_OK !=
          TALER_TESTING_get_trait_amount_obj (total_amount_cmd,
                                              0,
                                              &total_amount_from_reference))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      if (0 != TALER_amount_cmp (&ta->total_amount,
                                 total_amount_from_reference))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Amount missmath to command %s\n",
                    cmd->label);
        json_dumpf (hr->reply,
                    stderr,
                    0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
    }
  }
  TALER_TESTING_interpreter_next (is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command under execution.
 * @param is the interpreter state.
 */
static void
track_transfer_run (void *cls,
                    const struct TALER_TESTING_Command *cmd,
                    struct TALER_TESTING_Interpreter *is)
{
  /* looking for a wtid to track .. */
  struct TrackTransferState *tts = cls;
  struct TALER_WireTransferIdentifierRawP wtid;
  const struct TALER_WireTransferIdentifierRawP *wtid_ptr;

  /* If no reference is given, we'll use a all-zeros
   * WTID */
  memset (&wtid, 0, sizeof (wtid));
  wtid_ptr = &wtid;

  tts->is = is;
  if (NULL != tts->wtid_reference)
  {
    const struct TALER_TESTING_Command *wtid_cmd;

    wtid_cmd = TALER_TESTING_interpreter_lookup_command
                 (tts->is, tts->wtid_reference);

    if (NULL == wtid_cmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (tts->is);
      return;
    }

    if (GNUNET_OK != TALER_TESTING_get_trait_wtid
          (wtid_cmd, tts->index, &wtid_ptr))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (tts->is);
      return;
    }
    GNUNET_assert (NULL != wtid_ptr);
  }
  tts->tth = TALER_EXCHANGE_transfers_get (is->exchange,
                                           wtid_ptr,
                                           &track_transfer_cb,
                                           tts);
  GNUNET_assert (NULL != tts->tth);
}


/**
 * Make a "track transfer" CMD where no "expected"-arguments,
 * except the HTTP response code, are given.  The best use case
 * is when what matters to check is the HTTP response code, e.g.
 * when a bogus WTID was passed.
 *
 * @param label the command label
 * @param wtid_reference reference to any command which can provide
 *        a wtid.  If NULL is given, then a all zeroed WTID is
 *        used that will at 99.9999% probability NOT match any
 *        existing WTID known to the exchange.
 * @param index index number of the WTID to track, in case there
 *        are multiple on offer.
 * @param expected_response_code expected HTTP response code.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_track_transfer_empty (const char *label,
                                        const char *wtid_reference,
                                        unsigned int index,
                                        unsigned int expected_response_code)
{
  struct TrackTransferState *tts;

  tts = GNUNET_new (struct TrackTransferState);
  tts->wtid_reference = wtid_reference;
  tts->index = index;
  tts->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = tts,
      .label = label,
      .run = &track_transfer_run,
      .cleanup = &track_transfer_cleanup
    };

    return cmd;
  }
}


/**
 * Make a "track transfer" command, specifying which amount and
 * wire fee are expected.
 *
 * @param label the command label.
 * @param wtid_reference reference to any command which can provide
 *        a wtid.  Will be the one tracked.
 * @param index in case there are multiple WTID offered, this
 *        parameter selects a particular one.
 * @param expected_response_code expected HTTP response code.
 * @param expected_total_amount how much money we expect being moved
 *        with this wire-transfer.
 * @param expected_wire_fee expected wire fee.
 * @return the command
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_track_transfer (const char *label,
                                  const char *wtid_reference,
                                  unsigned int index,
                                  unsigned int expected_response_code,
                                  const char *expected_total_amount,
                                  const char *expected_wire_fee)
{
  struct TrackTransferState *tts;

  tts = GNUNET_new (struct TrackTransferState);
  tts->wtid_reference = wtid_reference;
  tts->index = index;
  tts->expected_response_code = expected_response_code;
  tts->expected_total_amount = expected_total_amount;
  tts->expected_wire_fee = expected_wire_fee;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = tts,
      .label = label,
      .run = &track_transfer_run,
      .cleanup = &track_transfer_cleanup
    };

    return cmd;
  }
}


/* end of testing_api_cmd_gransfer_get.c */
