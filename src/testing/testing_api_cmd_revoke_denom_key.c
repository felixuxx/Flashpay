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
 * @file testing/testing_api_cmd_revoke_denom_key.c
 * @brief Implement the revoke test command.
 * @author Christian Grothoff
 */
#include "platform.h"
#include "taler_json_lib.h"
#include <gnunet/gnunet_curl_lib.h>
#include "taler_signatures.h"
#include "taler_testing_lib.h"


/**
 * State for a "revoke" CMD.
 */
struct RevokeState
{
  /**
   * Expected HTTP status code.
   */
  unsigned int expected_response_code;

  /**
   * Command that offers a denomination to revoke.
   */
  const char *coin_reference;

  /**
   * The interpreter state.
   */
  struct TALER_TESTING_Interpreter *is;

  /**
   * Handle for the operation.
   */
  struct TALER_EXCHANGE_ManagementRevokeDenominationKeyHandle *kh;

  /**
   * Should we use a bogus signature?
   */
  bool bad_sig;

};


/**
 * Function called with information about the post revocation operation result.
 *
 * @param cls closure with a `struct RevokeState *`
 * @param hr HTTP response data
 */
static void
success_cb (
  void *cls,
  const struct TALER_EXCHANGE_HttpResponse *hr)
{
  struct RevokeState *rs = cls;

  rs->kh = NULL;
  if (rs->expected_response_code != hr->http_status)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Unexpected response code %u to command %s in %s:%u\n",
                hr->http_status,
                rs->is->commands[rs->is->ip].label,
                __FILE__,
                __LINE__);
    json_dumpf (hr->reply,
                stderr,
                0);
    TALER_TESTING_interpreter_fail (rs->is);
    return;
  }
  TALER_TESTING_interpreter_next (rs->is);
}


/**
 * Cleanup the state.
 *
 * @param cls closure, must be a `struct RevokeState`.
 * @param cmd the command which is being cleaned up.
 */
static void
revoke_cleanup (void *cls,
                const struct TALER_TESTING_Command *cmd)
{
  struct RevokeState *rs = cls;

  if (NULL != rs->kh)
  {
    TALER_EXCHANGE_management_revoke_denomination_key_cancel (rs->kh);
    rs->kh = NULL;
  }
  GNUNET_free (rs);
}


/**
 * Offer internal data from a "revoke" CMD to other CMDs.
 *
 * @param cls closure
 * @param[out] ret result (could be anything)
 * @param trait name of the trait
 * @param index index number of the object to offer.
 * @return #GNUNET_OK on success
 */
static int
revoke_traits (void *cls,
               const void **ret,
               const char *trait,
               unsigned int index)
{
  struct RevokeState *rs = cls;
  struct TALER_TESTING_Trait traits[] = {
    TALER_TESTING_trait_end ()
  };

  (void) rs;
  return TALER_TESTING_get_trait (traits,
                                  ret,
                                  trait,
                                  index);
}


/**
 * Run the "revoke" command.  The core of the function
 * is to call the "keyup" utility passing it the base32
 * encoding of the denomination to revoke.
 *
 * @param cls closure.
 * @param cmd the command to execute.
 * @param is the interpreter state.
 */
static void
revoke_run (void *cls,
            const struct TALER_TESTING_Command *cmd,
            struct TALER_TESTING_Interpreter *is)
{
  struct RevokeState *rs = cls;
  const struct TALER_TESTING_Command *coin_cmd;
  const struct TALER_EXCHANGE_DenomPublicKey *denom_pub;
  char *exchange_url;
  struct TALER_MasterSignatureP master_sig;

  rs->is = is;
  /* Get denom pub from trait */
  coin_cmd = TALER_TESTING_interpreter_lookup_command (is,
                                                       rs->coin_reference);

  if (NULL == coin_cmd)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
  GNUNET_assert (GNUNET_OK ==
                 TALER_TESTING_get_trait_denom_pub (coin_cmd,
                                                    0,
                                                    &denom_pub));
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "Trying to revoke denom '%s..'\n",
              TALER_B2S (&denom_pub->h_key));
  if (rs->bad_sig)
  {
    memset (&master_sig,
            42,
            sizeof (master_sig));
  }
  else
  {
    char *fn;
    struct TALER_MasterPrivateKeyP master_priv;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (is->cfg,
                                                 "exchange-offline",
                                                 "MASTER_PRIV_FILE",
                                                 &fn))
    {
      GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                                 "exchange-offline",
                                 "MASTER_PRIV_FILE");
      TALER_TESTING_interpreter_next (rs->is);
      return;
    }
    if (GNUNET_SYSERR ==
        GNUNET_DISK_directory_create_for_file (fn))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Could not setup directory for master private key file `%s'\n",
                  fn);
      GNUNET_free (fn);
      TALER_TESTING_interpreter_next (rs->is);
      return;
    }
    if (GNUNET_OK !=
        GNUNET_CRYPTO_eddsa_key_from_file (fn,
                                           GNUNET_YES,
                                           &master_priv.eddsa_priv))
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "Could not load master private key from `%s'\n",
                  fn);
      GNUNET_free (fn);
      TALER_TESTING_interpreter_next (rs->is);
      return;
    }
    GNUNET_free (fn);

    /* now sign */
    {
      struct TALER_MasterDenominationKeyRevocationPS kv = {
        .purpose.purpose = htonl (
          TALER_SIGNATURE_MASTER_DENOMINATION_KEY_REVOKED),
        .purpose.size = htonl (sizeof (kv)),
        .h_denom_pub = denom_pub->h_key
      };

      GNUNET_CRYPTO_eddsa_sign (&master_priv.eddsa_priv,
                                &kv,
                                &master_sig.eddsa_signature);
    }
  }
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_string (is->cfg,
                                             "exchange",
                                             "BASE_URL",
                                             &exchange_url))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "BASE_URL");
    TALER_TESTING_interpreter_next (rs->is);
    return;
  }
  rs->kh = TALER_EXCHANGE_management_revoke_denomination_key (
    is->ctx,
    exchange_url,
    &denom_pub->h_key,
    &master_sig,
    &success_cb,
    rs);
  GNUNET_free (exchange_url);
  if (NULL == rs->kh)
  {
    GNUNET_break (0);
    TALER_TESTING_interpreter_fail (is);
    return;
  }
}


struct TALER_TESTING_Command
TALER_TESTING_cmd_revoke_denomination (
  const char *label,
  unsigned int expected_response_code,
  bool bad_sig,
  const char *denom_ref)
{
  struct RevokeState *rs;

  rs = GNUNET_new (struct RevokeState);
  rs->expected_response_code = expected_response_code;
  rs->coin_reference = denom_ref;
  rs->bad_sig = bad_sig;
  {
    struct TALER_TESTING_Command cmd = {
      .cls = rs,
      .label = label,
      .run = &revoke_run,
      .cleanup = &revoke_cleanup,
      .traits = &revoke_traits
    };

    return cmd;
  }
}
