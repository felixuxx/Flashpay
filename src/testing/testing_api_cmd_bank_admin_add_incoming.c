/*
  This file is part of TALER
  Copyright (C) 2018-2020 Taler Systems SA

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
#include "taler_fakebank_lib.h"
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
 * State for a "fakebank transfer" CMD.
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
  const char *payto_debit_account;

  /**
   * Username to use for authentication.
   */
  struct TALER_BANK_AuthenticationData auth;

  /**
   * Set (by the interpreter) to the reserve's private key
   * we used to make a wire transfer subject line with.
   */
  struct TALER_ReservePrivateKeyP reserve_priv;

  /**
   * Whether we know the private key or not.
   */
  bool reserve_priv_known;

  /**
   * Reserve public key matching @e reserve_priv.
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Handle to the pending request at the fakebank.
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
  struct TALER_EXCHANGE_ReserveHistory reserve_history;

  /**
   * Set to the wire transfer's unique ID.
   */
  uint64_t serial_id;

  /**
   * Set to the wire transfer's row ID in network byte order.
   */
  uint64_t row_id_nbo;

  /**
   * Timestamp of the transaction (as returned from the bank).
   */
  struct GNUNET_TIME_Absolute timestamp;

  /**
   * Merchant instance.  Sometimes used to get the tip reserve
   * private key by reading the appropriate config section.
   */
  const char *instance;

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
 * Run the "fakebank transfer" CMD.
 *
 * @param cls closure.
 * @param cmd CMD being run.
 * @param is interpreter state.
 */
static void
admin_add_incoming_run (void *cls,
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
  fts->is->commands[fts->is->ip].last_req_time
    = GNUNET_TIME_absolute_get ();
  admin_add_incoming_run (fts,
                          NULL,
                          fts->is);
}


/**
 * This callback will process the fakebank response to the wire
 * transfer.  It just checks whether the HTTP response code is
 * acceptable.
 *
 * @param cls closure with the interpreter state
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for
 *        successful status request; 0 if the exchange's reply is
 *        bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param serial_id unique ID of the wire transfer
 * @param timestamp time stamp of the transaction made.
 * @param json raw response
 */
static void
confirmation_cb (void *cls,
                 unsigned int http_status,
                 enum TALER_ErrorCode ec,
                 uint64_t serial_id,
                 struct GNUNET_TIME_Absolute timestamp,
                 const json_t *json)
{
  struct AdminAddIncomingState *fts = cls;
  struct TALER_TESTING_Interpreter *is = fts->is;

  (void) json;
  fts->row_id_nbo = GNUNET_htonll (serial_id);
  fts->reserve_history.details.in_details.timestamp = timestamp;
  fts->reserve_history.details.in_details.wire_reference = &fts->row_id_nbo;
  fts->reserve_history.details.in_details.wire_reference_size
    = sizeof (fts->row_id_nbo);
  fts->aih = NULL;
  switch (http_status)
  {
  case MHD_HTTP_OK:
    fts->serial_id = serial_id;
    fts->timestamp = timestamp;
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
    }
    break;
  default:
    if (0 != fts->do_retry)
    {
      fts->do_retry--;
      if ( (0 == http_status) ||
           (TALER_EC_GENERIC_DB_SOFT_FAILURE == ec) ||
           (MHD_HTTP_INTERNAL_SERVER_ERROR == http_status) )
      {
        GNUNET_log (
          GNUNET_ERROR_TYPE_INFO,
          "Retrying fakebank transfer failed with %u/%d\n",
          http_status,
          (int) ec);
        /* on DB conflicts, do not use backoff */
        if (TALER_EC_GENERIC_DB_SOFT_FAILURE == ec)
          fts->backoff = GNUNET_TIME_UNIT_ZERO;
        else
          fts->backoff = GNUNET_TIME_randomized_backoff (fts->backoff,
                                                         MAX_BACKOFF);
        fts->is->commands[fts->is->ip].num_tries++;
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
              "Fakebank returned HTTP status %u/%d\n",
              http_status,
              (int) ec);
  TALER_TESTING_interpreter_fail (is);
}


/**
 * Run the "fakebank transfer" CMD.
 *
 * @param cls closure.
 * @param cmd CMD being run.
 * @param is interpreter state.
 */
static void
admin_add_incoming_run (void *cls,
                        const struct TALER_TESTING_Command *cmd,
                        struct TALER_TESTING_Interpreter *is)
{
  struct AdminAddIncomingState *fts = cls;
  bool have_public = false;

  (void) cmd;
  /* Use reserve public key as subject */
  if (NULL != fts->reserve_reference)
  {
    const struct TALER_TESTING_Command *ref;
    const struct TALER_ReservePrivateKeyP *reserve_priv;
    const struct TALER_ReservePublicKeyP *reserve_pub;

    ref = TALER_TESTING_interpreter_lookup_command
            (is, fts->reserve_reference);
    if (NULL == ref)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_reserve_priv (ref,
                                              0,
                                              &reserve_priv))
    {
      if (GNUNET_OK != TALER_TESTING_get_trait_reserve_pub (ref,
                                                            0,
                                                            &reserve_pub))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      have_public = true;
      fts->reserve_pub.eddsa_pub = reserve_pub->eddsa_pub;
      fts->reserve_priv_known = false;
    }
    else
    {
      fts->reserve_priv.eddsa_priv = reserve_priv->eddsa_priv;
      fts->reserve_priv_known = true;
    }
  }
  else
  {
    /* No referenced reserve, no instance to take priv
     * from, no explicit subject given: create new key! */
    GNUNET_CRYPTO_eddsa_key_create (&fts->reserve_priv.eddsa_priv);
    fts->reserve_priv_known = true;
  }
  if (! have_public)
    GNUNET_CRYPTO_eddsa_key_get_public (&fts->reserve_priv.eddsa_priv,
                                        &fts->reserve_pub.eddsa_pub);
  fts->reserve_history.type = TALER_EXCHANGE_RTT_CREDIT;
  fts->reserve_history.amount = fts->amount;
  fts->reserve_history.details.in_details.sender_url
    = (char *) fts->payto_debit_account; /* remember to NOT free this one... */
  fts->is = is;
  fts->aih
    = TALER_BANK_admin_add_incoming (
        TALER_TESTING_interpreter_get_context (is),
        &fts->auth,
        &fts->reserve_pub,
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
admin_add_incoming_cleanup (void *cls,
                            const struct TALER_TESTING_Command *cmd)
{
  struct AdminAddIncomingState *fts = cls;

  if (NULL != fts->aih)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %s did not complete\n",
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
static int
admin_add_incoming_traits (void *cls,
                           const void **ret,
                           const char *trait,
                           unsigned int index)
{
  struct AdminAddIncomingState *fts = cls;
  if (fts->reserve_priv_known)
  {
    struct TALER_TESTING_Trait traits[] = {
      TALER_TESTING_make_trait_bank_row (&fts->serial_id),
      TALER_TESTING_make_trait_payto (TALER_TESTING_PT_DEBIT,
                                      fts->payto_debit_account),
      /* Used as a marker, content does not matter */
      TALER_TESTING_make_trait_payto (TALER_TESTING_PT_CREDIT,
                                      "payto://void/the-exchange"),
      TALER_TESTING_make_trait_url (TALER_TESTING_UT_EXCHANGE_BANK_ACCOUNT_URL,
                                    fts->exchange_credit_url),
      TALER_TESTING_make_trait_amount_obj (0, &fts->amount),
      TALER_TESTING_make_trait_absolute_time (0, &fts->timestamp),
      TALER_TESTING_make_trait_reserve_priv (0,
                                             &fts->reserve_priv),
      TALER_TESTING_make_trait_reserve_pub (0,
                                            &fts->reserve_pub),
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
      TALER_TESTING_make_trait_payto (TALER_TESTING_PT_DEBIT,
                                      fts->payto_debit_account),
      /* Used as a marker, content does not matter */
      TALER_TESTING_make_trait_payto (TALER_TESTING_PT_CREDIT,
                                      "payto://void/the-exchange"),
      TALER_TESTING_make_trait_url (TALER_TESTING_UT_EXCHANGE_BANK_ACCOUNT_URL,
                                    fts->exchange_credit_url),
      TALER_TESTING_make_trait_amount_obj (0, &fts->amount),
      TALER_TESTING_make_trait_absolute_time (0, &fts->timestamp),
      TALER_TESTING_make_trait_reserve_pub (0,
                                            &fts->reserve_pub),
      TALER_TESTING_make_trait_reserve_history (0,
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
          const char *payto_debit_account)
{
  struct AdminAddIncomingState *fts;

  fts = GNUNET_new (struct AdminAddIncomingState);
  fts->exchange_credit_url = auth->wire_gateway_url;
  fts->payto_debit_account = payto_debit_account;
  fts->auth = *auth;
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


/**
 * Create admin/add-incoming command.
 *
 * @param label command label.
 * @param amount amount to transfer.
 * @param payto_debit_account which account sends money.
 * @param auth authentication data
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_incoming (const char *label,
                                      const char *amount,
                                      const struct
                                      TALER_BANK_AuthenticationData *auth,
                                      const char *payto_debit_account)
{
  return make_command (label,
                       make_fts (amount,
                                 auth,
                                 payto_debit_account));
}


/**
 * Create "/admin/add-incoming" CMD, letting the caller specify
 * a reference to a command that can offer a reserve private key.
 * This private key will then be used to construct the subject line
 * of the wire transfer.
 *
 * @param label command label.
 * @param amount the amount to transfer.
 * @param payto_debit_account which account sends money
 * @param auth authentication data
 * @param ref reference to a command that can offer a reserve
 *        private key or public key.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_incoming_with_ref
  (const char *label,
  const char *amount,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *payto_debit_account,
  const char *ref)
{
  struct AdminAddIncomingState *fts;

  fts = make_fts (amount,
                  auth,
                  payto_debit_account);
  fts->reserve_reference = ref;
  return make_command (label,
                       fts);
}


/**
 * Modify a fakebank transfer command to enable retries when the
 * reserve is not yet full or we get other transient errors from the
 * fakebank.
 *
 * @param cmd a fakebank transfer command
 * @return the command with retries enabled
 */
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
