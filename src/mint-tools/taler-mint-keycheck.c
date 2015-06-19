/*
  This file is part of TALER
  Copyright (C) 2014, 2015 Christian Grothoff (and other contributing authors)

  TALER is free software; you can redistribute it and/or modify it under the
  terms of the GNU General Public License as published by the Free Software
  Foundation; either version 3, or (at your option) any later version.

  TALER is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
  A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along with
  TALER; see the file COPYING.  If not, If not, see <http://www.gnu.org/licenses/>
*/
/**
 * @file taler-mint-keycheck.c
 * @brief Check mint keys for validity.  Reads the signing and denomination
 *        keys from the mint directory and checks to make sure they are
 *        well-formed.  This is purely a diagnostic tool.
 * @author Florian Dold
 * @author Benedikt Mueller
 * @author Christian Grothoff
 */
#include <platform.h>
#include <gnunet/gnunet_util_lib.h>
#include "taler_mintdb_lib.h"

/**
 * Mint directory with the keys.
 */
static char *mint_directory;

/**
 * Our configuration.
 */
static struct GNUNET_CONFIGURATION_Handle *kcfg;


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
               const struct TALER_MINTDB_PrivateSigningKeyInformationP *ski)
{
  GNUNET_log (GNUNET_ERROR_TYPE_DEBUG,
              "Iterating over key `%s' for start time %s\n",
              filename,
              GNUNET_STRINGS_absolute_time_to_string
              (GNUNET_TIME_absolute_ntoh (ski->issue.start)));

  if (ntohl (ski->issue.purpose.size) !=
      (sizeof (struct TALER_MintSigningKeyValidityPS) -
       offsetof (struct TALER_MintSigningKeyValidityPS,
                 purpose)))
  {
    fprintf (stderr,
             "Signing key `%s' has invalid purpose size\n",
             filename);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_SIGNING_KEY_VALIDITY,
                                  &ski->issue.purpose,
                                  &ski->issue.signature.eddsa_signature,
                                  &ski->issue.master_public_key.eddsa_pub))
  {
    fprintf (stderr,
             "Signing key `%s' has invalid signature\n",
             filename);
    return GNUNET_SYSERR;
  }
  printf ("Signing key `%s' valid\n",
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
mint_signkeys_check ()
{
  if (0 > TALER_MINTDB_signing_keys_iterate (mint_directory,
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
                const struct TALER_MINTDB_DenominationKeyIssueInformation *dki)
{
  struct GNUNET_HashCode hc;

  if (ntohl (dki->issue.purpose.size) !=
      sizeof (struct TALER_DenominationKeyValidityPS) -
      offsetof (struct TALER_DenominationKeyValidityPS,
                purpose))
  {
    fprintf (stderr,
             "Denomination key for `%s' has invalid purpose size\n",
             alias);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_DENOMINATION_KEY_VALIDITY,
                                  &dki->issue.purpose,
                                  &dki->issue.signature.eddsa_signature,
                                  &dki->issue.master.eddsa_pub))
  {
    fprintf (stderr,
             "Denomination key for `%s' has invalid signature\n",
             alias);
    return GNUNET_SYSERR;
  }
  GNUNET_CRYPTO_rsa_public_key_hash (dki->denom_pub.rsa_public_key,
                                     &hc);
  if (0 != memcmp (&hc,
                   &dki->issue.denom_hash,
                   sizeof (struct GNUNET_HashCode)))
  {
    fprintf (stderr,
             "Public key for `%s' does not match signature\n",
             alias);
    return GNUNET_SYSERR;
  }
  printf ("Denomination key `%s' is valid\n",
          alias);

  return GNUNET_OK;
}


/**
 * Check denomination keys.
 *
 * @return #GNUNET_OK if the keys are OK
 *         #GNUNET_NO if not
 */
static int
mint_denomkeys_check ()
{
  if (0 > TALER_MINTDB_denomination_keys_iterate (mint_directory,
                                        &denomkeys_iter,
                                        NULL))
    return GNUNET_NO;
  return GNUNET_OK;
}


/**
 * The main function of the keyup tool
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc, char *const *argv)
{
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_HELP ("gnunet-mint-keycheck OPTIONS"),
    {'d', "directory", "DIRECTORY",
     "mint directory with keys to check", 1,
     &GNUNET_GETOPT_set_filename, &mint_directory},
    GNUNET_GETOPT_OPTION_END
  };

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-mint-keycheck",
                                   "WARNING",
                                   NULL));

  if (GNUNET_GETOPT_run ("taler-mint-keycheck",
                         options,
                         argc, argv) < 0)
    return 1;
  if (NULL == mint_directory)
  {
    fprintf (stderr,
             "Mint directory not given\n");
    return 1;
  }

  kcfg = TALER_config_load (mint_directory);
  if (NULL == kcfg)
  {
    fprintf (stderr,
             "Failed to load mint configuration\n");
    return 1;
  }
  if ( (GNUNET_OK != mint_signkeys_check ()) ||
       (GNUNET_OK != mint_denomkeys_check ()) )
  {
    GNUNET_CONFIGURATION_destroy (kcfg);
    return 1;
  }
  GNUNET_CONFIGURATION_destroy (kcfg);
  return 0;
}

/* end of taler-mint-keycheck.c */
