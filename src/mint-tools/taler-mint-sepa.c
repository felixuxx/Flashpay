/*
  This file is part of TALER
  Copyright (C) 2015 Christian Grothoff (and other contributing authors)

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
 * @file taler-mint-sepa.c
 * @brief Create signed response for /wire/sepa requests.
 * @author Christian Grothoff
 */
#include <platform.h>
#include "taler_crypto_lib.h"

/**
 * Filename of the master private key.
 */
static char *masterkeyfile;

/**
 * Account holder name.
 */
static char *sepa_name;

/**
 * IBAN number.
 */
static char *iban;

/**
 * BIC number.
 */
static char *bic;

/**
 * Where to write the result.
 */
static char *output_filename;


/**
 * The main function of the taler-mint-sepa tool.  This tool is used
 * to sign the SEPA bank account details using the master key.
 *
 * @param argc number of arguments from the command line
 * @param argv command line arguments
 * @return 0 ok, 1 on error
 */
int
main (int argc,
      char *const *argv)
{
  static const struct GNUNET_GETOPT_CommandLineOption options[] = {
    {'b', "bic", "BICCODE",
     "bank BIC code", 1,
     &GNUNET_GETOPT_set_string, &bic},
    {'i', "iban", "IBAN",
     "IBAN number of the account", 1,
     &GNUNET_GETOPT_set_string, &iban},
    {'m', "master-key", "FILE",
     "master key file (private key)", 1,
     &GNUNET_GETOPT_set_filename, &masterkeyfile},
    {'n', "name", "NAME",
     "name of the account holder", 1,
     &GNUNET_GETOPT_set_string, &sepa_name},
    {'o', "output", "FILE",
     "where to write the result", 1,
     &GNUNET_GETOPT_set_filename, &output_filename},
    GNUNET_GETOPT_OPTION_VERSION (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_priv;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-mint-sepa",
                                   "WARNING",
                                   NULL));

  if (GNUNET_GETOPT_run ("taler-mint-sepa",
                         options,
                         argc, argv) < 0)
    return 1;
  if (NULL == masterkeyfile)
  {
    fprintf (stderr,
             "Master key file not given\n");
    return 1;
  }
  eddsa_priv = GNUNET_CRYPTO_eddsa_key_create_from_file (masterkeyfile);
  if (NULL == eddsa_priv)
  {
    fprintf (stderr,
             "Failed to initialize master key from file `%s'\n",
             masterkeyfile);
    return 1;
  }
  /* FIXME: do real work! */
  GNUNET_free (eddsa_priv);
  return 0;
}

/* end of taler-mint-sepa.c */
