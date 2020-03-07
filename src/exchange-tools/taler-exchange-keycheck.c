/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2016 Taler Systems SA

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
 * @file taler-exchange-keycheck.c
 * @brief Check exchange keys for validity.  Reads the signing and denomination
 *        keys from the exchange directory and checks to make sure they are
 *        well-formed.  This is purely a diagnostic tool.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include <platform.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_exchangedb_lib.h"

/**
 * Exchange directory with the keys.
 */
static char *exchange_directory;

/**
 * Our configuration.
 */
static const struct GNUNET_CONFIGURATION_Handle *kcfg;

/**
 * Return value from main().
 */
static int global_ret;


/**
 * Function called on each signing key.
 *
 * @param cls closure (NULL)
 * @param filename name of the file the key came from
 * @param ski the sign key
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
signkeys_iter (void *cls,
               const char *filename,
               const struct TALER_EXCHANGEDB_PrivateSigningKeyInformationP *ski)
{
  (void) cls;
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Iterating over key `%s' for start time %s\n",
              filename,
              GNUNET_STRINGS_absolute_time_to_string
                (GNUNET_TIME_absolute_ntoh (ski->issue.start)));

  if (ntohl (ski->issue.purpose.size) !=
      (sizeof (struct TALER_ExchangeSigningKeyValidityPS)))
  {
    fprintf (stderr,
             "Signing key `%s' has invalid purpose size\n",
             filename);
    return GNUNET_SYSERR;
  }
  if ( (0 != GNUNET_TIME_absolute_ntoh (ski->issue.start).abs_value_us
        % 1000000) ||
       (0 != GNUNET_TIME_absolute_ntoh (ski->issue.expire).abs_value_us
        % 1000000) ||
       (0 != GNUNET_TIME_absolute_ntoh (ski->issue.end).abs_value_us
        % 1000000) )
  {
    fprintf (stderr,
             "Timestamps are not multiples of a round second\n");
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY,
                                  &ski->issue.purpose,
                                  &ski->master_sig.eddsa_signature,
                                  &ski->issue.master_public_key.eddsa_pub))
  {
    fprintf (stderr,
             "Signing key `%s' has invalid signature\n",
             filename);
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Signing key `%s' valid\n",
              filename);
  return GNUNET_OK;
}


/**
 * Check signing keys.
 *
 * @return #GNUNET_OK if the keys are OK
 *         #GNUNET_NO if not
 */
static int
exchange_signkeys_check ()
{
  if (0 > TALER_EXCHANGEDB_signing_keys_iterate (exchange_directory,
                                                 &signkeys_iter,
                                                 NULL))
    return GNUNET_NO;
  return GNUNET_OK;
}


/**
 * Function called on each denomination key.
 *
 * @param cls closure (NULL)
 * @param dki the denomination key
 * @param alias coin alias
 * @return #GNUNET_OK to continue to iterate,
 *  #GNUNET_NO to stop iteration with no error,
 *  #GNUNET_SYSERR to abort iteration with error!
 */
static int
denomkeys_iter (void *cls,
                const char *alias,
                const struct
                TALER_EXCHANGEDB_DenominationKey *dki)
{
  struct GNUNET_HashCode hc;

  (void) cls;
  if (ntohl (dki->issue.properties.purpose.size) !=
      sizeof (struct TALER_DenominationKeyValidityPS))
  {
    fprintf (stderr,
             "Denomination key for `%s' has invalid purpose size\n",
             alias);
    return GNUNET_SYSERR;
  }

  if ( (0 != GNUNET_TIME_absolute_ntoh (
          dki->issue.properties.start).abs_value_us % 1000000) ||
       (0 != GNUNET_TIME_absolute_ntoh (
          dki->issue.properties.expire_withdraw).abs_value_us % 1000000) ||
       (0 != GNUNET_TIME_absolute_ntoh (
          dki->issue.properties.expire_legal).abs_value_us % 1000000) ||
       (0 != GNUNET_TIME_absolute_ntoh (
          dki->issue.properties.expire_deposit).abs_value_us % 1000000) )
  {
    fprintf (stderr,
             "Timestamps are not multiples of a round second\n");
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (
        TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY,
        &dki->issue.properties.purpose,
        &dki->issue.signature.eddsa_signature,
        &dki->issue.properties.master.eddsa_pub))
  {
    fprintf (stderr,
             "Denomination key for `%s' has invalid signature\n",
             alias);
    return GNUNET_SYSERR;
  }
  GNUNET_CRYPTO_rsa_public_key_hash (dki->denom_pub.rsa_public_key,
                                     &hc);
  if (0 != GNUNET_memcmp (&hc,
                          &dki->issue.properties.denom_hash))
  {
    fprintf (stderr,
             "Public key for `%s' does not match signature\n",
             alias);
    return GNUNET_SYSERR;
  }
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Denomination key `%s' (%s) is valid\n",
              alias,
              GNUNET_h2s (&hc));
  return GNUNET_OK;
}


/**
 * Check denomination keys.
 *
 * @return #GNUNET_OK if the keys are OK
 *         #GNUNET_NO if not
 */
static int
exchange_denomkeys_check ()
{
  struct TALER_MasterPublicKeyP master_public_key_from_cfg;

  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_data (kcfg,
                                     "exchange",
                                     "master_public_key",
                                     &master_public_key_from_cfg,
                                     sizeof (struct
                                             GNUNET_CRYPTO_EddsaPublicKey)))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "master_public_key");
    return GNUNET_NO;
  }
  if (0 > TALER_EXCHANGEDB_denomination_keys_iterate (exchange_directory,
                                                      &denomkeys_iter,
                                                      NULL))
    return GNUNET_NO;
  return GNUNET_OK;
}


/**
 * Main function that will be run.
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
  kcfg = cfg;
  if (GNUNET_OK !=
      GNUNET_CONFIGURATION_get_value_filename (kcfg,
                                               "exchange",
                                               "KEYDIR",
                                               &exchange_directory))
  {
    GNUNET_log_config_missing (GNUNET_ERROR_TYPE_ERROR,
                               "exchange",
                               "KEYDIR");
    global_ret = 1;
    return;
  }

  if ( (GNUNET_OK != exchange_signkeys_check ()) ||
       (GNUNET_OK != exchange_denomkeys_check ()) )
  {
    global_ret = 1;
    return;
  }
}


/**
 * The main function of the keyup tool
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_END
  };

  /* force linker to link against libtalerutil; if we do
    not do this, the linker may "optimize" libtalerutil
    away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-exchange-keycheck",
                                   "WARNING",
                                   NULL));
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
                          "taler-exchange-keycheck",
                          "Check keys of the exchange for validity",
                          options,
                          &run, NULL))
    return 1;
  return global_ret;

}


/* end of taler-exchange-keycheck.c */
