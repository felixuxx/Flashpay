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
 * @file exchange-lib/testing_api_cmd_admin_add_incoming.c
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
#include "taler_testing_bank_lib.h"


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
   * Base URL of the debit account.
   */
  const char *debit_url;

  /**
   * Money receiver account URL.
   */
  const char *payto_credit_account;

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
   * Set to the wire transfer's unique ID.
   */
  uint64_t serial_id;

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
   * enable retries?
   */
  int do_retry;
};


/**
 * Run the "fakebank transfer" CMD.
 *
 * @param cls closure.
 * @param cmd CMD being run.
 * @param is interpreter state.
 */
static void
fakebank_transfer_run (void *cls,
                       const struct TALER_TESTING_Command *cmd,
                       struct TALER_TESTING_Interpreter *is);


/**
 * Task scheduled to re-try #fakebank_transfer_run.
 *
 * @param cls a `struct AdminAddIncomingState`
 */
static void
do_retry (void *cls)
{
  struct AdminAddIncomingState *fts = cls;

  fts->retry_task = NULL;
  fakebank_transfer_run (fts,
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

  fts->aih = NULL;
  if (MHD_HTTP_OK != http_status)
  {
    if (GNUNET_YES == fts->do_retry)
    {
      if ( (0 == http_status) ||
           (TALER_EC_DB_COMMIT_FAILED_ON_RETRY == ec) ||
           (MHD_HTTP_INTERNAL_SERVER_ERROR == http_status) )
      {
        GNUNET_log
          (GNUNET_ERROR_TYPE_INFO,
          "Retrying fakebank transfer failed with %u/%d\n",
          http_status,
          (int) ec);
        /* on DB conflicts, do not use backoff */
        if (TALER_EC_DB_COMMIT_FAILED_ON_RETRY == ec)
          fts->backoff = GNUNET_TIME_UNIT_ZERO;
        else
          fts->backoff = EXCHANGE_LIB_BACKOFF (fts->backoff);
        fts->retry_task = GNUNET_SCHEDULER_add_delayed
                            (fts->backoff,
                            &do_retry,
                            fts);
        return;
      }
    }
    GNUNET_break (0);
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Fakebank returned HTTP status %u/%d\n",
                http_status,
                (int) ec);
    TALER_TESTING_interpreter_fail (is);
    return;
  }

  fts->serial_id = serial_id;
  fts->timestamp = timestamp;
  TALER_TESTING_interpreter_next (is);
}


/**
 * Run the "fakebank transfer" CMD.
 *
 * @param cls closure.
 * @param cmd CMD being run.
 * @param is interpreter state.
 */
static void
fakebank_transfer_run (void *cls,
                       const struct TALER_TESTING_Command *cmd,
                       struct TALER_TESTING_Interpreter *is)
{
  struct AdminAddIncomingState *fts = cls;

  /* Use reserve public key as subject */
  if (NULL != fts->reserve_reference)
  {
    const struct TALER_TESTING_Command *ref;
    const struct TALER_ReservePrivateKeyP *reserve_priv;

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
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    fts->reserve_priv.eddsa_priv = reserve_priv->eddsa_priv;
  }
  else
  {
    if (NULL != fts->instance)
    {
      char *section;
      char *keys;
      struct GNUNET_CRYPTO_EddsaPrivateKey *priv;
      struct GNUNET_CONFIGURATION_Handle *cfg;

      GNUNET_assert (NULL != fts->config_filename);
      cfg = GNUNET_CONFIGURATION_create ();
      if (GNUNET_OK !=
          GNUNET_CONFIGURATION_load (cfg,
                                     fts->config_filename))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }

      GNUNET_asprintf (&section,
                       "instance-%s",
                       fts->instance);
      if (GNUNET_OK !=
          GNUNET_CONFIGURATION_get_value_filename
            (cfg,
            section,
            "TIP_RESERVE_PRIV_FILENAME",
            &keys))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "Configuration fails to specify reserve"
                    " private key filename in section %s\n",
                    section);
        GNUNET_free (section);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      priv = GNUNET_CRYPTO_eddsa_key_create_from_file (keys);
      GNUNET_free (keys);
      if (NULL == priv)
      {
        GNUNET_log_config_invalid
          (GNUNET_ERROR_TYPE_ERROR,
          section,
          "TIP_RESERVE_PRIV_FILENAME",
          "Failed to read private key");
        GNUNET_free (section);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      fts->reserve_priv.eddsa_priv = *priv;
      GNUNET_free (section);
      GNUNET_free (priv);
      GNUNET_CONFIGURATION_destroy (cfg);
    }
    else
    {
      /* No referenced reserve, no instance to take priv
       * from, no explicit subject given: create new key! */
      struct GNUNET_CRYPTO_EddsaPrivateKey *priv;

      priv = GNUNET_CRYPTO_eddsa_key_create ();
      fts->reserve_priv.eddsa_priv = *priv;
      GNUNET_free (priv);
    }
  }
  GNUNET_CRYPTO_eddsa_key_get_public (&fts->reserve_priv.eddsa_priv,
                                      &fts->reserve_pub.eddsa_pub);
  fts->is = is;
  fts->aih
    = TALER_BANK_admin_add_incoming
        (TALER_TESTING_interpreter_get_context (is),
        fts->debit_url,
        &fts->auth,
        &fts->reserve_pub,
        &fts->amount,
        fts->payto_credit_account,
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
 * Free the state of a "fakebank transfer" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure
 * @param cmd current CMD being cleaned up.
 */
static void
fakebank_transfer_cleanup (void *cls,
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
 * Offer internal data from a "fakebank transfer" CMD to other
 * commands.
 *
 * @param cls closure.
 * @param ret[out] result
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static int
fakebank_transfer_traits (void *cls,
                          const void **ret,
                          const char *trait,
                          unsigned int index)
{
  struct AdminAddIncomingState *fts = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_url (1, fts->debit_url),
    TALER_TESTING_MAKE_TRAIT_ROW_ID (&fts->serial_id),
    TALER_TESTING_MAKE_TRAIT_CREDIT_ACCOUNT (fts->payto_credit_account),
    TALER_TESTING_MAKE_TRAIT_DEBIT_ACCOUNT (fts->debit_url),
    TALER_TESTING_make_trait_amount_obj (0, &fts->amount),
    TALER_TESTING_make_trait_absolute_time (0, &fts->timestamp),
    TALER_TESTING_make_trait_reserve_priv (0,
                                           &fts->reserve_priv),
    TALER_TESTING_make_trait_reserve_pub (0,
                                          &fts->reserve_pub),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Create fakebank_transfer command, the subject line will be
 * derived from a randomly created reserve priv.  Note that that
 * reserve priv will then be offered as trait.
 *
 * @param label command label.
 * @param amount amount to transfer.
 * @param account_base_url base URL of the account that implements this
 *        wire transer (which account gives money).
 * @param payto_credit_account which account receives money.
 * @param auth_username username identifying the @a
 *        debit_account_no at the bank.
 * @param auth_password password for @a auth_username.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_incoming
  (const char *label,
  const char *amount,
  const char *account_base_url,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *payto_credit_account)
{
  struct AdminAddIncomingState *fts;

  fts = GNUNET_new (struct AdminAddIncomingState);
  fts->debit_url = account_base_url;
  fts->payto_credit_account = payto_credit_account;
  fts->auth = *auth;
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
      .run = &fakebank_transfer_run,
      .cleanup = &fakebank_transfer_cleanup,
      .traits = &fakebank_transfer_traits
    };

    return cmd;
  }
}


/**
 * Create "fakebank transfer" CMD, letting the caller specify
 * a reference to a command that can offer a reserve private key.
 * This private key will then be used to construct the subject line
 * of the wire transfer.
 *
 * @param label command label.
 * @param amount the amount to transfer.
 * @param bank_url base URL of the bank running the transfer.
 * @param debit_account_no which account (expressed as a number)
 *        gives money.
 * @param credit_account_no which account (expressed as a number)
 *        receives money.
 * @param auth_username username identifying the @a
 *        debit_account_no at the bank.
 * @param auth_password password for @a auth_username.
 * @param ref reference to a command that can offer a reserve
 *        private key.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_incoming_with_ref
  (const char *label,
  const char *amount,
  const char *account_base_url,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *payto_credit_account,
  const char *ref)
{
  struct AdminAddIncomingState *fts;

  fts = GNUNET_new (struct AdminAddIncomingState);
  fts->debit_url = account_base_url;
  fts->payto_credit_account = payto_credit_account;
  fts->auth = *auth;
  fts->reserve_reference = ref;
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
      .run = &fakebank_transfer_run,
      .cleanup = &fakebank_transfer_cleanup,
      .traits = &fakebank_transfer_traits
    };

    return cmd;
  }
}


/**
 * Create "fakebank transfer" CMD, letting the caller specifying
 * the merchant instance.  This version is useful when a tip
 * reserve should be topped up, in fact the interpreter will need
 * the "tipping instance" in order to get the instance public key
 * and make a wire transfer subject out of it.
 *
 * @param label command label.
 * @param amount amount to transfer.
 * @param bank_url base URL of the bank that implements this
 *        wire transer.  For simplicity, both credit and debit
 *        bank account exist at the same bank.
 * @param debit_account_no which account (expressed as a number)
 *        gives money.
 * @param credit_account_no which account (expressed as a number)
 *        receives money.
 *
 * @param auth_username username identifying the @a
 *        debit_account_no at the bank.
 * @param auth_password password for @a auth_username.
 * @param instance the instance that runs the tipping.  Under this
 *        instance, the configuration file will provide the private
 *        key of the tipping reserve.  This data will then used to
 *        construct the wire transfer subject line.
 * @param config_filename configuration file to use.
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_incoming_with_instance
  (const char *label,
  const char *amount,
  const char *account_base_url,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *payto_credit_account,
  const char *instance,
  const char *config_filename)
{
  struct AdminAddIncomingState *fts;

  fts = GNUNET_new (struct AdminAddIncomingState);
  fts->debit_url = account_base_url;
  fts->payto_credit_account = payto_credit_account;
  fts->auth = *auth;
  fts->instance = instance;
  fts->config_filename = config_filename;
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
      .run = &fakebank_transfer_run,
      .cleanup = &fakebank_transfer_cleanup,
      .traits = &fakebank_transfer_traits
    };

    return cmd;
  }
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

  GNUNET_assert (&fakebank_transfer_run == cmd.run);
  fts = cmd.cls;
  fts->do_retry = GNUNET_YES;
  return cmd;
}


/* end of testing_api_cmd_admin_add_incoming.c */
