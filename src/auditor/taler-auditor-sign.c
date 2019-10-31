/*
  This file is part of TALER
  Copyright (C) 2014, 2015, 2018 GNUnet e.V.

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
 * @file taler-auditor-sign.c
 * @brief Tool used by the auditor to sign the exchange's master key and the
 *        denomination key(s).
 * @author Christian Grothoff
 */
#include <platform.h>
#include "taler_exchangedb_lib.h"
#include "taler_auditordb_lib.h"


/**
 * Are we running in verbose mode?
 */
static unsigned int verbose;

/**
 * Filename of the auditor's private key.
 */
static char *auditor_key_file;

/**
 * File with the Exchange's denomination keys to sign, itself
 * signed by the Exchange's public key.
 */
static char *exchange_request_file;

/**
 * Where should we write the auditor's signature?
 */
static char *output_file;

/**
 * URL of the auditor (informative for the user).
 */
static char *auditor_url;

/**
 * Master public key of the exchange.
 */
static struct TALER_MasterPublicKeyP master_public_key;

/**
 * Our configuration.
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;

/**
 * Handle to access the auditor's database.
 */
static struct TALER_AUDITORDB_Plugin *adb;


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
  TALER_amount_ntoh (&a,
                     &dk->fee_refund);
  fprintf (stdout,
           "Refund fee: %s\n",
           s = TALER_amount_to_string (&a));
  GNUNET_free (s);

  fprintf (stdout,
           "Validity start time: %s\n",
           GNUNET_STRINGS_absolute_time_to_string (GNUNET_TIME_absolute_ntoh (
                                                     dk->start)));
  fprintf (stdout,
           "Withdraw end time: %s\n",
           GNUNET_STRINGS_absolute_time_to_string (GNUNET_TIME_absolute_ntoh (
                                                     dk->expire_withdraw)));
  fprintf (stdout,
           "Deposit end time: %s\n",
           GNUNET_STRINGS_absolute_time_to_string (GNUNET_TIME_absolute_ntoh (
                                                     dk->expire_deposit)));
  fprintf (stdout,
           "Legal dispute end time: %s\n",
           GNUNET_STRINGS_absolute_time_to_string (GNUNET_TIME_absolute_ntoh (
                                                     dk->expire_legal)));

  fprintf (stdout,
           "\n");
}


/**
 * The main function of the taler-auditor-sign tool.  This tool is used
 * to sign a exchange's master and denomination keys, affirming that the
 * auditor is aware of them and will validate the exchange's database with
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
  char *cfgfile = NULL;
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_option_filename ('a',
                                   "auditor-key",
                                   "FILENAME",
                                   "file containing the private key of the auditor",
                                   &auditor_key_file),
    GNUNET_GETOPT_option_cfgfile (&cfgfile),
    GNUNET_GETOPT_option_help ("Sign denomination keys of an exchange"),
    GNUNET_GETOPT_option_mandatory
      (GNUNET_GETOPT_option_base32_auto ('m',
                                         "exchange-key",
                                         "KEY",
                                         "public key of the exchange (Crockford base32 encoded)",
                                         &master_public_key)),
    GNUNET_GETOPT_option_string ('u',
                                 "auditor-url",
                                 "URL",
                                 "URL of the auditor (informative link for the user)",
                                 &auditor_url),
    GNUNET_GETOPT_option_mandatory
      (GNUNET_GETOPT_option_filename ('r',
                                      "exchange-request",
                                      "FILENAME",
                                      "set of keys the exchange requested the auditor to sign",
                                      &exchange_request_file)),
    GNUNET_GETOPT_option_filename ('o',
                                   "output",
                                   "FILENAME",
                                   "where to write our signature",
                                   &output_file),
    GNUNET_GETOPT_option_version (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_option_verbose (&verbose),
    GNUNET_GETOPT_OPTION_END
  };
  struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_priv;
  struct TALER_AuditorSignatureP *sigs;
  struct TALER_AuditorPublicKeyP apub;
  struct GNUNET_DISK_FileHandle *fh;
  struct TALER_DenominationKeyValidityPS *dks;
  unsigned int dks_len;
  struct TALER_ExchangeKeyValidityPS kv;
  off_t in_size;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-auditor-sign",
                                   "WARNING",
                                   NULL));
  if (GNUNET_GETOPT_run ("taler-auditor-sign",
                         options,
                         argc, argv) <= 0)
    return 1;
  if (NULL == cfgfile)
    cfgfile = GNUNET_strdup (GNUNET_OS_project_data_get ()->user_config_file);
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_SYSERR ==
      GNUNET_CONFIGURATION_load (cfg,
                                 cfgfile))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                _ ("Malformed configuration file `%s', exit ...\n"),
                cfgfile);
    GNUNET_free_non_null (cfgfile);
    return 1;
  }
  GNUNET_free_non_null (cfgfile);
  if ( (NULL == auditor_key_file) &&
       (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                 "auditor",
                                                 "AUDITOR_PRIV_FILE",
                                                 &auditor_key_file)) )
  {
    fprintf (stderr,
             "Auditor key file not given in neither configuration nor command-line\n");
    return 1;
  }
  if ( (NULL == auditor_url) &&
       (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_string (cfg,
                                               "auditor",
                                               "AUDITOR_URL",
                                               &auditor_url)) )
  {
    fprintf (stderr,
             "Auditor URL not given in neither configuration nor command-line\n");
    return 1;
  }
  if (GNUNET_YES !=
      GNUNET_DISK_file_test (auditor_key_file))
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Auditor private key `%s' does not exist yet, creating it!\n",
                auditor_key_file);
  eddsa_priv = GNUNET_CRYPTO_eddsa_key_create_from_file (auditor_key_file);
  if (NULL == eddsa_priv)
  {
    fprintf (stderr,
             "Failed to initialize auditor key from file `%s'\n",
             auditor_key_file);
    return 1;
  }
  GNUNET_CRYPTO_eddsa_key_get_public (eddsa_priv,
                                      &apub.eddsa_pub);
  fh = GNUNET_DISK_file_open (exchange_request_file,
                              GNUNET_DISK_OPEN_READ,
                              GNUNET_DISK_PERM_NONE);
  if (NULL == fh)
  {
    fprintf (stderr,
             "Failed to open file `%s': %s\n",
             exchange_request_file,
             strerror (errno));
    GNUNET_free (eddsa_priv);
    return 1;
  }
  if (GNUNET_OK !=
      GNUNET_DISK_file_handle_size (fh,
                                    &in_size))
  {
    fprintf (stderr,
             "Failed to obtain input file size `%s': %s\n",
             exchange_request_file,
             strerror (errno));
    GNUNET_DISK_file_close (fh);
    GNUNET_free (eddsa_priv);
    return 1;
  }
  if (0 != (in_size % sizeof (struct TALER_DenominationKeyValidityPS)))
  {
    fprintf (stderr,
             "Input file size of file `%s' is invalid\n",
             exchange_request_file);
    GNUNET_DISK_file_close (fh);
    GNUNET_free (eddsa_priv);
    return 1;
  }
  dks_len = in_size / sizeof (struct TALER_DenominationKeyValidityPS);
  if (0 == dks_len)
  {
    fprintf (stderr,
             "Failed to produce auditor signature, denomination list is empty.\n");
    GNUNET_DISK_file_close (fh);
    GNUNET_free (eddsa_priv);
    return 2;
  }
  if (NULL ==
      (adb = TALER_AUDITORDB_plugin_load (cfg)))
  {
    fprintf (stderr,
             "Failed to initialize auditor database plugin.\n");
    GNUNET_DISK_file_close (fh);
    GNUNET_free (eddsa_priv);
    return 3;
  }

  kv.purpose.purpose = htonl (TALER_SIGNATURE_AUDITOR_EXCHANGE_KEYS);
  kv.purpose.size = htonl (sizeof (struct TALER_ExchangeKeyValidityPS));
  GNUNET_CRYPTO_hash (auditor_url,
                      strlen (auditor_url) + 1,
                      &kv.auditor_url_hash);
  kv.master = master_public_key;
  dks = GNUNET_new_array (dks_len,
                          struct TALER_DenominationKeyValidityPS);
  sigs = GNUNET_new_array (dks_len,
                           struct TALER_AuditorSignatureP);
  if (in_size !=
      GNUNET_DISK_file_read (fh,
                             dks,
                             in_size))
  {
    fprintf (stderr,
             "Failed to read input file `%s': %s\n",
             exchange_request_file,
             strerror (errno));
    TALER_AUDITORDB_plugin_unload (adb);
    GNUNET_DISK_file_close (fh);
    GNUNET_free (sigs);
    GNUNET_free (dks);
    GNUNET_free (eddsa_priv);
    return 1;
  }
  GNUNET_DISK_file_close (fh);
  for (unsigned int i = 0; i<dks_len; i++)
  {
    struct TALER_DenominationKeyValidityPS *dk = &dks[i];

    if (verbose)
      print_dk (dk);
    kv.start = dk->start;
    kv.expire_withdraw = dk->expire_withdraw;
    kv.expire_deposit = dk->expire_deposit;
    kv.expire_legal = dk->expire_legal;
    kv.value = dk->value;
    kv.fee_withdraw = dk->fee_withdraw;
    kv.fee_deposit = dk->fee_deposit;
    kv.fee_refresh = dk->fee_refresh;
    kv.fee_refund = dk->fee_refund;
    kv.denom_hash = dk->denom_hash;

    /* Finally sign ... */
    GNUNET_assert (GNUNET_OK ==
                   GNUNET_CRYPTO_eddsa_sign (eddsa_priv,
                                             &kv.purpose,
                                             &sigs[i].eddsa_sig));
  }

  if (NULL == output_file)
  {
    fprintf (stderr,
             "Output file not given\n");
    TALER_AUDITORDB_plugin_unload (adb);
    GNUNET_free (dks);
    GNUNET_free (sigs);
    GNUNET_free (eddsa_priv);
    return 1;
  }

  /* Create required tables */
  if (GNUNET_OK !=
      adb->create_tables (adb->cls))
  {
    fprintf (stderr,
             "Failed to create tables in auditor's database\n");
    TALER_AUDITORDB_plugin_unload (adb);
    GNUNET_free (dks);
    GNUNET_free (sigs);
    GNUNET_free (eddsa_priv);
    return 3;
  }


  /* Update DB */
  {
    enum GNUNET_DB_QueryStatus qs;
    struct TALER_AUDITORDB_Session *session;

    session = adb->get_session (adb->cls);
    if (NULL == session)
    {
      fprintf (stderr,
               "Failed to initialize database session\n");
      TALER_AUDITORDB_plugin_unload (adb);
      GNUNET_free (dks);
      GNUNET_free (sigs);
      GNUNET_free (eddsa_priv);
      return 3;
    }
    for (unsigned int i = 0; i<dks_len; i++)
    {
      const struct TALER_DenominationKeyValidityPS *dk = &dks[i];

      qs = adb->insert_denomination_info (adb->cls,
                                          session,
                                          dk);
      if (0 > qs)
      {
        fprintf (stderr,
                 "Failed to store key in auditor DB (did you add the exchange using taler-auditor-exchange first?)\n");
        TALER_AUDITORDB_plugin_unload (adb);
        GNUNET_free (dks);
        GNUNET_free (sigs);
        GNUNET_free (eddsa_priv);
        return 3;
      }
    }
  }
  TALER_AUDITORDB_plugin_unload (adb);

  /* write result to disk */
  if (GNUNET_OK !=
      TALER_EXCHANGEDB_auditor_write (output_file,
                                      &apub,
                                      auditor_url,
                                      sigs,
                                      &master_public_key,
                                      dks_len,
                                      dks))
  {
    fprintf (stderr,
             "Failed to write to file `%s': %s\n",
             output_file,
             strerror (errno));
    GNUNET_free (sigs);
    GNUNET_free (dks);
    return 1;
  }
  GNUNET_free (sigs);
  GNUNET_free (dks);
  GNUNET_free (eddsa_priv);
  return 0;
}


/* end of taler-auditor-sign.c */
