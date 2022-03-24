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
 * @file exchange-tools/taler-crypto-worker.c
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
      GNUNET_JSON_parse_free (eddsa_verify_spec);
      continue;
    }
    if (0 == strcmp ("kx_ecdhe_eddsa",
                     op))
    {
      struct GNUNET_CRYPTO_EcdhePrivateKey priv;
      struct GNUNET_CRYPTO_EddsaPublicKey pub;
      struct GNUNET_HashCode key_material;
      json_t *resp;
      struct GNUNET_JSON_Specification kx_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("eddsa_pub",
                                     &pub),
        GNUNET_JSON_spec_fixed_auto ("ecdhe_priv",
                                     &priv),
        GNUNET_JSON_spec_end ()
      };
      if (GNUNET_OK != GNUNET_JSON_parse (args,
                                          kx_spec,
                                          NULL,
                                          NULL))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "malformed op args\n");
        global_ret = 1;
        return;
      }
      if (GNUNET_OK != GNUNET_CRYPTO_ecdh_eddsa (&priv,
                                                 &pub,
                                                 &key_material))
      {
        // FIXME: Return as result?
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "kx failed\n");
        global_ret = 1;
        return;
      }
      resp = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("h",
                                    &key_material)
        );
      json_dumpf (resp, stdout, JSON_COMPACT);
      printf ("\n");
      fflush (stdout);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "sent response\n");
      GNUNET_JSON_parse_free (kx_spec);
      continue;
    }
    if (0 == strcmp ("eddsa_sign",
                     op))
    {
      struct GNUNET_CRYPTO_EddsaSignature sig;
      struct GNUNET_CRYPTO_EccSignaturePurpose *msg;
      struct GNUNET_CRYPTO_EddsaPrivateKey priv;
      size_t msg_size;
      json_t *resp;
      struct GNUNET_JSON_Specification eddsa_sign_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("priv",
                                     &priv),
        GNUNET_JSON_spec_varsize ("msg",
                                  (void **) &msg,
                                  &msg_size),
        GNUNET_JSON_spec_end ()
      };
      if (GNUNET_OK != GNUNET_JSON_parse (args,
                                          eddsa_sign_spec,
                                          NULL,
                                          NULL))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "malformed op args\n");
        global_ret = 1;
        return;
      }
      GNUNET_CRYPTO_eddsa_sign_ (
        &priv,
        msg,
        &sig
        );
      resp = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("sig", &sig)
        );
      json_dumpf (resp, stdout, JSON_COMPACT);
      printf ("\n");
      fflush (stdout);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "sent response\n");
      GNUNET_JSON_parse_free (eddsa_sign_spec);
      continue;
    }
    if (0 == strcmp ("setup_refresh_planchet", op))
    {
      struct TALER_TransferSecretP transfer_secret;
      uint32_t coin_index;
      json_t *resp;
      struct GNUNET_JSON_Specification setup_refresh_planchet_spec[] = {
        GNUNET_JSON_spec_uint32 ("coin_index",
                                 &coin_index),
        GNUNET_JSON_spec_fixed_auto ("transfer_secret",
                                     &transfer_secret),
        GNUNET_JSON_spec_end ()
      };
      struct TALER_CoinSpendPublicKeyP coin_pub;
      struct TALER_CoinSpendPrivateKeyP coin_priv;
      struct TALER_PlanchetMasterSecretP ps;
      struct TALER_ExchangeWithdrawValues alg_values = {
        // FIXME: also allow CS
        .cipher = TALER_DENOMINATION_RSA,
      };
      union TALER_DenominationBlindingKeyP dbk;

      if (GNUNET_OK !=
          GNUNET_JSON_parse (args,
                             setup_refresh_planchet_spec,
                             NULL,
                             NULL))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "malformed op args\n");
        global_ret = 1;
        return;
      }
      TALER_transfer_secret_to_planchet_secret (&transfer_secret,
                                                coin_index,
                                                &ps);
      TALER_planchet_setup_coin_priv (&ps,
                                      &alg_values,
                                      &coin_priv);
      GNUNET_CRYPTO_eddsa_key_get_public (&coin_priv.eddsa_priv,
                                          &coin_pub.eddsa_pub);
      TALER_planchet_blinding_secret_create (&ps,
                                             &alg_values,
                                             &dbk);

      resp = GNUNET_JSON_PACK (
        GNUNET_JSON_pack_data_auto ("coin_priv", &coin_priv),
        GNUNET_JSON_pack_data_auto ("coin_pub", &coin_pub),
        GNUNET_JSON_pack_data_auto ("blinding_key", &dbk.rsa_bks)
        );
      json_dumpf (resp, stdout, JSON_COMPACT);
      printf ("\n");
      fflush (stdout);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "sent response\n");
      GNUNET_JSON_parse_free (setup_refresh_planchet_spec);
      continue;
    }
    if (0 == strcmp ("rsa_blind", op))
    {
      struct GNUNET_HashCode hm;
      struct GNUNET_CRYPTO_RsaBlindingKeySecret bks;
      void *pub_enc;
      size_t pub_enc_size;
      int success;
      struct GNUNET_CRYPTO_RsaPublicKey *pub;
      void *blinded_buf;
      size_t blinded_size;
      json_t *resp;
      struct GNUNET_JSON_Specification rsa_blind_spec[] = {
        GNUNET_JSON_spec_fixed_auto ("hm",
                                     &hm),
        GNUNET_JSON_spec_fixed_auto ("bks",
                                     &bks),
        GNUNET_JSON_spec_varsize ("pub",
                                  &pub_enc,
                                  &pub_enc_size),
        GNUNET_JSON_spec_end ()
      };
      if (GNUNET_OK !=
          GNUNET_JSON_parse (args,
                             rsa_blind_spec,
                             NULL,
                             NULL))
      {
        GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                    "malformed op args\n");
        global_ret = 1;
        return;
      }
      pub = GNUNET_CRYPTO_rsa_public_key_decode (pub_enc,
                                                 pub_enc_size);
      success = GNUNET_CRYPTO_rsa_blind (&hm,
                                         &bks,
                                         pub,
                                         &blinded_buf,
                                         &blinded_size);

      if (GNUNET_YES == success)
      {
        resp = GNUNET_JSON_PACK (
          GNUNET_JSON_pack_data_varsize ("blinded", blinded_buf, blinded_size),
          GNUNET_JSON_pack_bool ("success", true)
          );
      }
      else
      {
        resp = GNUNET_JSON_PACK (
          GNUNET_JSON_pack_bool ("success", false)
          );
      }
      json_dumpf (resp, stdout, JSON_COMPACT);
      printf ("\n");
      fflush (stdout);
      GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                  "sent response\n");
      GNUNET_JSON_parse_free (rsa_blind_spec);
      GNUNET_free (blinded_buf);
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
