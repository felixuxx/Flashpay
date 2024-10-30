/*
  This file is part of TALER
  Copyright (C) 2024 Taler Systems SA

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
 * @file testing/testing_api_cmd_bank_admin_add_kycauth.c
 * @brief implementation of a bank /admin/add-kycauth command
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
 * State for a KYCAUTH wire transfer CMD.
 */
struct AdminAddKycauthState
{

  /**
   * Label of any command that can trait-offer an account priv.
   */
  const char *account_ref;

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
   * Set (by the interpreter) to the account's private key
   * we used to make a wire transfer subject line with.
   */
  union TALER_AccountPrivateKeyP account_priv;

  /**
   * Account public key matching @e account_priv.
   */
  union TALER_AccountPublicKeyP account_pub;

  /**
   * Handle to the pending request at the bank.
   */
  struct TALER_BANK_AdminAddKycauthHandle *aih;

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
   * Expected HTTP status code.
   */
  unsigned int expected_http_status;

  /**
   * Do we have @e account_priv?
   */
  bool have_priv;
};


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
                 const struct TALER_BANK_AdminAddKycauthResponse *air)
{
  struct AdminAddKycauthState *fts = cls;
  struct TALER_TESTING_Interpreter *is = fts->is;

  fts->aih = NULL;
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
    GNUNET_break (0);
    break;
  }
  GNUNET_break (0);
  GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
              "Bank returned HTTP status %u/%d\n",
              air->http_status,
              (int) air->ec);
  TALER_TESTING_interpreter_fail (is);
}


/**
 * Run the KYC AUTH transfer CMD.
 *
 * @param cls closure.
 * @param cmd CMD being run.
 * @param is interpreter state.
 */
static void
admin_add_kycauth_run (void *cls,
                       const struct TALER_TESTING_Command *cmd,
                       struct TALER_TESTING_Interpreter *is)
{
  struct AdminAddKycauthState *fts = cls;

  (void) cmd;
  fts->is = is;
  /* Use account public key as subject */
  if (NULL != fts->account_ref)
  {
    const struct TALER_TESTING_Command *ref;
    const union TALER_AccountPrivateKeyP *account_priv;

    ref = TALER_TESTING_interpreter_lookup_command (
      is,
      fts->account_ref);
    if (NULL == ref)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (is);
      return;
    }
    if (GNUNET_OK !=
        TALER_TESTING_get_trait_account_priv (ref,
                                              &account_priv))
    {
      const union TALER_AccountPublicKeyP *account_pub;

      if (GNUNET_OK !=
          TALER_TESTING_get_trait_account_pub (ref,
                                               &account_pub))
      {
        GNUNET_break (0);
        TALER_TESTING_interpreter_fail (is);
        return;
      }
      fts->account_pub = *account_pub;
    }
    else
    {
      fts->account_priv = *account_priv;
      fts->have_priv = true;
      GNUNET_CRYPTO_eddsa_key_get_public (
        &fts->account_priv.merchant_priv.eddsa_priv,
        &fts->account_pub.merchant_pub.eddsa_pub);
    }
  }
  else
  {
    /* No referenced account, no instance to take priv
     * from, no explicit subject given: create new key! */
    GNUNET_CRYPTO_eddsa_key_create (
      &fts->account_priv.merchant_priv.eddsa_priv);
    fts->have_priv = true;
    GNUNET_CRYPTO_eddsa_key_get_public (
      &fts->account_priv.merchant_priv.eddsa_priv,
      &fts->account_pub.merchant_pub.eddsa_pub);
  }
  fts->aih
    = TALER_BANK_admin_add_kycauth (
        TALER_TESTING_interpreter_get_context (is),
        &fts->auth,
        &fts->account_pub,
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
 * Free the state of a "/admin/add-kycauth" CMD, and possibly
 * cancel a pending operation thereof.
 *
 * @param cls closure
 * @param cmd current CMD being cleaned up.
 */
static void
admin_add_kycauth_cleanup (void *cls,
                           const struct TALER_TESTING_Command *cmd)
{
  struct AdminAddKycauthState *fts = cls;

  if (NULL != fts->aih)
  {
    TALER_TESTING_command_incomplete (fts->is,
                                      cmd->label);
    TALER_BANK_admin_add_kycauth_cancel (fts->aih);
    fts->aih = NULL;
  }
  GNUNET_free (fts);
}


/**
 * Offer internal data from a "/admin/add-kycauth" CMD to other
 * commands.
 *
 * @param cls closure.
 * @param[out] ret result
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
admin_add_kycauth_traits (void *cls,
                          const void **ret,
                          const char *trait,
                          unsigned int index)
{
  struct AdminAddKycauthState *fts = cls;
  static const char *void_uri = "payto://void/the-exchange";
  struct TALER_TESTING_Trait traits[] = {
    /* must be first! */
    TALER_TESTING_make_trait_account_priv (&fts->account_priv),
    TALER_TESTING_make_trait_bank_row (&fts->serial_id),
    TALER_TESTING_make_trait_debit_payto_uri (fts->payto_debit_account),
    TALER_TESTING_make_trait_payto_uri (fts->payto_debit_account),
    /* Used as a marker, content does not matter */
    TALER_TESTING_make_trait_credit_payto_uri (void_uri),
    TALER_TESTING_make_trait_exchange_bank_account_url (
      fts->exchange_credit_url),
    TALER_TESTING_make_trait_amount (&fts->amount),
    TALER_TESTING_make_trait_timestamp (0,
                                        &fts->timestamp),
    TALER_TESTING_make_trait_account_pub (&fts->account_pub),
    TALER_TESTING_trait_end ()
  };

  if (MHD_HTTP_OK !=
      fts->expected_http_status)
    return GNUNET_NO; /* requests that failed generate no history */

  return TALER_TESTING_get_trait (traits + (fts->have_priv ? 0 : 1),
                                  ret,
                                  trait,
                                  index);
}


/**
 * Create internal state for "/admin/add-kycauth" CMD.
 *
 * @param amount the amount to transfer.
 * @param payto_debit_account which account sends money
 * @param auth authentication data
 * @param account_ref reference to command with account
 *    private key to use; NULL to create a fresh key pair
 * @return the internal state
 */
static struct AdminAddKycauthState *
make_fts (const char *amount,
          const struct TALER_BANK_AuthenticationData *auth,
          const char *payto_debit_account,
          const char *account_ref)
{
  struct AdminAddKycauthState *fts;

  fts = GNUNET_new (struct AdminAddKycauthState);
  fts->exchange_credit_url = auth->wire_gateway_url;
  fts->payto_debit_account = payto_debit_account;
  fts->account_ref = account_ref;
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


struct TALER_TESTING_Command
TALER_TESTING_cmd_admin_add_kycauth (
  const char *label,
  const char *amount,
  const struct TALER_BANK_AuthenticationData *auth,
  const char *payto_debit_account,
  const char *account_ref)
{
  struct TALER_TESTING_Command cmd = {
    .cls = make_fts (amount,
                     auth,
                     payto_debit_account,
                     account_ref),
    .label = label,
    .run = &admin_add_kycauth_run,
    .cleanup = &admin_add_kycauth_cleanup,
    .traits = &admin_add_kycauth_traits
  };

  return cmd;
}


/* end of testing_api_cmd_bank_admin_add_kycauth.c */
