/*
  This file is part of TALER
  Copyright (C) 2018-2021 Taler Systems SA

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
 * @file testing/testing_api_cmd_bank_transfer.c
 * @brief implementation of a bank /transfer command
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "backoff.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * How often do we retry before giving up?
 */
#define NUM_RETRIES 5


/**
 * State for a "transfer" CMD.
 */
struct TransferState
{

  /**
   * Wire transfer amount.
   */
  struct TALER_Amount amount;

  /**
   * Base URL of the debit account.
   */
  const char *account_debit_url;

  /**
   * Money receiver payto URL.
   */
  struct TALER_FullPayto payto_debit_account;

  /**
   * Money receiver account URL.
   */
  struct TALER_FullPayto payto_credit_account;

  /**
   * Username to use for authentication.
   */
  struct TALER_BANK_AuthenticationData auth;

  /**
   * Base URL of the exchange.
   */
  const char *exchange_base_url;

  /**
   * Wire transfer identifier to use.
   */
  struct TALER_WireTransferIdentifierRawP wtid;

  /**
   * Handle to the pending request at the fakebank.
   */
  struct TALER_BANK_TransferHandle *weh;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Set to the wire transfer's unique ID.
   */
  uint64_t serial_id;

  /**
   * Timestamp of the transaction (as returned from the bank).
   */
  struct GNUNET_TIME_Timestamp timestamp;

  /**
   * Configuration filename.  Used to get the tip reserve key
   * filename (used to obtain a public key to write in the
   * transfer subject).
   */
  const char *config_filename;

  /**
   * Task scheduled to try later.
   */
  struct GNUNET_SCHEDULER_Task *retry_task;

  /**
   * How long do we wait until we retry?
   */
  struct GNUNET_TIME_Relative backoff;

  /**
   * Was this command modified via
   * #TALER_TESTING_cmd_admin_add_incoming_with_retry to
   * enable retries? If so, how often should we still retry?
   */
  unsigned int do_retry;
};


/**
 * Run the "transfer" CMD.
 *
 * @param cls closure.
 * @param cmd CMD being run.
 * @param is interpreter state.
 */
static void
transfer_run (void *cls,
              const struct TALER_TESTING_Command *cmd,
              struct TALER_TESTING_Interpreter *is);


/**
 * Task scheduled to re-try #transfer_run.
 *
 * @param cls a `struct TransferState`
 */
static void
do_retry (void *cls)
{
  struct TransferState *fts = cls;

  fts->retry_task = NULL;
  TALER_TESTING_touch_cmd (fts->is);
  transfer_run (fts,
                NULL,
                fts->is);
}


/**
 * This callback will process the fakebank response to the wire
 * transfer.  It just checks whether the HTTP response code is
 * acceptable.
 *
 * @param cls closure with the interpreter state
 * @param tr response details
 */
static void
confirmation_cb (void *cls,
                 const struct TALER_BANK_TransferResponse *tr)
{
  struct TransferState *fts = cls;
  struct TALER_TESTING_Interpreter *is = fts->is;

  fts->weh = NULL;
  if (MHD_HTTP_OK != tr->http_status)
  {
    if (0 != fts->do_retry)
    {
      fts->do_retry--;
      if ( (0 == tr->http_status) ||
           (TALER_EC_GENERIC_DB_SOFT_FAILURE == tr->ec) ||
           (MHD_HTTP_INTERNAL_SERVER_ERROR == tr->http_status) )
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "Retrying transfer failed with %u/%d\n",
                    tr->http_status,
                    (int) tr->ec);
        /* on DB conflicts, do not use backoff */
        if (TALER_EC_GENERIC_DB_SOFT_FAILURE == tr->ec)
          fts->backoff = GNUNET_TIME_UNIT_ZERO;
        else
          fts->backoff = EXCHANGE_LIB_BACKOFF (fts->backoff);
        TALER_TESTING_inc_tries (fts->is);
        fts->retry_task
          = GNUNET_SCHEDULER_add_delayed (fts->backoff,
                                          &do_retry,
                                          fts);
        return;
      }
    }
    TALER_TESTING_unexpected_status (is,
                                     tr->http_status,
                                     MHD_HTTP_OK);
    return;
  }

  fts->serial_id = tr->details.ok.row_id;
  fts->timestamp = tr->details.ok.timestamp;
  TALER_TESTING_interpreter_next (is);
}


/**
 * Run the "transfer" CMD.
 *
 * @param cls closure.
 * @param cmd CMD being run.
 * @param is interpreter state.
 */
static void
transfer_run (void *cls,
              const struct TALER_TESTING_Command *cmd,
              struct TALER_TESTING_Interpreter *is)
{
  struct TransferState *fts = cls;
  void *buf;
  size_t buf_size;

  (void) cmd;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Transfer of %s from %s to %s\n",
              TALER_amount2s (&fts->amount),
              fts->account_debit_url,
              fts->payto_credit_account.full_payto);
  TALER_BANK_prepare_transfer (fts->payto_credit_account,
                               &fts->amount,
                               fts->exchange_base_url,
                               &fts->wtid,
                               &buf,
                               &buf_size);
  fts->is = is;
  fts->weh
    = TALER_BANK_transfer (
        TALER_TESTING_interpreter_get_context (is),
        &fts->auth,
        buf,
        buf_size,
        &confirmation_cb,
        fts);
  GNUNET_free (buf);
  if (NULL == fts->weh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "fakebank transfer" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure
 * @param cmd current CMD being cleaned up.
 */
static void
transfer_cleanup (void *cls,
                  const struct TALER_TESTING_Command *cmd)
{
  struct TransferState *fts = cls;

  if (NULL != fts->weh)
  {
    TALER_TESTING_command_incomplete (fts->is,
                                      cmd->label);
    TALER_BANK_transfer_cancel (fts->weh);
    fts->weh = NULL;
  }
  if (NULL != fts->retry_task)
  {
    GNUNET_SCHEDULER_cancel (fts->retry_task);
    fts->retry_task = NULL;
  }
  GNUNET_free (fts);
}


/**
 * Offer internal data from a "fakebank transfer" CMD to other
 * commands.
 *
 * @param cls closure.
 * @param[out] ret result
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
transfer_traits (void *cls,
                 const void **ret,
                 const char *trait,
                 unsigned int index)
{
  struct TransferState *fts = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_exchange_url (
      fts->exchange_base_url),
    TALER_TESTING_make_trait_bank_row (&fts->serial_id),
    TALER_TESTING_make_trait_credit_payto_uri (
      &fts->payto_credit_account),
    TALER_TESTING_make_trait_debit_payto_uri (
      &fts->payto_debit_account),
    TALER_TESTING_make_trait_amount (&fts->amount),
    TALER_TESTING_make_trait_timestamp (0, &fts->timestamp),
    TALER_TESTING_make_trait_wtid (&fts->wtid),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_transfer (const char *label,
                            const char *amount,
                            const struct TALER_BANK_AuthenticationData *auth,
                            struct TALER_FullPayto payto_debit_account,
                            struct TALER_FullPayto payto_credit_account,
                            const struct TALER_WireTransferIdentifierRawP *wtid,
                            const char *exchange_base_url)
{
  struct TransferState *fts;

  fts = GNUNET_new (struct TransferState);
  fts->account_debit_url = auth->wire_gateway_url;
  fts->exchange_base_url = exchange_base_url;
  fts->payto_debit_account = payto_debit_account;
  fts->payto_credit_account = payto_credit_account;
  fts->auth = *auth;
  fts->wtid = *wtid;
  if (GNUNET_OK !=
      TALER_string_to_amount (amount,
                              &fts->amount))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse amount `%s' at %s\n",
                amount,
                label);
    GNUNET_assert (0);
  }

  {
    struct TALER_TESTING_Command cmd = {
      .cls = fts,
      .label = label,
      .run = &transfer_run,
      .cleanup = &transfer_cleanup,
      .traits = &transfer_traits
    };

    return cmd;
  }
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_transfer_retry (struct TALER_TESTING_Command cmd)
{
  struct TransferState *fts;

  GNUNET_assert (&transfer_run == cmd.run);
  fts = cmd.cls;
  fts->do_retry = NUM_RETRIES;
  return cmd;
}


/* end of testing_api_cmd_bank_transfer.c */
