/*
  This file is part of TALER
  (C) 2015, 2016 GNUnet e.V. and Inria

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
 * @file wire/test_wire_plugin.c
 * @brief Tests for wire plugins
 * @author Christian Grothoff
 * @author Sree Harsha Totakura <sreeharsha@totakura.in>
 */
#include "platform.h"
#include "taler_util.h"
#include "taler_wire_lib.h"
#include "taler_wire_plugin.h"
#include <gnunet/gnunet_json_lib.h>
#include <jansson.h>


/**
 * Definitions for a test with a plugin.
 */
struct TestBlock {

  /**
   * Name of the plugin to test.
   */
  const char *plugin_name;

  /**
   * JSON template expected by the plugin for an account definition.
   */
  const char *json_proto;

  /**
   * Amount to give to the rounding function.
   */
  const char *round_in;

  /**
   * Expected result from rounding.
   */
  const char *round_out;

};


/**
 * List of plugins and (unsigned) JSON account definitions
 * to use for the tests.
 */
static struct TestBlock tests[] = {
  {
    .plugin_name = "sepa",
    .json_proto = "{  \"type\":\"sepa\", \"iban\":\"DE67830654080004822650\", \"name\":\"GNUnet e.V.\", \"bic\":\"GENODEF1SLR\" }",
    .round_in = "EUR:0.123456",
    .round_out = "EUR:0.12",
  },
  {
    .plugin_name = "test",
    .json_proto = "{  \"type\":\"test\", \"bank_uri\":\"http://localhost/\", \"account_number\":42 }",
    .round_in = "KUDOS:0.123456",
    .round_out = "KUDOS:0.12",
  },
  {
    NULL, NULL, NULL, NULL
  }
};


/**
 * Private key used to sign wire details.
 */
static struct TALER_MasterPrivateKeyP priv_key;

/**
 * Public key matching #priv_key.
 */
static struct TALER_MasterPublicKeyP pub_key;

/**
 * Our configuration.
 */
static struct GNUNET_CONFIGURATION_Handle *cfg;


/**
 * Run the test.
 *
 * @param test details of the test
 * @param plugin plugin to test
 * @param wire wire details for testing
 * @return #GNUNET_OK on success
 */
static int
run_test (const struct TestBlock *test,
          struct TALER_WIRE_Plugin *plugin,
          json_t *wire)
{
  struct GNUNET_HashCode salt;
  struct TALER_MasterSignatureP sig;
  json_t *lwire;
  struct TALER_Amount in;
  struct TALER_Amount expect;

  GNUNET_CRYPTO_random_block (GNUNET_CRYPTO_QUALITY_NONCE,
                              &salt,
                              sizeof (salt));
  if (GNUNET_OK !=
      plugin->sign_wire_details (plugin->cls,
                                 wire,
                                 &priv_key,
                                 &salt,
                                 &sig))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  json_object_set_new (wire,
                       "salt",
                       GNUNET_JSON_from_data (&salt,
                                              sizeof (salt)));
  json_object_set_new (wire,
                       "sig",
                       GNUNET_JSON_from_data (&sig,
                                              sizeof (sig)));
  if (GNUNET_OK !=
      plugin->wire_validate (plugin->cls,
                             wire,
                             &pub_key))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  /* load wire details from file */
  lwire = plugin->get_wire_details (plugin->cls,
                                    cfg,
                                    test->plugin_name);
  if (NULL == lwire)
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_OK !=
      plugin->wire_validate (plugin->cls,
                             lwire,
                             &pub_key))
  {
    GNUNET_break (0);
    json_decref (lwire);
    return GNUNET_SYSERR;
  }
  json_decref (lwire);
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (test->round_in,
                                         &in));
  GNUNET_assert (GNUNET_OK ==
                 TALER_string_to_amount (test->round_out,
                                         &expect));
  if (GNUNET_OK !=
      plugin->amount_round (plugin->cls,
                            &in))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (0 != TALER_amount_cmp (&in, &expect))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  if (GNUNET_NO !=
      plugin->amount_round (plugin->cls,
                            &in))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  memset (&in, 0, sizeof (in));
  if (GNUNET_SYSERR !=
      plugin->amount_round (plugin->cls,
                            &in))
  {
    GNUNET_break (0);
    return GNUNET_SYSERR;
  }
  return GNUNET_OK;
}


int
main (int argc,
      const char *const argv[])
{
  json_t *wire;
  int ret;
  struct TALER_WIRE_Plugin *plugin;
  const struct TestBlock *test;
  unsigned int i;
  struct GNUNET_CRYPTO_EddsaPrivateKey *pk;

  GNUNET_log_setup ("test-wire-plugin",
                    "WARNING",
                    NULL);
  cfg = GNUNET_CONFIGURATION_create ();
  GNUNET_assert (GNUNET_OK ==
                 GNUNET_CONFIGURATION_load (cfg,
                                            "test_wire_plugin.conf"));
  pk = GNUNET_CRYPTO_eddsa_key_create_from_file ("test_wire_plugin_key.priv");
  priv_key.eddsa_priv = *pk;
  GNUNET_free (pk);
  GNUNET_CRYPTO_eddsa_key_get_public (&priv_key.eddsa_priv,
                                      &pub_key.eddsa_pub);
  ret = GNUNET_OK;
  for (i=0;NULL != (test = &tests[i])->plugin_name;i++)
  {
    plugin = TALER_WIRE_plugin_load (cfg,
                                     test->plugin_name);
    GNUNET_assert (NULL != plugin);
    wire = json_loads (test->json_proto, 0, NULL);
    GNUNET_assert (NULL != wire);
    ret = run_test (test, plugin, wire);
    json_decref (wire);
    TALER_WIRE_plugin_unload (plugin);
    if (GNUNET_OK != ret)
    {
      fprintf (stdout,
               "%s FAILED\n",
               test->plugin_name);
      break;
    }
    else
    {
      fprintf (stdout,
               "%s PASS\n",
               test->plugin_name);
    }
  }
  GNUNET_CONFIGURATION_destroy (cfg);
  if (GNUNET_NO == ret)
    return 1;
  return 0;
}
