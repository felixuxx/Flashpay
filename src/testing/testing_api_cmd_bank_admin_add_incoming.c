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
 * @file testing/testing_api_cmd_bank_admin_add_incoming.c
 * @brief implementation of a bank /admin/add-incoming command
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "backoff.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_bank_service.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"

/**
 * How long do we wait AT MOST when retrying?
 */
#define MAX_BACKOFF GNUNET_TIME_relative_multiply ( \
          GNUNET_TIME_UNIT_MILLISECONDS, 100)


/**
 * How often do we retry before giving up?
 */
#define NUM_RETRIES 5


/**
 * State for a "bank transfer" CMD.
 */
struct AdminAddIncomingState
{

  /**
   * Label of any command that can trait-offer a reserve priv.
   */
  const char *reserve_reference;

  /**
   * Wire transfer amount.
   */
  struct TALER_Amount amount;

  /**
   * Base URL of the credited account.
   */
  const char *exchange_credit_url;

  /**
   * Money sender payto URL.
   */
  struct TALER_FullPayto payto_debit_account;

  /**
   * Username to use for authentication.
   */
  struct TALER_BANK_AuthenticationData auth;

  /**
   * Set (by the interpreter) to the reserve's private key
   * we used to make a wire transfer subject line with.
   */
  union TALER_AccountPrivateKeyP account_priv;

  /**
   * Whether we know the private key or not.
   */
  bool reserve_priv_known;

  /**
   * Account public key matching @e account_priv.
   */
  union TALER_AccountPublicKeyP account_pub;

  /**
   * Handle to the pending request at the bank.
   */
  struct TALER_BANK_AdminAddIncomingHandle *aih;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Reserve history entry that corresponds to this operation.
   * Will be of type #TALER_EXCHANGE_RTT_CREDIT.  Note that
   * the "sender_url" field is set to a 'const char *' and
   * MUST NOT be free()'ed.
   */
  struct TALER_EXCHANGE_ReserveHistoryEntry reserve_history;

  /**
   * Set to the wire transfer's unique ID.
   */
  uint64_t serial_id;

  /**
   * Timestamp of the transaction (as returned from the bank).
   */
  struct GNUNET_TIME_Timestamp timestamp;

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

  /**
   * Expected HTTP status code.
   */
  unsigned int expected_http_status;
};


/**
 * Run the "bank transfer" CMD.
 *
 * @param cls closure.
 * @param cmd CMD being run.
 * @param is interpreter state.
 */
static void
admin_add_incoming_run (
  void *cls,
  const struct TALER_TESTING_Command *cmd,
  struct TALER_TESTING_Interpreter *is);


/**
 * Task scheduled to re-try #admin_add_incoming_run.
 *
 * @param cls a `struct AdminAddIncomingState`
 */
static void
do_retry (void *cls)
{
  struct AdminAddIncomingState *fts = cls;

  fts->retry_task = NULL;
  TALER_TESTING_touch_cmd (fts->is);
  admin_add_incoming_run (fts,
                          NULL,
                          fts->is);
}


/**
 * This callback will process the bank response to the wire
 * transfer.  It just checks whether the HTTP response code is
 * acceptable.
 *
 * @param cls closure with the interpreter state
 * @param air response details
 */
static void
confirmation_cb (void *cls,
                 const struct TALER_BANK_AdminAddIncomingResponse *air)
{
  struct AdminAddIncomingState *fts = cls;
  struct TALER_TESTING_Interpreter *is = fts->is;

  fts->aih = NULL;
  /**
   * Test case not caring about the HTTP status code.
   * That helps when fakebank and Libeufin diverge in
   * the response status code.  An example is the
   * /admin/add-incoming: libeufin return ALWAYS '200 OK'
   * (see note below) whereas the fakebank responds with
   * '409 Conflict' upon a duplicate reserve public key.
   *
   * Note: this decision aims at avoiding to put Taler
   * logic into the Sandbox; that's because banks DO allow
   * their customers to wire the same subject multiple
   * times.  Hence, instead of triggering any error, libeufin
   * bounces the payment back in the same way it does for
   * malformed reserve public keys.
   */
  if (-1 == (int) fts->expected_http_status)
  {
    TALER_TESTING_interpreter_next (is);
    return;
  }
  if (air->http_status != fts->expected_http_status)
  {
    TALER_TESTING_unexpected_status (is,
                                     air->http_status,
                                     fts->expected_http_status);
    return;
  }
  switch (air->http_status)
  {
  case MHD_HTTP_OK:
    fts->reserve_history.details.in_details.timestamp
      = air->details.ok.timestamp;
    fts->reserve_history.details.in_details.wire_reference
      = air->details.ok.serial_id;
    fts->serial_id
      = air->details.ok.serial_id;
    fts->timestamp
      = air->details.ok.timestamp;
    TALER_TESTING_interpreter_next (is);
    return;
  case MHD_HTTP_UNAUTHORIZED:
    switch (fts->auth.method)
    {
    case TALER_BANK_AUTH_NONE:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Authentication required, but none configure.\n");
      break;
    case TALER_BANK_AUTH_BASIC:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Basic authentication (%s) failed.\n",
                  fts->auth.details.basic.username);
      break;
    case TALER_BANK_AUTH_BEARER:
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Bearer authentication (%s) failed.\n",
                  fts->auth.details.bearer.token);
      break;
    }
    break;
  case MHD_HTTP_CONFLICT:
    TALER_TESTING_interpreter_next (is);
    return;
  default:
    if (0 != fts->do_retry)
    {
      fts->do_retry--;
      if ( (0 == air->http_status) ||
           (TALER_EC_GENERIC_DB_SOFT_FAILURE == air->ec) ||
           (MHD_HTTP_INTERNAL_SERVER_ERROR == air->http_status) )
      {
        GNUNET_log (
          GNUNET_ERROR_TYPE_INFO,
          "Retrying bank transfer failed with %u/%d\n",
          air->http_status,
          (int) air->ec);
        /* on DB conflicts, do not use backoff */
        if (TALER_EC_GENERIC_DB_SOFT_FAILURE == air->ec)
          fts->backoff = GNUNET_TIME_UNIT_ZERO;
        else
          fts->backoff = GNUNET_TIME_randomized_backoff (fts->backoff,
                                                         MAX_BACKOFF);
        TALER_TESTING_inc_tries (fts->is);
        fts->retry_task = GNUNET_SCHEDULER_add_delayed (
          fts->backoff,
          &do_retry,
          fts);
        return;
      }
    }
    break;
  }
  GNUNET_break (0);
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Bank returned HTTP status %u/%d\n",
              air->http_status,
              (int) air->ec);
  TALER_TESTING_interpreter_fail (is);
}


static void
admin_add_incoming_run (
  void *cls,
  const struct TALER_TESTING_Command *cmd,
  struct TALER_TESTING_Interpreter *is)
{
  struct AdminAddIncomingState *fts = cls;
  bool have_public = false;

  (void) cmd;
  fts->is = is;
  /* Use reserve public key as subject */
  if (NULL != fts->reserve_reference)
  {
    const struct TALER_TESTING_Command *ref;
    const struct TALER_ReservePrivateKeyP *reserve_priv;
    const struct TALER_ReservePublicKeyP *reserve_pub;

    ref = TALER_TESTING_interpreter_lookup_command (
      is,
      fts->reserve_reference);
    if (NULL == ref)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_reserve_priv (ref,
                                              &reserve_priv))
    {
      if (GNUNET_OK !=
          TALER_TESTING_get_trait_reserve_pub (ref,
                                               &reserve_pub))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      have_public = true;
      fts->account_pub.reserve_pub.eddsa_pub
        = reserve_pub->eddsa_pub;
      fts->reserve_priv_known = false;
    }
    else
    {
      fts->account_priv.reserve_priv.eddsa_priv
        = reserve_priv->eddsa_priv;
      fts->reserve_priv_known = true;
    }
  }
  else
  {
    /* No referenced reserve to take priv
     * from, no explicit subject given: create new key! */
    GNUNET_CRYPTO_eddsa_key_create (
      &fts->account_priv.reserve_priv.eddsa_priv);
    fts->reserve_priv_known = true;
  }
  if (! have_public)
    GNUNET_CRYPTO_eddsa_key_get_public (
      &fts->account_priv.reserve_priv.eddsa_priv,
      &fts->account_pub.reserve_pub.eddsa_pub);
  fts->reserve_history.type = TALER_EXCHANGE_RTT_CREDIT;
  fts->reserve_history.amount = fts->amount;
  fts->reserve_history.details.in_details.sender_url
    = fts->payto_debit_account; /* remember to NOT free this one... */
  fts->aih
    = TALER_BANK_admin_add_incoming (
        TALER_TESTING_interpreter_get_context (is),
        &fts->auth,
        &fts->account_pub.reserve_pub,
        &fts->amount,
        fts->payto_debit_account,
        &confirmation_cb,
        fts);
  if (NULL == fts->aih)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


/**
 * Free the state of a "/admin/add-incoming" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure
 * @param cmd current CMD being cleaned up.
 */
static void
admin_add_incoming_cleanup (
  void *cls,
  const struct TALER_TESTING_Command *cmd)
{
  struct AdminAddIncomingState *fts = cls;

  if (NULL != fts->aih)
  {
    TALER_TESTING_command_incomplete (fts->is,
                                      cmd->label);
    TALER_BANK_admin_add_incoming_cancel (fts->aih);
    fts->aih = NULL;
  }
  if (NULL != fts->retry_task)
  {
    GNUNET_SCHEDULER_cancel (fts->retry_task);
    fts->retry_task = NULL;
  }
  GNUNET_free (fts);
}


/**
 * Offer internal data from a "/admin/add-incoming" CMD to other
 * commands.
 *
 * @param cls closure.
 * @param[out] ret result
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
admin_add_incoming_traits (void *cls,
                           const void **ret,
                           const char *trait,
                           unsigned int index)
{
  struct AdminAddIncomingState *fts = cls;
  static struct TALER_FullPayto void_uri = {
    .full_payto = (char *) "payto://void/the-exchange?receiver=name=exchange"
  };

  if (MHD_HTTP_OK !=
      fts->expected_http_status)
    return GNUNET_NO; /* requests that failed generate no history */
  if (fts->reserve_priv_known)
  {
    struct TALER_TESTING_Trait traits[] = {
      TALER_TESTING_make_trait_bank_row (&fts->serial_id),
      TALER_TESTING_make_trait_debit_payto_uri (&fts->payto_debit_account),
      TALER_TESTING_make_trait_full_payto_uri (&fts->payto_debit_account),
      /* Used as a marker, content does not matter */
      TALER_TESTING_make_trait_credit_payto_uri (&void_uri),
      TALER_TESTING_make_trait_exchange_bank_account_url (
        fts->exchange_credit_url),
      TALER_TESTING_make_trait_amount (&fts->amount),
      TALER_TESTING_make_trait_timestamp (0,
                                          &fts->timestamp),
      TALER_TESTING_make_trait_reserve_priv (
        &fts->account_priv.reserve_priv),
      TALER_TESTING_make_trait_reserve_pub (
        &fts->account_pub.reserve_pub),
      TALER_TESTING_make_trait_account_priv (
        &fts->account_priv),
      TALER_TESTING_make_trait_account_pub (
        &fts->account_pub),
      TALER_TESTING_make_trait_reserve_history (0,
                                                &fts->reserve_history),
      TALER_TESTING_trait_end ()
    };

    return TALER_TESTING_get_trait (traits,
                                    ret,
                                    trait,
                                    index);
  }
  else
  {
    struct TALER_TESTING_Trait traits[] = {
      TALER_TESTING_make_trait_bank_row (&fts->serial_id),
      TALER_TESTING_make_trait_debit_payto_uri (&fts->payto_debit_account),
      /* Used as a marker, content does not matter */
      TALER_TESTING_make_trait_credit_payto_uri (&void_uri),
      TALER_TESTING_make_trait_exchange_bank_account_url (
        fts->exchange_credit_url),
      TALER_TESTING_make_trait_amount (&fts->amount),
      TALER_TESTING_make_trait_timestamp (0,
                                          &fts->timestamp),
      TALER_TESTING_make_trait_reserve_pub (
        &fts->account_pub.reserve_pub),
      TALER_TESTING_make_trait_account_pub (
        &fts->account_pub),
      TALER_TESTING_make_trait_reserve_history (
        0,
        &fts->reserve_history),
      TALER_TESTING_trait_end ()
    };

    return TALER_TESTING_get_trait (traits,
                                    ret,
                                    trait,
                                    index);
  }
}


/**
 * Create internal state for "/admin/add-incoming" CMD.
 *
 * @param amount the amount to transfer.
 * @param payto_debit_account which account sends money
 * @param auth authentication data
 * @return the internal state
 */
static struct AdminAddIncomingState *
make_fts (const char *amount,
          const struct TALER_BANK_AuthenticationData *auth,
          const struct TALER_FullPayto payto_debit_account)
{
  struct AdminAddIncomingState *fts;

  fts = GNUNET_new (struct AdminAddIncomingState);
  fts->exchange_credit_url = auth->wire_gateway_url;
  fts->payto_debit_account = payto_debit_account;
  fts->auth = *auth;
  fts->expected_http_status = MHD_HTTP_OK;
  if (GNUNET_OK !=
      TALER_string_to_amount (amount,
                              &fts->amount))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Failed to parse amount `%s'\n",
                amount);
    GNUNET_assert (0);
  }
  return fts;
}


/**
 * Helper function to create admin/add-incoming command.
 *
 * @param label command label.
 * @param fts internal state to use
 * @return the command.
 */
static struct TALER_TESTING_Command
make_command (const char *label,
              struct AdminAddIncomingState *fts)
{
  struct TALER_TESTING_Command cmd = {
    .cls = fts,
    .label = label,
    .run = &admin_add_incoming_run,
    .cleanup = &admin_add_incoming_cleanup,
    .traits = &admin_add_incoming_traits
  };

  return cmd;
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_incoming (
  const char *label,
  const char *amount,
  const struct TALER_BANK_AuthenticationData *auth,
  const struct TALER_FullPayto payto_debit_account)
{
  return make_command (label,
                       make_fts (amount,
                                 auth,
                                 payto_debit_account));
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_incoming_with_ref (
  const char *label,
  const char *amount,
  const struct TALER_BANK_AuthenticationData *auth,
  const struct TALER_FullPayto payto_debit_account,
  const char *ref,
  unsigned int http_status)
{
  struct AdminAddIncomingState *fts;

  fts = make_fts (amount,
                  auth,
                  payto_debit_account);
  fts->reserve_reference = ref;
  fts->expected_http_status = http_status;
  return make_command (label,
                       fts);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_incoming_retry (struct TALER_TESTING_Command cmd)
{
  struct AdminAddIncomingState *fts;

  GNUNET_assert (&admin_add_incoming_run == cmd.run);
  fts = cmd.cls;
  fts->do_retry = NUM_RETRIES;
  return cmd;
}


/* end of testing_api_cmd_bank_admin_add_incoming.c */
