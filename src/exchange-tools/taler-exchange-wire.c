/*
  This file is part of TALER
  Copyright (C) 2015, 2016, 2017 Inria

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
 * @file taler-exchange-wire.c
 * @brief Create signed response for /wire requests.
 * @author Christian Grothoff
 */
#include <platform.h>
#include <jansson.h>
#include <gnunet/gnunet_json_lib.h>
#include "taler_crypto_lib.h"
#include "taler_util.h"
#include "taler_wire_lib.h"
#include "taler_signatures.h"


/**
 * Filename of the master private key.
 */
static char *masterkeyfile;

/**
 * Account holder information in JSON format.
 */
static json_t *account_holder;

/**
 * Which wire method is this for?
 */
static char *method;

/**
 * Where to write the result.
 */
static char *output_filename;

/**
 * Return value from main().
 */
static int global_ret;


/**
 * Main function that will be run.
 *
 * @param cls closure
 * @param args remaining command-line arguments
 * @param cfgfile name of the configuration file used (for saving, can be NULL!)
 * @param c configuration
 */
static void
run (void *cls,
     char *const *args,
     const char *cfgfile,
     const struct GNUNET_CONFIGURATION_Handle *cfg)
{
  struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_priv;
  struct TALER_MasterPrivateKeyP key;
  struct TALER_MasterSignatureP sig;
  char *json_out;
  struct GNUNET_HashCode salt;
  struct TALER_WIRE_Plugin *plugin;

  if ( (NULL == masterkeyfile) &&
       (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                 "exchange",
                                                 "MASTER_PRIV_FILE",
                                                 &masterkeyfile)) )
  {
    fprintf (stderr,
             "Master key file not given in neither configuration nor command-line\n");
    global_ret = 1;
    return;
  }
  if (GNUNET_YES != GNUNET_DISK_file_test (masterkeyfile))
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Exchange master private key `%s' does not exist yet, creating it!\n",
                masterkeyfile);
  eddsa_priv = GNUNET_CRYPTO_eddsa_key_create_from_file (masterkeyfile);
  if (NULL == eddsa_priv)
  {
    fprintf (stderr,
             "Failed to initialize master key from file `%s'\n",
             masterkeyfile);
    global_ret = 1;
    return;
  }
  if (NULL == method)
  {
    json_t *test;
    const char *m;

    test = json_object_get(account_holder,
                           "type");
    if ( (NULL == test) ||
         (NULL == (m = json_string_value (test))))
    {
      fprintf (stderr,
               "Required -t argument missing\n");
      global_ret = 1;
      return;
    }
    method = GNUNET_strdup (m);
  }
  else
  {
    json_object_set_new (account_holder,
                         "type",
                         json_string (method));
  }
  key.eddsa_priv = *eddsa_priv;
  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                              &salt,
                              sizeof (salt));
  plugin = TALER_WIRE_plugin_load (cfg,
                                   method);
  if (NULL == plugin)
  {
    GNUNET_log (GNUNET_ERROR_TYPE_INFO,
                "Wire transfer method `%s' not supported\n",
                method);
    GNUNET_free (method);
    global_ret = 1;
    return;
  }
  GNUNET_free (method);
  if (GNUNET_OK !=
      plugin->sign_wire_details (plugin->cls,
                                 account_holder,
                                 &key,
                                 &salt,
                                 &sig))
  {
    /* sign function should have logged applicable errors */
    json_decref (account_holder);
    TALER_WIRE_plugin_unload (plugin);
    global_ret = 1;
    return;
  }
  TALER_WIRE_plugin_unload (plugin);
  GNUNET_free (eddsa_priv);

  /* add signature and salt to JSON message */
  json_object_set_new (account_holder,
                       "salt",
                       GNUNET_JSON_from_data (&salt,
                                              sizeof (salt)));
  json_object_set_new (account_holder,
                       "sig",
                       GNUNET_JSON_from_data (&sig,
                                              sizeof (sig)));

  /* dump result to stdout */
  json_out = json_dumps (account_holder,
                         JSON_INDENT(2));
  json_decref (account_holder);
  GNUNET_assert (NULL != json_out);

  if (NULL != output_filename)
  {
    if (NULL != stdout)
      fclose (stdout);
    stdout = fopen (output_filename,
		    "w+");
    if (NULL == stdout)
    {
      fprintf (stderr,
               "Failed to open `%s': %s\n",
               output_filename,
               STRERROR (errno));
      return;
    }
  }
  fprintf (stdout,
	   "%s",
	   json_out);
  fflush (stdout);
  free (json_out);
}


/**
 * The main function of the taler-exchange-wire tool.  This tool is
 * used to sign the bank account details using the master key.
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
    GNUNET_GETOPT_OPTION_MANDATORY
    (GNUNET_JSON_getopt ('j',
                         "json",
                         "JSON",
                         "account information in JSON format",
                         &account_holder)),
    GNUNET_GETOPT_OPTION_FILENAME ('m',
                                   "master-key",
                                   "FILENAME",
                                   "master key file (private key)",
                                   &masterkeyfile),
    GNUNET_GETOPT_OPTION_STRING ('t',
                                 "type",
                                 "METHOD",
                                 "which wire transfer method (i.e. 'test' or 'sepa') is this for?",
                                 &method),
    GNUNET_GETOPT_OPTION_FILENAME ('o',
                                   "output",
                                   "FILENAME",
                                   "where to write the result",
                                   &output_filename),
    GNUNET_GETOPT_OPTION_END
  };

  /* force linker to link against libtalerutil; if we do
     not do this, the linker may "optimize" libtalerutil
     away and skip #TALER_OS_init(), which we do need */
  (void) TALER_project_data_default ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-exchange-wire",
                                   "WARNING",
                                   NULL));
  if (GNUNET_OK !=
      GNUNET_PROGRAM_run (argc, argv,
			  "taler-exchange-wire",
			  "Setup /wire response",
			  options,
			  &run, NULL))
    return 1;
  return global_ret;
}


/* end of taler-exchange-wire.c */
