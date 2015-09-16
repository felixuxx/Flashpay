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
 * @file taler-auditor-sign.c
 * @brief Tool used by the auditor to sign the mint's master key and the
 *        denomination key(s).
 * @author Christian Grothoff
 */
#include <platform.h>
#include "taler_mintdb_lib.h"


/**
 * Are we running in verbose mode?
 */
static int verbose;

/**
 * Filename of the auditor's private key.
 */
static char *auditor_key_file;

/**
 * Mint's public key (in Crockford base32 encoding).
 */
static char *mint_public_key;

/**
 * File with the Mint's denomination keys to sign, itself
 * signed by the Mint's public key.
 */
static char *mint_request_file;

/**
 * Where should we write the auditor's signature?
 */
static char *output_file;

/**
 * Handle to the auditor's configuration
 */
static struct GNUNET_CONFIGURATION_Handle *kcfg;

/**
 * Master public key of the mint.
 */
static struct TALER_MasterPublicKeyP master_public_key;


/**
 * Print denomination key details for diagnostics.
 *
 * @param dk denomination key to print
 */
static void
print_dk (const struct TALER_DenominationKeyValidityPS *dk)
{
  struct TALER_Amount a;
  char *s;

  fprintf (stdout,
           "Denomination key hash: %s\n",
           GNUNET_h2s_full (&dk->denom_hash));
  TALER_amount_ntoh (&a,
                     &dk->value);
  fprintf (stdout,
           "Value: %s\n",
           s = TALER_amount_to_string (&a));
  GNUNET_free (s);
    TALER_amount_ntoh (&a,
                       &dk->fee_withdraw);
  fprintf (stdout,
           "Withdraw fee: %s\n",
           s = TALER_amount_to_string (&a));
  GNUNET_free (s);
    TALER_amount_ntoh (&a,
                       &dk->fee_deposit);
  fprintf (stdout,
           "Deposit fee: %s\n",
           s = TALER_amount_to_string (&a));
  GNUNET_free (s);
  TALER_amount_ntoh (&a,
                     &dk->fee_refresh);
  fprintf (stdout,
           "Refresh fee: %s\n",
           s = TALER_amount_to_string (&a));
  GNUNET_free (s);

  fprintf (stdout,
           "Validity start time: %s\n",
           GNUNET_TIME_absolute_to_string (GNUNET_TIME_absolute_ntoh (dk->start)));
  fprintf (stdout,
           "Withdraw end time: %s\n",
           GNUNET_TIME_absolute_to_string (GNUNET_TIME_absolute_ntoh (dk->expire_withdraw)));
  fprintf (stdout,
           "Deposit end time: %s\n",
           GNUNET_TIME_absolute_to_string (GNUNET_TIME_absolute_ntoh (dk->expire_spend)));
  fprintf (stdout,
           "Legal dispute end time: %s\n",
           GNUNET_TIME_absolute_to_string (GNUNET_TIME_absolute_ntoh (dk->expire_legal)));

  fprintf (stdout,
           "\n");
}


/**
 * The main function of the taler-auditor-sign tool.  This tool is used
 * to sign a mint's master and denomination keys, affirming that the
 * auditor is aware of them and will validate the mint's database with
 * respect to these keys.
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
    {'a', "auditor-key", "FILE",
     "file containing the private key of the auditor", 1,
     &GNUNET_GETOPT_set_filename, &auditor_key_file},
    TALER_GETOPT_OPTION_HELP ("Private key of the auditor to use for signing"),
    {'m', "mint-key", "KEY",
     "public key of the mint (Crockford base32 encoded)", 1,
     &GNUNET_GETOPT_set_filename, &mint_public_key},
    {'r', "mint-request", "FILE",
     "set of keys the mint requested the auditor to sign", 1,
     &GNUNET_GETOPT_set_string, &mint_request_file},
    {'o', "output", "FILE",
     "where to write our signature", 1,
     &GNUNET_GETOPT_set_string, &output_file},
    GNUNET_GETOPT_OPTION_VERSION (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_VERBOSE (&verbose),
    GNUNET_GETOPT_OPTION_END
  };
  struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_priv;
  struct TALER_AuditorSignatureP sig;
  struct GNUNET_DISK_FileHandle *fh;
  struct GNUNET_DISK_FileHandle *fout;
  struct TALER_DenominationKeyValidityPS *dks;
  struct TALER_MintKeyValidityPS *ap;
  off_t in_size;
  unsigned int i;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-mint-keyup",
                                   "WARNING",
                                   NULL));
  if (GNUNET_GETOPT_run ("taler-mint-keyup",
                         options,
                         argc, argv) < 0)
    return 1;
  if (NULL == auditor_key_file)
  {
    fprintf (stderr,
             "Auditor key file not given\n");
    return 1;
  }
  eddsa_priv = GNUNET_CRYPTO_eddsa_key_create_from_file (auditor_key_file);
  if (NULL == eddsa_priv)
  {
    fprintf (stderr,
             "Failed to initialize auditor key from file `%s'\n",
             auditor_key_file);
    return 1;
  }
  if (NULL == mint_public_key)
  {
    fprintf (stderr,
             "Mint public key not given\n");
    return 1;
  }
  if (GNUNET_OK !=
      GNUNET_STRINGS_string_to_data (mint_public_key,
                                     strlen (mint_public_key),
                                     &master_public_key,
                                     sizeof (master_public_key)))
  {
    fprintf (stderr,
             "Public key `%s' malformed\n",
             mint_public_key);
    return 1;
  }
  if (NULL == mint_request_file)
  {
    fprintf (stderr,
             "Mint signing request not given\n");
    return 1;
  }
  fh = GNUNET_DISK_file_open (mint_request_file,
                              GNUNET_DISK_OPEN_READ,
                              GNUNET_DISK_PERM_NONE);
  if (NULL == fh)
  {
    fprintf (stderr,
             "Failed to open file `%s': %s\n",
             mint_request_file,
             STRERROR (errno));
    return 1;
  }
  if (GNUNET_OK !=
      GNUNET_DISK_file_handle_size (fh,
                                    &in_size))
  {
    fprintf (stderr,
             "Failed to obtain input file size `%s': %s\n",
             mint_request_file,
             STRERROR (errno));
    GNUNET_DISK_file_close (fh);
    return 1;
  }
  if (0 != (in_size % sizeof (struct TALER_DenominationKeyValidityPS)))
  {
    fprintf (stderr,
             "Input file size of file `%s' is invalid\n",
             mint_request_file);
    GNUNET_DISK_file_close (fh);
    return 1;
  }
  ap = GNUNET_malloc (sizeof (struct TALER_MintKeyValidityPS) +
                      in_size);
  ap.purpose.purpose = htonl (TALER_SIGNATURE_AUDITOR_MINT_KEYS);
  ap.purpose.size = htonl (sizeof (struct TALER_MintKeyValidityPS) +
                           in_size);
  ap.master = master_public_key;
  dks = (struct TALER_DenominationKeyValidityPS *) &ap[1];
  if (in_size !=
      GNUNET_DISK_file_read (fh,
                             dks,
                             in_size))
  {
    fprintf (stderr,
             "Failed to read input file `%s': %s\n",
             mint_request_file,
             STRERROR (errno));
    GNUNET_DISK_file_close (fh);
    GNUNET_free (ap);
    return 1;
  }
  GNUNET_DISK_file_close (fh);
  if (verbose)
  {
    for (i=0;i<in_size / sizeof (struct TALER_DenominationKeyValidityPS);i++)
      print_dk (&dks[i]);
  }

  if (NULL == output_file)
  {
    fprintf (stderr,
             "Output file not given\n");
    GNUNET_free (ap);
    return 1;
  }
  fout = GNUNET_DISK_file_open (output_file,
                                GNUNET_DISK_OPEN_READ |
                                GNUNET_DISK_OPEN_TRUNCATE |
                                GNUNET_DISK_OPEN_CREATE,
                                GNUNET_DISK_PERM_USER_READ |
                                GNUNET_DISK_PERM_USER_WRITE |
                                GNUNET_DISK_PERM_GROUP_READ |
                                GNUNET_DISK_PERM_OTHER_READ);
  if (NULL == fout)
  {
    fprintf (stderr,
             "Failed to open file `%s': %s\n",
             output_file,
             STRERROR (errno));
    GNUNET_free (ap);
    return 1;
  }

  /* Finally sign ... */
  GNUNET_CRYPTO_eddsa_sign (eddsa_priv,
                            &ap->purpose,
                            &sig.eddsa_sig);
  if (sizeof (struct TALER_AuditorSignatureP) !=
      GNUNET_DISK_file_write (out,
                              &sig,
                              sizeof (sig)))
  {
    fprintf (stderr,
             "Failed to write to file `%s': %s\n",
             output_file,
             STRERROR (errno));
    GNUNET_free (ap);
    GNUNET_DISK_file_close (output_file);
    return 1;
  }
  GNUNET_free (ap);
  GNUNET_DISK_file_close (out);
  GNUNET_free (eddsa_priv);
  return 0;
}

/* end of taler-auditor-sign.c */
