/*
  This file is part of TALER
  Copyright (C) 2014-2021 Taler Systems SA

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file util/taler-crypto-worker.c
 * @brief Standalone process to perform various cryptographic operations.
 * @author Florian Dold
 */
#include "platform.h"
#include "taler_util.h"
#include <gnunet/gnunet_json_lib.h>
#include <gnunet/gnunet_crypto_lib.h>
#include "taler_error_codes.h"
#include "taler_json_lib.h"
#include "taler_signatures.h"
#include "secmod_common.h"


/**
 * Return value from main().
 */
static int global_ret;


/**
 * Main function that will be run under the GNUnet scheduler.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param cfg configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  (void) cls;
  (void) args;
  (void) cfgfile;

  json_t *req;
  GNUNET_log (GNUNET_ERROR_TYPE_INFO,
              "started crypto worker\n");

  for (;;)
  {
    const char *op;
    const json_t *args;
    req = json_loadf (stdin, JSON_DISABLE_EOF_CHECK, NULL);
    if (NULL == req)
    {
      if (feof (stdin))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                    "end of input\n");
        global_ret = 0;
        return;
      }
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "invalid JSON\n");
      global_ret = 1;
      return;
    }
    op = json_string_value (json_object_get (req,
                                             "op"));
    if (! op)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "no op specified\n");
      global_ret = 1;
      return;
    }
    args = json_object_get (req, "args");
    if (! args)
    {
      GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                  "no args specified\n");
      global_ret = 1;
      return;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "got request\n");
    if (0 == strcmp ("eddsa_verify",
                     op))
    {
      struct GNUNET_CRYPTO_EddsaPublicKey pub;
      struct GNUNET_CRYPTO_EddsaSignature sig;
      struct GNUNET_CRYPTO_EccSignaturePurpose *msg;
      size_t msg_size;
      enum GNUNET_GenericReturnValue verify_ret;
      json_t *resp;
      struct GNUNET_JSON_Specification eddsa_verify_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("pub",
                                     &pub),
        GNUNET_JSON_spec_fixed_auto ("sig",
                                     &sig),
        GNUNET_JSON_spec_varsize ("msg",
                                  (void **) &msg,
                                  &msg_size),
        GNUNET_JSON_spec_end ()
      };
      if (GNUNET_OK != GNUNET_JSON_parse (args,
                                          eddsa_verify_spec,
                                          NULL,
                                          NULL))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "malformed op args\n");
        global_ret = 1;
        return;
      }
      verify_ret = GNUNET_CRYPTO_eddsa_verify_ (
        ntohl (msg->purpose),
        msg,
        &sig,
        &pub);
      resp = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_bool ("valid",
                               GNUNET_OK == verify_ret));
      json_dumpf (resp, stdout, JSON_COMPACT);
      printf ("\n");
      fflush (stdout);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "sent response\n");
      continue;
    }
    if (0 == strcmp ("setup_refresh_planchet", op))
    {
      struct TALER_DenominationPublicKey denom_pub;
      struct TALER_Amount fee_withdraw;
      struct TALER_Amount value;
      struct TALER_ReservePublicKeyP reserve_pub;
      struct TALER_ReservePublicKeyP reserve_priv;
      uint32_t coin_index;
      json_t *resp;
      struct GNUNET_JSON_Specification eddsa_verify_spec[] = {
        TALER_JSON_spec_denom_pub ("denom_pub",
                                   &denom_pub),
        TALER_JSON_spec_amount_any ("fee_withdraw",
                                    &fee_withdraw),
        TALER_JSON_spec_amount_any ("value",
                                    &value),
        GNUNET_JSON_spec_fixed_auto ("reserve_pub",
                                     &reserve_pub),
        GNUNET_JSON_spec_fixed_auto ("reserve_priv",
                                     &reserve_priv),
        GNUNET_JSON_spec_uint32 ("coin_index",
                                 &coin_index),
        GNUNET_JSON_spec_end ()
      };
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct TALER_PlanchetSecretsP ps;

      if (GNUNET_OK !=
          GNUNET_JSON_parse (args,
                             eddsa_verify_spec,
                             NULL,
                             NULL))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "malformed op args\n");
        global_ret = 1;
        return;
      }
      TALER_planchet_setup_refresh (&transfer_secret,
                                    coin_num_salt,
                                    &ps);
      GNUNET_CRYPTO_eddsa_key_get_public (&ps.coin_priv.eddsa_priv,
                                          &coin_pub.eddsa_pub);

      resp = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("coin_priv", &ps.coin_priv),
        GNUNET_JSON_pack_data_auto ("coin_pub", &coin_pub),
        GNUNET_JSON_pack_data_auto ("blinding_key", &ps.blinding_key)
        );
      json_dumpf (resp, stdout, JSON_COMPACT);
      printf ("\n");
      fflush (stdout);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "sent response\n");
      continue;
    }
    if (0 == strcmp (op, "create_planchet"))
    {
      struct TALER_TransferSecretP transfer_secret;
      uint32_t coin_num_salt;
      struct TALER_PlanchetSecretsP ps;
      struct TALER_CoinSpendPublicKeyP coin_pub;
      json_t *resp;
      struct GNUNET_JSON_Specification eddsa_verify_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("transfer_secret",
                                     &transfer_secret),
        GNUNET_JSON_spec_uint32 ("coin_index",
                                 &coin_num_salt),
        GNUNET_JSON_spec_end ()
      };
      if (GNUNET_OK != GNUNET_JSON_parse (args,
                                          eddsa_verify_spec,
                                          NULL,
                                          NULL))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "malformed op args\n");
        global_ret = 1;
        return;
      }
      TALER_planchet_setup_refresh (&transfer_secret,
                                    coin_num_salt, &ps);
      GNUNET_CRYPTO_eddsa_key_get_public (&ps.coin_priv.eddsa_priv,
                                          &coin_pub.eddsa_pub);

      resp = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("coin_priv", &ps.coin_priv),
        GNUNET_JSON_pack_data_auto ("coin_pub", &coin_pub),
        GNUNET_JSON_pack_data_auto ("blinding_key", &ps.blinding_key)
        );
      json_dumpf (resp, stdout, JSON_COMPACT);
      printf ("\n");
      fflush (stdout);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "sent response\n");
      continue;
    }
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "unsupported operation '%s'\n",
                op);
    global_ret = 1;
    return;
  }

}


/**
 * The entry point.
 *
 * @param argc number of arguments in @a argv
 * @param argv command-line arguments
 * @return 0 on normal termination
 */
int
main (int argc,
      char **argv)
{
  struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_END
  };
  int ret;

  /* force linker to link against libtalerutil; if we do
   not do this, the linker may "optimize" libtalerutil
   away and skip #TALER_OS_init(), which we do need */
  TALER_OS_init ();
  ret = GNUNET_PROGRAM_run (argc, argv,
                            "taler-crypto-worker",
                            "Execute cryptographic operations read from stdin",
                            options,
                            &run,
                            NULL);
  if (GNUNET_NO == ret)
    return 0;
  if (GNUNET_SYSERR == ret)
    return 1;
  return global_ret;
}
