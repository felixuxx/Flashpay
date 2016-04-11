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
#include "taler_wire_plugin.h"
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
 * Our configuration.
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;


/**
 * The main function of the taler-exchange-sepa tool.  This tool is used
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
  char *cfgfile = NULL;
  const struct GNUNET_GETOPT_CommandLineOption options[] = {
    GNUNET_GETOPT_OPTION_CFG_FILE (&cfgfile),
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
    GNUNET_GETOPT_OPTION_HELP ("Setup /wire response"),
    GNUNET_GETOPT_OPTION_VERSION (VERSION "-" VCS_VERSION),
    GNUNET_GETOPT_OPTION_END
  };
  struct GNUNET_CRYPTO_EddsaPrivateKey *eddsa_priv;
  struct TALER_MasterPrivateKeyP key;
  struct TALER_MasterSignatureP sig;
  json_t *j;
  json_error_t err;
  char *json_out;
  struct GNUNET_HashCode salt;
  struct TALER_WIRE_Plugin *plugin;

  GNUNET_assert (GNUNET_OK ==
                 GNUNET_log_setup ("taler-exchange-wire",
                                   "WARNING",
                                   NULL));

  if (GNUNET_GETOPT_run ("taler-exchange-wire",
                         options,
                         argc, argv) < 0)
    return 1;
  cfg = GNUNET_CONFIGURATION_create ();
  if (GNUNET_SYSERR == GNUNET_CONFIGURATION_load (cfg,
                                                  cfgfile))
  {
    GNUNET_log (GNUNET_ERROR_TYPE_ERROR,
                _("Malformed configuration file `%s', exit ...\n"),
                cfgfile);
    GNUNET_free_non_null (cfgfile);
    return 1;
  }
  GNUNET_free_non_null (cfgfile);
  if ( (NULL == masterkeyfile) &&
       (GNUNET_OK !=
        GNUNET_CONFIGURATION_get_value_filename (cfg,
                                                 "exchange-master",
                                                 "MASTER_PRIV_FILE",
                                                 &masterkeyfile)) )
  {
    fprintf (stderr,
             "Master key file not given in neither configuration nor command-line\n");
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
  if (NULL == json_in)
  {
    fprintf (stderr,
             "Required -j argument missing\n");
    return 1;
  }
  if (NULL == method)
  {
    fprintf (stderr,
             "Required -t argument missing\n");
    return 1;
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
    return 1;
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
    return 1;
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
    return 1;
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
  return 0;
}

/* end of taler-exchange-wire.c */
