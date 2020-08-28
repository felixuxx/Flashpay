/*
  This file is part of TALER
  Copyright (C) 2015-2020 Taler Systems SA

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
 * @file key-helper.c
 * @brief shared logic between tools that deal with the master private key
 * @author Christian Grothoff
 */

/**
 * Extract the @a master_priv from the @a cfg or @a masterkeyfile and
 * verify that it matches the master public key given in @a cfg.
 *
 * @param cfg configuration to use
 * @param masterkeyfile master private key filename, can be NULL to use from @a cfg
 * @param[out] master_priv where to store the master private key on success
 * @return #GNUNET_OK on success, #GNUNET_SYSERR on failures
 */
static int
get_and_check_master_key (const struct GNUNET_CONFIGURATION_Handle *cfg,
                          const char *masterkeyfile,
                          struct TALER_MasterPrivateKeyP *master_priv)
{
  struct GNUNET_CRYPTO_EddsaPublicKey mpub;
  struct GNUNET_CRYPTO_EddsaPublicKey mpub_cfg;
  char *fn;

  if (NULL != masterkeyfile)
  {
    fn = GNUNET_strdup (masterkeyfile);
  }
  else
  {
    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                 "exchange",
                                                 "MASTER_PRIV_FILE",
                                                 &fn))
    {
      fprintf (stderr,
               "Master private key file given neither in configuration nor on command-line\n");
      return GNUNET_SYSERR;
    }
  }
  if (GNUNET_YES !=
      GNUNET_DISK_file_test (fn))
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Exchange master private key `%s' does not exist yet, creating it!\n",
                fn);
  {
    int ret;

    ret = GNUNET_CRYPTO_eddsa_key_from_file (fn,
                                             GNUNET_YES,
                                             &master_priv->eddsa_priv);
    if (GNUNET_OK != ret)
    {
      fprintf (stderr,
               "Failed to initialize master key from file `%s': %s\n",
               fn,
               (GNUNET_NO == ret)
               ? "file exists"
               : "could not create file");
      GNUNET_free (fn);
      return GNUNET_SYSERR;
    }
    GNUNET_CRYPTO_eddsa_key_get_public (&master_priv->eddsa_priv,
                                        &mpub);
  }

  /* Check our key matches that in the configuration */
  {
    char *masters;

    if (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "exchange",
                                               "MASTER_PUBLIC_KEY",
                                               &masters))
    {
      /* Help user by telling them precisely what to fix */
      masters = GNUNET_STRINGS_data_to_string_alloc (&mpub,
                                                     sizeof (mpub));
      fprintf (stderr,
               "You must set MASTER_PUBLIC_KEY to `%s' in the [exchange] section of the configuration before proceeding.\n",
               masters);
      GNUNET_free (masters);
      GNUNET_free (fn);
      return GNUNET_SYSERR;
    }
    if (GNUNET_OK !=
        GNUNET_STRINGS_string_to_data (masters,
                                       strlen (masters),
                                       &mpub_cfg,
                                       sizeof (mpub_cfg)))
    {
      fprintf (stderr,
               "MASTER_PUBLIC_KEY value `%s' specified in section [exchange] of the configuration is a valid public key\n",
               masters);
      GNUNET_free (masters);
      GNUNET_free (fn);
      return GNUNET_SYSERR;
    }
    if (0 != GNUNET_memcmp (&mpub,
                            &mpub_cfg))
    {
      fprintf (stderr,
               "MASTER_PUBLIC_KEY value `%s' specified in section [exchange] of the configuration does not match our master private key. You can use `gnunet-ecc -p \"%s\"' to determine the correct value.\n",
               masters,
               fn);
      GNUNET_free (masters);
      GNUNET_free (fn);
      return GNUNET_SYSERR;
    }
    GNUNET_free (masters);
  }
  GNUNET_free (fn);

  return GNUNET_OK;
}
