/*
  This file is part of TALER
  Copyright (C) 2018 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see
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

/**
 *
 */
struct FakebankTransferState
{

  /**
   * Label to another admin_add_incoming command if we
   * should deposit into an existing reserve, NULL if
   * a fresh reserve should be created.
   */
  const char *reserve_reference;

  /**
   * String describing the amount to add to the reserve.
   */
  struct TALER_Amount amount;

  /**
   * Wire transfer subject. NULL to use public key corresponding
   * to @e reserve_priv or @e reserve_reference.  Should only be
   * set manually to test invalid wire transfer subjects.
   */
  const char *subject;

  /**
   * Sender (debit) account number.
   */
  uint64_t debit_account_no;

  /**
   * Receiver (credit) account number.
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
   * we used to fill the reserve.
   */
  struct TALER_ReservePrivateKeyP reserve_priv;

  /**
   * Set to the API's handle during the operation.
   */
  struct TALER_BANK_AdminAddIncomingHandle *aih;

  /**
   * Interpreter state while command is running.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Set to the wire transfer's unique ID.
   */
  uint64_t serial_id;

};


/**
 * Function called upon completion of our /admin/add/incoming request.
 *
 * @param cls closure with the interpreter state
 * @param http_status HTTP response code, #MHD_HTTP_OK (200) for successful status request
 *                    0 if the exchange's reply is bogus (fails to follow the protocol)
 * @param ec taler-specific error code, #TALER_EC_NONE on success
 * @param serial_id unique ID of the wire transfer
 * @param full_response full response from the exchange (for logging, in case of errors)
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
 * Runs the command.  Note that upon return, the interpreter
 * will not automatically run the next command, as the command
 * may continue asynchronously in other scheduler tasks.  Thus,
 * the command must ensure to eventually call
 * #TALER_TESTING_interpreter_next() or
 * #TALER_TESTING_interpreter_fail().
 *
 * @param is interpreter state
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

      ref = TALER_TESTING_interpreter_lookup_command (is,
                                                      fts->reserve_reference);
      if (NULL == ref)
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      if (GNUNET_OK !=
          TALER_TESTING_get_trait_reserve_priv (ref,
                                                NULL,
                                                &reserve_priv))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
    }
    else
    {
      struct GNUNET_CRYPTO_EddsaPrivateKey *priv;

      priv = GNUNET_CRYPTO_eddsa_key_create ();
      fts->reserve_priv.eddsa_priv = *priv;
      GNUNET_free (priv);
    }
    GNUNET_CRYPTO_eddsa_key_get_public (&fts->reserve_priv.eddsa_priv,
                                        &reserve_pub.eddsa_pub);
    subject = GNUNET_STRINGS_data_to_string_alloc (&reserve_pub,
                                                   sizeof (reserve_pub));
  }

  auth.method = TALER_BANK_AUTH_BASIC;
  auth.details.basic.username = (char *) fts->auth_username;
  auth.details.basic.password = (char *) fts->auth_password;
  fts->is = is;
  fts->aih
    = TALER_BANK_admin_add_incoming (TALER_TESTING_interpreter_get_context (is),
                                     "http://localhost:8082/", /* bank URL: FIXME */
                                     &auth,
                                     "https://exchange.com/", /* exchange URL: FIXME */
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
 * Clean up after the command.  Run during forced termination
 * (CTRL-C) or test failure or test success.
 *
 * @param cls closure
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
 * Extract information from a command that is useful for other
 * commands.
 *
 * @param cls closure
 * @param ret[out] result (could be anything)
 * @param trait name of the trait
 * @param selector more detailed information about which object
 *                 to return in case there were multiple generated
 *                 by the command
 * @return #GNUNET_OK on success
 */
static int
fakebank_transfer_traits (void *cls,
                          void **ret,
                          const char *trait,
                          const char *selector)
{
  struct FakebankTransferState *fts = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_reserve_priv (NULL,
                                           &fts->reserve_priv),
    TALER_TESTING_trait_end ()
  };

  if (NULL != fts->subject)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR; /* we do NOT create a reserve private key */
  }
  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  selector);
}


/**
 * Create fakebank_transfer command.
 *
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer (const char *label,
                                     const char *amount,
                                     uint64_t debit_account_no,
                                     uint64_t credit_account_no,
                                     const char *auth_username,
                                     const char *auth_password)
{
  struct TALER_TESTING_Command cmd;
  struct FakebankTransferState *fts;

  fts = GNUNET_new (struct FakebankTransferState);
  fts->credit_account_no = credit_account_no;
  fts->debit_account_no = debit_account_no;
  fts->auth_username = auth_username;
  fts->auth_password = auth_password;
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
 * Create fakebank_transfer command with custom subject.
 *
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer_with_subject (const char *label,
                                                  const char *amount,
                                                  uint64_t debit_account_no,
                                                  uint64_t credit_account_no,
                                                  const char *auth_username,
                                                  const char *auth_password,
                                                  const char *subject)
{
  struct TALER_TESTING_Command cmd;
  struct FakebankTransferState *fts;

  fts = GNUNET_new (struct FakebankTransferState);
  fts->credit_account_no = credit_account_no;
  fts->debit_account_no = debit_account_no;
  fts->auth_username = auth_username;
  fts->auth_password = auth_password;
  fts->subject = subject;
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
 * Create fakebank_transfer command with custom subject.
 *
 */
struct TALER_TESTING_Command
TALER_TESTING_cmd_fakebank_transfer_with_ref (const char *label,
                                              const char *amount,
                                              uint64_t debit_account_no,
                                              uint64_t credit_account_no,
                                              const char *auth_username,
                                              const char *auth_password,
                                              const char *ref)
{
  struct TALER_TESTING_Command cmd;
  struct FakebankTransferState *fts;

  fts = GNUNET_new (struct FakebankTransferState);
  fts->credit_account_no = credit_account_no;
  fts->debit_account_no = debit_account_no;
  fts->auth_username = auth_username;
  fts->auth_password = auth_password;
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
  cmd.cls = fts;
  cmd.label = label;
  cmd.run = &fakebank_transfer_run;
  cmd.cleanup = &fakebank_transfer_cleanup;
  cmd.traits = &fakebank_transfer_traits;
  return cmd;
}


/* end of testing_api_cmd_fakebank_transfer.c */
