/*
  This file is part of TALER
  (C) 2014 Christian Grothoff (and other contributing authors)

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
 * @brief Check mint keys for validity.
 * @author Florian Dold
 * @author Benedikt Mueller
 */

#include <platform.h>
#include <gnunet/gnunet_util_lib.h>
#include "mint.h"
#include "taler_signatures.h"


static char *mintdir;
static struct GNUNET_CONFIGURATION_Handle *kcfg;


static int
signkeys_iter (void *cls, const struct TALER_MINT_SignKeyIssuePriv *ski)
{
  struct GNUNET_TIME_Absolute start;

  printf ("iterating over key for start time %s\n",
          GNUNET_STRINGS_absolute_time_to_string (GNUNET_TIME_absolute_ntoh (ski->issue.start)));

  start = GNUNET_TIME_absolute_ntoh (ski->issue.start);

  if (ntohl (ski->issue.purpose.size) !=
      (sizeof (struct TALER_MINT_SignKeyIssue) - offsetof (struct TALER_MINT_SignKeyIssue, purpose)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Signkey with start %s has invalid purpose field (timestamp: %llu)\n",
                GNUNET_STRINGS_absolute_time_to_string (start),
                (long long) start.abs_value_us);
    return GNUNET_SYSERR;
  }


  if (GNUNET_OK != GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_SIGNKEY,
                                               &ski->issue.purpose,
                                               &ski->issue.signature,
                                               &ski->issue.master_pub))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Signkey with start %s has invalid signature (timestamp: %llu)\n",
                GNUNET_STRINGS_absolute_time_to_string (start),
                (long long) start.abs_value_us);
    return GNUNET_SYSERR;
  }
  /* FIXME: what about private key matching the public key? */
  printf ("key valid\n");
  return GNUNET_OK;
}


static int
mint_signkeys_check ()
{
  if (0 > TALER_MINT_signkeys_iterate (mintdir, signkeys_iter, NULL))
    return GNUNET_NO;
  return GNUNET_OK;
}


static int
denomkeys_iter (void *cls,
                const char *alias,
                const struct TALER_MINT_DenomKeyIssuePriv *dki)
{
  struct GNUNET_TIME_Absolute start;

  start = GNUNET_TIME_absolute_ntoh (dki->issue.start);

  if (ntohl (dki->issue.purpose.size) !=
      (sizeof (struct TALER_MINT_DenomKeyIssuePriv) - offsetof (struct TALER_MINT_DenomKeyIssuePriv, issue.purpose)))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR, "Denomkey for '%s' with start %s has invalid purpose field (timestamp: %llu)\n",
                alias,
                GNUNET_STRINGS_absolute_time_to_string (start),
                (long long) start.abs_value_us);
    return GNUNET_SYSERR;
  }

  if (GNUNET_OK !=
      GNUNET_CRYPTO_eddsa_verify (TALER_SIGNATURE_MASTER_DENOM,
                                  &dki->issue.purpose,
                                  &dki->issue.signature,
                                  &dki->issue.master))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                "Denomkey for '%s'with start %s has invalid signature (timestamp: %llu)\n",
                alias,
                GNUNET_STRINGS_absolute_time_to_string (start),
                (long long) start.abs_value_us);
    return GNUNET_SYSERR;
  }
  printf ("denom key valid\n");

  return GNUNET_OK;
}


static int
mint_denomkeys_check ()
{
  if (0 > TALER_MINT_denomkeys_iterate (mintdir,
                                        &denomkeys_iter, NULL))
    return GNUNET_NO;
  return GNUNET_OK;
}


static int
mint_keys_check (void)
{
  if (GNUNET_OK != mint_signkeys_check ())
    return GNUNET_NO;
  return mint_denomkeys_check ();
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
    GNUNET_GETOPT_OPTION_HELP ("gnunet-mint-keyup OPTIONS"),
    {'d', "mint-dir", "DIR",
     "mint directory with keys to update", 1,
     &GNUNET_GETOPT_set_filename, &mintdir},
    GNUNET_GETOPT_OPTION_END
  };

  GNUNET_assert (GNUNET_OK == GNUNET_log_setup ("taler-mint-keycheck", "WARNING", NULL));

  if (GNUNET_GETOPT_run ("taler-mint-keyup", options, argc, argv) < 0)
    return 1;
  if (NULL == mintdir)
  {
    fprintf (stderr, "mint directory not given\n");
    return 1;
  }

  kcfg = TALER_MINT_config_load (mintdir);
  if (NULL == kcfg)
  {
    fprintf (stderr, "can't load mint configuration\n");
    return 1;
  }
  if (GNUNET_OK != mint_keys_check ())
    return 1;
  return 0;
}

