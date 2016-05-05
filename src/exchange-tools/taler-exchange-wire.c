/*
  This file is part of TALER
  Copyright (C) 2015, 2016 Inria

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
static char *json_in;

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
  json_t *j;
  json_error_t err;
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
  if (NULL == json_in)
  {
    fprintf (stderr,
             "Required -j argument missing\n");
    global_ret = 1;
    return;
  }
  if (NULL == method)
  {
    fprintf (stderr,
             "Required -t argument missing\n");
    global_ret = 1;
    return;
  }
  j = json_loads (json_in,
                  JSON_REJECT_DUPLICATES,
                  &err);
  if (NULL == j)
  {
    fprintf (stderr,
             "Failed to parse JSON: %s (at offset %u)\n",
             err.text,
             (unsigned int) err.position);
    global_ret = 1;
    return;
  }
  json_object_set_new (j,
                       "type",
                       json_string (method));
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
    global_ret = 1;
    return;
  }
  if (GNUNET_OK !=
      plugin->sign_wire_details (plugin->cls,
                                 j,
                                 &key,
                                 &salt,
                                 &sig))
  {
    /* sign function should have logged applicable errors */
    json_decref (j);
    TALER_WIRE_plugin_unload (plugin);
    global_ret = 1;
    return;
  }
  TALER_WIRE_plugin_unload (plugin);
  GNUNET_free (eddsa_priv);

  /* add signature and salt to JSON message */
  json_object_set_new (j,
                       "salt",
                       GNUNET_JSON_from_data (&salt,
                                              sizeof (salt)));
  json_object_set_new (j,
                       "sig",
                       GNUNET_JSON_from_data (&sig,
                                              sizeof (sig)));

  /* dump result to stdout */
  json_out = json_dumps (j, JSON_INDENT(2));
  json_decref (j);
  GNUNET_assert (NULL != json_out);

  if (NULL != output_filename)
  {
    fclose (stdout);
    stdout = fopen (output_filename,
		    "w+");
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
    {'j', "json", "JSON",
     "account information in JSON format", 1,
     &GNUNET_GETOPT_set_string, &json_in},
    {'m', "master-key", "FILE",
     "master key file (private key)", 1,
     &GNUNET_GETOPT_set_filename, &masterkeyfile},
    {'t', "type", "METHOD",
     "which wire transfer method (i.e. 'test' or 'sepa') is this for?", 1,
     &GNUNET_GETOPT_set_string, &method},
    {'o', "output", "FILE",
     "where to write the result", 1,
     &GNUNET_GETOPT_set_filename, &output_filename},
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
