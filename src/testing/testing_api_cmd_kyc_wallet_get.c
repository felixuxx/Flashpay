/*
  This file is part of TALER
  Copyright (C) 2021 Taler Systems SA

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
 * @file testing/testing_api_cmd_kyc_wallet_get.c
 * @brief Implement the testing CMDs for the /kyc_wallet/ GET operations.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_testing_lib.h"

/**
 * State for a "/kyc-wallet" GET CMD.
 */
struct KycWalletGetState
{

  /**
   * Private key of the reserve (account).
   */
  struct TALER_ReservePrivateKeyP reserve_priv;

  /**
   * Public key of the reserve (account).
   */
  struct TALER_ReservePublicKeyP reserve_pub;

  /**
   * Payto URI of the reserve of the wallet.
   */
  char *reserve_payto_uri;

  /**
   * Command to get a reserve private key from.
   */
  const char *reserve_reference;

  /**
   * Expected HTTP response code.
   */
  unsigned int expected_response_code;

  /**
   * Set to the KYC UUID *if* the exchange replied with
   * a request for KYC (#MHD_HTTP_ACCEPTED).
   */
  uint64_t kyc_uuid;

  /**
   * Handle to the "track transaction" pending operation.
   */
  struct TALER_EXCHANGE_KycWalletHandle *kwh;

  /**
   * Interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;
};


/**
 * Handle response to the command.
 *
 * @param cls closure.
 * @param wkr GET deposit response details
 */
static void
wallet_kyc_cb (void *cls,
               const struct TALER_EXCHANGE_WalletKycResponse *wkr)
{
  struct KycWalletGetState *kwg = cls;
  struct TALER_TESTING_Interpreter *is = kwg->is;
  struct TALER_TESTING_Command *cmd = &is->commands[is->ip];

  kwg->kwh = NULL;
  if (kwg->expected_response_code != wkr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u/%d to command %s in %s:%u\n",
                wkr->http_status,
                (int) wkr->ec,
                cmd->label,
                __FILE__,
                __LINE__);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  switch (wkr->http_status)
  {
  case MHD_HTTP_OK:
    kwg->kyc_uuid = wkr->payment_target_uuid;
    break;
  case MHD_HTTP_NO_CONTENT:
    break;
  case MHD_HTTP_FORBIDDEN:
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  default:
    GNUNET_break (0);
    break;
  }
  TALER_TESTING_interpreter_next (kwg->is);
}


/**
 * Run the command.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
wallet_kyc_run (void *cls,
                const struct TALER_TESTING_Command *cmd,
                struct TALER_TESTING_Interpreter *is)
{
  struct KycWalletGetState *kwg = cls;

  (void) cmd;
  kwg->is = is;
  if (NULL != kwg->reserve_reference)
  {
    const struct TALER_TESTING_Command *res_cmd;
    const struct TALER_ReservePrivateKeyP *reserve_priv;

    res_cmd = TALER_TESTING_interpreter_lookup_command (kwg->is,
                                                        kwg->reserve_reference);
    if (NULL == res_cmd)
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (kwg->is);
      return;
    }

    if (GNUNET_OK !=
        TALER_TESTING_get_trait_reserve_priv (res_cmd,
                                              &reserve_priv))
    {
      GNUNET_break (0);
      TALER_TESTING_interpreter_fail (kwg->is);
      return;
    }
    kwg->reserve_priv = *reserve_priv;
  }
  else
  {
    GNUNET_CRYPTO_eddsa_key_create (&kwg->reserve_priv.eddsa_priv);
  }
  kwg->reserve_payto_uri
    = TALER_payto_from_reserve (TALER_EXCHANGE_get_base_url (is->exchange),
                                &kwg->reserve_pub);
  GNUNET_CRYPTO_eddsa_key_get_public (&kwg->reserve_priv.eddsa_priv,
                                      &kwg->reserve_pub.eddsa_pub);
  kwg->kwh = TALER_EXCHANGE_kyc_wallet (is->exchange,
                                        &kwg->reserve_priv,
                                        &wallet_kyc_cb,
                                        kwg);
  GNUNET_assert (NULL != kwg->kwh);
}


/**
 * Cleanup the state from a "track transaction" CMD, and possibly
 * cancel a operation thereof.
 *
 * @param cls closure with our `struct KycWalletGetState`
 * @param cmd the command which is being cleaned up.
 */
static void
wallet_kyc_cleanup (void *cls,
                    const struct TALER_TESTING_Command *cmd)
{
  struct KycWalletGetState *kwg = cls;

  if (NULL != kwg->kwh)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_WARNING,
                "Command %u (%s) did not complete\n",
                kwg->is->ip,
                cmd->label);
    TALER_EXCHANGE_kyc_wallet_cancel (kwg->kwh);
    kwg->kwh = NULL;
  }
  GNUNET_free (kwg->reserve_payto_uri);
  GNUNET_free (kwg);
}


/**
 * Offer internal data from a "wallet KYC" CMD.
 *
 * @param cls closure.
 * @param[out] ret result (could be anything).
 * @param trait name of the trait.
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success.
 */
static enum GNUNET_GenericReturnValue
wallet_kyc_traits (void *cls,
                   const void **ret,
                   const char *trait,
                   unsigned int index)
{
  struct KycWalletGetState *kwg = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_make_trait_reserve_priv (&kwg->reserve_priv),
    TALER_TESTING_make_trait_reserve_pub (&kwg->reserve_pub),
    TALER_TESTING_make_trait_payment_target_uuid (&kwg->kyc_uuid),
    TALER_TESTING_make_trait_payto_uri (
      (const char **) &kwg->reserve_payto_uri),
    TALER_TESTING_trait_end ()
  };

  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_wallet_kyc_get (const char *label,
                                  const char *reserve_reference,
                                  unsigned int expected_response_code)
{
  struct KycWalletGetState *kwg;

  kwg = GNUNET_new (struct KycWalletGetState);
  kwg->reserve_reference = reserve_reference;
  kwg->expected_response_code = expected_response_code;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = kwg,
      .label = label,
      .run = &wallet_kyc_run,
      .cleanup = &wallet_kyc_cleanup,
      .traits = &wallet_kyc_traits
    };

    return cmd;
  }
}


/* end of testing_api_cmd_kyc_wallet_get.c */
