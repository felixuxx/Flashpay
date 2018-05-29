/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

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
 * @file exchange-lib/testing_api_cmd_fakebank_transfer.c
 * @brief implementation of a fakebank wire transfer command
 * @author Christian Grothoff
 * @author Marcello Stanisci
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "exchange_api_handle.h"
#include "taler_bank_service.h"
#include "taler_fakebank_lib.h"
#include "taler_signatures.h"
#include "taler_testing_lib.h"
#include "taler_testing_bank_lib.h"

/**
 * State for a "fakebank transfer" CMD.
 */
struct FakebankTransferState
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
   * Wire transfer subject.
   */
  const char *subject;

  /**
   * Base URL of the bank serving the request.
   */
  const char *bank_url;

  /**
   * Money sender account number.
   */
  uint64_t debit_account_no;

  /**
   * Money receiver account number.
   */
  uint64_t credit_account_no;

  /**
   * Username to use for authentication.
   */
  const char *auth_username;

  /**
   * Password to use for authentication.
   */
  const char *auth_password;

  /**
   * Set (by the interpreter) to the reserve's private key
   * we used to make a wire transfer subject line with.
   */
  struct TALER_ReservePrivateKeyP reserve_priv;

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
   * Exchange URL.  FIXME: explaing is needed.
   */
  const char *exchange_url;

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
};


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
 * @param full_response full response from the exchange (for
 *        logging, in case of errors)
 */
static void
add_incoming_cb (void *cls,
                 unsigned int http_status,
		 enum TALER_ErrorCode ec,
                 uint64_t serial_id,
                 const json_t *full_response)
{
  struct FakebankTransferState *fts = cls;
  struct TALER_TESTING_Interpreter *is = fts->is;

  fts->aih = NULL;
  fts->serial_id = serial_id;
  if (MHD_HTTP_OK != http_status)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
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
  struct FakebankTransferState *fts = cls;
  char *subject;
  struct TALER_BANK_AuthenticationData auth;
  struct TALER_ReservePublicKeyP reserve_pub;

  if (NULL != fts->subject)
  {
    subject = GNUNET_strdup (fts->subject);
  }
  else
  {
    /* Use reserve public key as subject */
    if (NULL != fts->reserve_reference)
    {
      const struct TALER_TESTING_Command *ref;
      struct TALER_ReservePrivateKeyP *reserve_priv;

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
        GNUNET_assert (NULL != fts->config_filename);
        char *section;
        char *keys;
        struct GNUNET_CRYPTO_EddsaPrivateKey *priv;
        struct GNUNET_CONFIGURATION_Handle *cfg;
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
        if (NULL == priv)
        {
          GNUNET_log_config_invalid
            (GNUNET_ERROR_TYPE_ERROR,
             section,
             "TIP_RESERVE_PRIV_FILENAME",
             "Failed to read private key");
          GNUNET_free (keys);
          GNUNET_free (section);
          TALER_TESTING_interpreter_fail (is);
          return;
        }
        fts->reserve_priv.eddsa_priv = *priv;
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
    GNUNET_CRYPTO_eddsa_key_get_public
      (&fts->reserve_priv.eddsa_priv, &reserve_pub.eddsa_pub);
    subject = GNUNET_STRINGS_data_to_string_alloc
      (&reserve_pub, sizeof (reserve_pub));
  }

  auth.method = TALER_BANK_AUTH_BASIC;
  auth.details.basic.username = (char *) fts->auth_username;
  auth.details.basic.password = (char *) fts->auth_password;
  fts->is = is;
  fts->aih = TALER_BANK_admin_add_incoming
    (TALER_TESTING_interpreter_get_context (is),
     fts->bank_url,
     &auth,
     fts->exchange_url,
     subject,
     &fts->amount,
     fts->debit_account_no,
     fts->credit_account_no,
     &add_incoming_cb,
     fts);
  GNUNET_free (subject);
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
  struct FakebankTransferState *fts = cls;

  if (NULL != fts->aih)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %s did not complete\n",
                cmd->label);
    TALER_BANK_admin_add_incoming_cancel (fts->aih);
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
 *
 * @return #GNUNET_OK on success.
 */
static int
fakebank_transfer_traits (void *cls,
                          void **ret,
                          const char *trait,
                          unsigned int index)
{
  struct FakebankTransferState *fts = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_reserve_priv
      (0, &fts->reserve_priv),
    TALER_TESTING_MAKE_TRAIT_DEBIT_ACCOUNT
      (&fts->debit_account_no),
    TALER_TESTING_MAKE_TRAIT_CREDIT_ACCOUNT
      (&fts->credit_account_no),
    TALER_TESTING_make_trait_url (0, fts->exchange_url),
    TALER_TESTING_make_trait_transfer_subject (0, fts->subject),
    TALER_TESTING_MAKE_TRAIT_ROW_ID (&fts->serial_id),
    TALER_TESTING_make_trait_amount_obj (0, &fts->amount),
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
 * @param bank_url base URL of the bank that implements this
 *        wire transer.  For simplicity, both credit and debit
 *        bank account exist at the same bank.
 * @param debit_account_no which account (expressed as a number)
 *        gives money.
 * @param credit_account_no which account (expressed as a number)
 *        receives money.
 * @param auth_username username identifying the @a
 *        debit_account_no at the bank.
 * @param auth_password password for @a auth_username.
 * @param exchange_url which exchange is involved in this transfer.
 *        This data is used for tracking purposes (FIXME: explain
 *        _how_).
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer
  (const char *label,
   const char *amount,
   const char *bank_url,
   uint64_t debit_account_no,
   uint64_t credit_account_no,
   const char *auth_username,
   const char *auth_password,
   const char *exchange_url)
{
  struct TALER_TESTING_Command cmd;
  struct FakebankTransferState *fts;

  fts = GNUNET_new (struct FakebankTransferState);
  fts->bank_url = bank_url;
  fts->credit_account_no = credit_account_no;
  fts->debit_account_no = debit_account_no;
  fts->auth_username = auth_username;
  fts->auth_password = auth_password;
  fts->exchange_url = exchange_url;
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
  cmd.cls = fts;
  cmd.label = label;
  cmd.run = &fakebank_transfer_run;
  cmd.cleanup = &fakebank_transfer_cleanup;
  cmd.traits = &fakebank_transfer_traits;
  return cmd;
}

/**
 * Create "fakebank transfer" CMD, letting the caller specifying
 * the subject line.
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
 * @param subject wire transfer's subject line.
 * @param exchange_url which exchange is involved in this transfer.
 *        This data is used for tracking purposes (FIXME: explain
 *        _how_).
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer_with_subject
  (const char *label,
   const char *amount,
   const char *bank_url,
   uint64_t debit_account_no,
   uint64_t credit_account_no,
   const char *auth_username,
   const char *auth_password,
   const char *subject,
   const char *exchange_url)
{
  struct TALER_TESTING_Command cmd;
  struct FakebankTransferState *fts;

  fts = GNUNET_new (struct FakebankTransferState);
  fts->bank_url = bank_url;
  fts->credit_account_no = credit_account_no;
  fts->debit_account_no = debit_account_no;
  fts->auth_username = auth_username;
  fts->auth_password = auth_password;
  fts->subject = subject;
  fts->exchange_url = exchange_url;
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
  cmd.cls = fts;
  cmd.label = label;
  cmd.run = &fakebank_transfer_run;
  cmd.cleanup = &fakebank_transfer_cleanup;
  cmd.traits = &fakebank_transfer_traits;
  return cmd;
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
 * @param exchange_url the exchage involved in the transfer,
 *        tipically receiving the money in order to fuel a reserve.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer_with_ref
  (const char *label,
   const char *amount,
   const char *bank_url,
   uint64_t debit_account_no,
   uint64_t credit_account_no,
   const char *auth_username,
   const char *auth_password,
   const char *ref,
   const char *exchange_url)
{
  struct TALER_TESTING_Command cmd;
  struct FakebankTransferState *fts;

  fts = GNUNET_new (struct FakebankTransferState);
  fts->bank_url = bank_url;
  fts->credit_account_no = credit_account_no;
  fts->debit_account_no = debit_account_no;
  fts->auth_username = auth_username;
  fts->auth_password = auth_password;
  fts->reserve_reference = ref;
  fts->exchange_url = exchange_url;
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
  cmd.cls = fts;
  cmd.label = label;
  cmd.run = &fakebank_transfer_run;
  cmd.cleanup = &fakebank_transfer_cleanup;
  cmd.traits = &fakebank_transfer_traits;
  return cmd;
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
 * @param exchange_url which exchange is involved in this transfer.
 *        This data is used for tracking purposes (FIXME: explain
 *        _how_).
 * @param config_filename configuration file to use.
 *
 * @return the command.
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer_with_instance
  (const char *label,
   const char *amount,
   const char *bank_url,
   uint64_t debit_account_no,
   uint64_t credit_account_no,
   const char *auth_username,
   const char *auth_password,
   const char *instance,
   const char *exchange_url,
   const char *config_filename)
{
  struct TALER_TESTING_Command cmd;
  struct FakebankTransferState *fts;

  fts = GNUNET_new (struct FakebankTransferState);
  fts->bank_url = bank_url;
  fts->credit_account_no = credit_account_no;
  fts->debit_account_no = debit_account_no;
  fts->auth_username = auth_username;
  fts->auth_password = auth_password;
  fts->instance = instance;
  fts->exchange_url = exchange_url;
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
  cmd.cls = fts;
  cmd.label = label;
  cmd.run = &fakebank_transfer_run;
  cmd.cleanup = &fakebank_transfer_cleanup;
  cmd.traits = &fakebank_transfer_traits;
  return cmd;
}

/* end of testing_api_cmd_fakebank_transfer.c */
